// SPDX-License-Identifier: MIT
// Sourcepad — JSON-RPC over stdio Language Server Protocol client.
//
// One LSPClient = one running language server process. The lifecycle is
// owned by LSPServerManager which creates clients on demand (per-workspace,
// per-language) and tears them down when the last document for that
// (workspace, language) pair closes.
//
// Threading model:
//   - One serial queue per client owns ALL pipe I/O and the pending-callback
//     table. The readability handler fires on that queue; writes go through
//     it via `queue.async`.
//   - Public methods are safe to call from any thread; they hop onto the
//     internal queue when needed.
//   - Delegate callbacks (notifications) dispatch to the main queue.
//
// JSON-RPC framing per LSP 3.17:
//   Content-Length: N\r\n
//   Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n  (optional)
//   \r\n
//   <N bytes of UTF-8 JSON>
//
// Refs:
//   https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/

import Foundation

public protocol LSPClientDelegate: AnyObject {
    /// Server sent a notification (no id field). Method + raw params JSON.
    /// Delegate is invoked on the main queue.
    func lsp(_ client: LSPClient,
             didReceiveNotification method: String,
             params: Any?)

    /// Server sent a request (has id + method). Delegate must call
    /// client.respond(toID:result:) or client.respond(toID:error:).
    func lsp(_ client: LSPClient,
             didReceiveRequest method: String,
             id: LSPID,
             params: Any?)

    /// Server stderr or exit notification.
    func lsp(_ client: LSPClient, didLog message: String)
    func lsp(_ client: LSPClient, didExit code: Int32)
}

/// JSON-RPC id type — either an Int or a String. We always send Int.
public enum LSPID: Hashable {
    case int(Int)
    case string(String)
}

public final class LSPClient {

    public weak var delegate: LSPClientDelegate?

    public let serverID: String
    public let executable: URL
    public let arguments: [String]

    private let queue: DispatchQueue
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var receiveBuffer = Data()
    private var nextRequestID: Int = 1
    private var pendingResponses: [Int: (Result<Any?, LSPError>) -> Void] = [:]
    private var isRunning: Bool = false

    public init(serverID: String, executable: URL, arguments: [String] = []) {
        self.serverID = serverID
        self.executable = executable
        self.arguments = arguments
        self.queue = DispatchQueue(label: "sourcepad.lsp.\(serverID)",
                                   qos: .utility)
    }

    // MARK: - Lifecycle

    /// Spawn the server process and start reading its stdout. Returns
    /// whether the process was launched successfully.
    @discardableResult
    public func start() -> Bool {
        return queue.sync {
            guard !isRunning else { return true }
            process.executableURL = executable
            process.arguments = arguments
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.terminationHandler = { [weak self] proc in
                guard let self else { return }
                let code = proc.terminationStatus
                DispatchQueue.main.async {
                    self.delegate?.lsp(self, didExit: code)
                }
            }
            do {
                try process.run()
            } catch {
                NSLog("[Sourcepad] LSP \(serverID) failed to launch: \(error)")
                return false
            }
            isRunning = true

            // Stream stdout: dispatch raw bytes onto our serial queue, parse
            // messages, fire delegate callbacks on main.
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    // EOF — server closed its stdout.
                    handle.readabilityHandler = nil
                    return
                }
                self?.queue.async {
                    self?.appendAndParse(chunk: chunk)
                }
            }

            // Stderr → forward to delegate.log so we can see init crashes
            // / "missing executable" / etc.
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    self?.delegate?.lsp(self!, didLog: text)
                }
            }
            return true
        }
    }

    /// Send `shutdown` then `exit`, then kill the process if it doesn't
    /// quit within `gracefulTimeout` seconds.
    public func stop(gracefulTimeout: TimeInterval = 2.0) {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.sendRequestRaw(method: "shutdown", params: nil, expectsResponse: false)
            self.sendNotificationRaw(method: "exit", params: nil)
            // Give the server a moment; SIGTERM if it lingers.
            DispatchQueue.global().asyncAfter(deadline: .now() + gracefulTimeout) { [weak self] in
                guard let self else { return }
                if self.process.isRunning {
                    self.process.terminate()
                }
            }
            self.isRunning = false
            self.stdoutPipe.fileHandleForReading.readabilityHandler = nil
            self.stderrPipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    // MARK: - Public RPC

    /// Send a request. Result is delivered on the main queue.
    public func sendRequest(method: String,
                            params: [String: Any]?,
                            completion: @escaping (Result<Any?, LSPError>) -> Void) {
        queue.async {
            let id = self.nextRequestID
            self.nextRequestID += 1
            self.pendingResponses[id] = completion
            var message: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "method": method,
            ]
            if let params { message["params"] = params }
            self.writeMessage(message)
        }
    }

    /// Send a notification (no response expected).
    public func sendNotification(method: String, params: [String: Any]?) {
        queue.async {
            self.sendNotificationRaw(method: method, params: params)
        }
    }

    /// Respond to a server-originated request.
    public func respond(toID id: LSPID, result: Any?) {
        queue.async {
            var message: [String: Any] = [
                "jsonrpc": "2.0",
                "id": self.encodeID(id),
            ]
            message["result"] = result ?? NSNull()
            self.writeMessage(message)
        }
    }

    // MARK: - Internal helpers (called from `queue`)

    private func sendNotificationRaw(method: String, params: [String: Any]?) {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if let params { message["params"] = params }
        writeMessage(message)
    }

    private func sendRequestRaw(method: String, params: [String: Any]?, expectsResponse: Bool) {
        // shutdown returns a response; exit doesn't. The completion table
        // would leak if we don't register a completion here, so skip when
        // expectsResponse is false.
        let id = nextRequestID
        nextRequestID += 1
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
        ]
        if let params { message["params"] = params }
        if expectsResponse {
            // No callback — caller doesn't want it.
        }
        writeMessage(message)
    }

    private func writeMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message,
                                                     options: []) else {
            return
        }
        let header = "Content-Length: \(data.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else { return }
        let frame = headerData + data
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: frame)
        } catch {
            NSLog("[Sourcepad] LSP \(serverID) write failed: \(error)")
        }
    }

    /// Append `chunk` to the receive buffer, then drain as many complete
    /// messages as we have. A message is complete when we've read its
    /// declared Content-Length bytes after the blank-line separator.
    private func appendAndParse(chunk: Data) {
        receiveBuffer.append(chunk)
        while let msg = takeNextMessage() {
            handleMessage(msg)
        }
    }

    private func takeNextMessage() -> [String: Any]? {
        // Look for the \r\n\r\n header/body separator.
        let separator = Data("\r\n\r\n".utf8)
        guard let sepRange = receiveBuffer.range(of: separator) else { return nil }

        let headerData = receiveBuffer.subdata(in: 0..<sepRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            // Bad header bytes — drop everything up to and including the
            // separator and try to recover from the next message.
            receiveBuffer.removeSubrange(0..<sepRange.upperBound)
            return nil
        }
        var contentLength: Int = -1
        for line in headerString.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                contentLength = Int(parts[1]) ?? -1
            }
        }
        guard contentLength >= 0 else {
            receiveBuffer.removeSubrange(0..<sepRange.upperBound)
            return nil
        }
        let bodyStart = sepRange.upperBound
        let bodyEnd = bodyStart + contentLength
        guard receiveBuffer.count >= bodyEnd else { return nil }
        let bodyData = receiveBuffer.subdata(in: bodyStart..<bodyEnd)
        receiveBuffer.removeSubrange(0..<bodyEnd)

        guard let obj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private func handleMessage(_ msg: [String: Any]) {
        // Response — has "id" and either "result" or "error".
        if let id = msg["id"] as? Int,
           pendingResponses[id] != nil {
            let callback = pendingResponses.removeValue(forKey: id)
            if let errorBlob = msg["error"] as? [String: Any] {
                let code = (errorBlob["code"] as? Int) ?? -32000
                let message = (errorBlob["message"] as? String) ?? "unknown error"
                DispatchQueue.main.async {
                    callback?(.failure(LSPError(code: code, message: message)))
                }
            } else {
                let result = msg["result"]
                DispatchQueue.main.async {
                    callback?(.success(result))
                }
            }
            return
        }
        // Server request — has id + method but no callback in our table.
        if let method = msg["method"] as? String, let id = msg["id"] {
            let lid: LSPID? = (id as? Int).map(LSPID.int) ?? (id as? String).map(LSPID.string)
            if let lid {
                DispatchQueue.main.async {
                    self.delegate?.lsp(self, didReceiveRequest: method, id: lid, params: msg["params"])
                }
                return
            }
        }
        // Notification — has method, no id.
        if let method = msg["method"] as? String {
            DispatchQueue.main.async {
                self.delegate?.lsp(self, didReceiveNotification: method, params: msg["params"])
            }
        }
    }

    private func encodeID(_ id: LSPID) -> Any {
        switch id {
        case .int(let i):   return i
        case .string(let s): return s
        }
    }
}

public struct LSPError: Error {
    public let code: Int
    public let message: String
}
