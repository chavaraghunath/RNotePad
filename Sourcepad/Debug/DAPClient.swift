// SPDX-License-Identifier: MIT
// Sourcepad — Phase 33 DAP (Debug Adapter Protocol) client.
//
// Mirrors the LSP client architecture: one process per debug session,
// Content-Length framing, request/response correlation, notifications
// to a delegate.
//
// Phase 33 ships the wire-level + breakpoint plumbing. The matching
// UI (sidebar panels for variables / stack / breakpoints, step
// controls in the toolbar) lands as a follow-on Xcode-project pass —
// see DebugPaneSidebar TODO.

import Foundation

public protocol DAPClientDelegate: AnyObject {
    func dap(_ client: DAPClient, didReceiveEvent event: String, body: Any?)
    func dap(_ client: DAPClient, didLog message: String)
}

public final class DAPClient {

    public weak var delegate: DAPClientDelegate?

    public let adapter: URL
    public let arguments: [String]
    private let queue: DispatchQueue
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private var seq = 0
    private var pending: [Int: (Result<Any?, DAPError>) -> Void] = [:]
    private var buf = Data()

    public init(adapter: URL, arguments: [String] = []) {
        self.adapter = adapter
        self.arguments = arguments
        self.queue = DispatchQueue(label: "sourcepad.dap.\(adapter.lastPathComponent)")
    }

    public func start() -> Bool {
        return queue.sync {
            process.executableURL = adapter
            process.arguments = arguments
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = Pipe()
            do { try process.run() } catch { return false }
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil; return }
                self?.queue.async { self?.append(chunk) }
            }
            return true
        }
    }

    public func sendRequest(command: String, arguments: [String: Any]?,
                            completion: @escaping (Result<Any?, DAPError>) -> Void) {
        queue.async {
            self.seq += 1
            let id = self.seq
            self.pending[id] = completion
            var msg: [String: Any] = [
                "seq": id,
                "type": "request",
                "command": command,
            ]
            if let arguments { msg["arguments"] = arguments }
            self.writeMessage(msg)
        }
    }

    private func writeMessage(_ msg: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        let header = "Content-Length: \(data.count)\r\n\r\n"
        var frame = Data(header.utf8); frame.append(data)
        try? stdinPipe.fileHandleForWriting.write(contentsOf: frame)
    }

    private func append(_ chunk: Data) {
        buf.append(chunk)
        while let msg = takeMessage() {
            handle(msg)
        }
    }

    private func takeMessage() -> [String: Any]? {
        let sep = Data("\r\n\r\n".utf8)
        guard let r = buf.range(of: sep) else { return nil }
        let headerData = buf.subdata(in: 0..<r.lowerBound)
        guard let header = String(data: headerData, encoding: .utf8) else {
            buf.removeSubrange(0..<r.upperBound); return nil
        }
        var contentLength = -1
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                contentLength = Int(parts[1]) ?? -1
            }
        }
        guard contentLength >= 0, buf.count >= r.upperBound + contentLength else { return nil }
        let body = buf.subdata(in: r.upperBound..<r.upperBound + contentLength)
        buf.removeSubrange(0..<r.upperBound + contentLength)
        return (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? nil
    }

    private func handle(_ msg: [String: Any]) {
        if msg["type"] as? String == "response",
           let reqSeq = msg["request_seq"] as? Int {
            let cb = pending.removeValue(forKey: reqSeq)
            let success = msg["success"] as? Bool ?? false
            if success {
                DispatchQueue.main.async { cb?(.success(msg["body"])) }
            } else {
                let m = (msg["message"] as? String) ?? "DAP error"
                DispatchQueue.main.async { cb?(.failure(DAPError(message: m))) }
            }
        } else if msg["type"] as? String == "event",
                  let event = msg["event"] as? String {
            DispatchQueue.main.async {
                self.delegate?.dap(self, didReceiveEvent: event, body: msg["body"])
            }
        }
    }
}

public struct DAPError: Error {
    public let message: String
}
