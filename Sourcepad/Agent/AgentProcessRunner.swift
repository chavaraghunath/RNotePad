// SPDX-License-Identifier: MIT
// Sourcepad — subprocess line streamer shared by all one-shot agent adapters.
//
// Spawns a CLI, feeds stdout to a per-line JSON handler as data arrives, and
// reports termination. Adapters supply argv + an event parser; this handles the
// process plumbing (async stdout reads, line buffering, cancel, stderr capture).
//
// Foundation-only.

import Foundation

/// A one-shot agent subprocess emitting newline-delimited JSON on stdout.
public final class AgentProcessRunner: AgentTurnHandle {

    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var stdoutBuffer = Data()
    private var stderrText = ""
    private let lock = NSLock()
    private var finished = false
    /// Keep the runner alive for the lifetime of the subprocess even if the
    /// caller drops the returned handle — a live turn must not die early.
    private var selfRetain: AgentProcessRunner?

    /// Called (main queue) for each complete stdout line that parses as JSON.
    private let onLine: ([String: Any]) -> Void
    /// Called (main queue) for each complete stdout line as a raw string,
    /// regardless of whether it is JSON. Used by text-output CLIs (e.g. agy)
    /// that stream a plain-text answer rather than newline-delimited JSON.
    private let onRawLine: ((String) -> Void)?
    /// Called (main queue) once when the process exits. `code` is the exit
    /// status; `stderr` is whatever the process wrote to stderr.
    private let onExit: (_ code: Int32, _ stderr: String) -> Void

    public init(executable: URL,
                arguments: [String],
                workingDirectory: String,
                environment: [String: String]? = nil,
                stdin: String? = nil,
                onLine: @escaping ([String: Any]) -> Void,
                onRawLine: ((String) -> Void)? = nil,
                onExit: @escaping (_ code: Int32, _ stderr: String) -> Void) {
        self.onLine = onLine
        self.onRawLine = onRawLine
        self.onExit = onExit

        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.environment = environment ?? Self.inheritedEnvironment()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Either pipe a prompt in or close stdin so CLIs (e.g. codex exec) don't
        // block waiting for piped input.
        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            inPipe.fileHandleForWriting.closeFile()
        } else {
            process.standardInput = FileHandle.nullDevice
        }
    }

    /// Spawn the process and begin streaming. Returns false if spawn failed.
    @discardableResult
    public func start() -> Bool {
        selfRetain = self
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.ingest(chunk)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else { return }
            self.lock.lock(); self.stderrText += String(decoding: chunk, as: UTF8.self); self.lock.unlock()
        }
        process.terminationHandler = { [weak self] proc in
            self?.handleTermination(code: proc.terminationStatus)
        }
        do {
            try process.run()
            return true
        } catch {
            selfRetain = nil
            DispatchQueue.main.async { [weak self] in
                self?.onExit(-1, "spawn failed: \(error.localizedDescription)")
            }
            return false
        }
    }

    public func cancel() {
        lock.lock(); let done = finished; lock.unlock()
        guard !done, process.isRunning else { return }
        process.terminate()
    }

    // MARK: - Stream plumbing

    private func ingest(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        // Split on newlines; keep the trailing partial in the buffer.
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<nl)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nl)
            deliver(lineData)
        }
    }

    private func deliver(_ lineData: Data) {
        guard !lineData.isEmpty else { return }
        // Raw-text consumers see every line as-is.
        if let onRawLine {
            let s = String(decoding: lineData, as: UTF8.self)
            DispatchQueue.main.async { onRawLine(s) }
        }
        // JSON consumers see only lines that parse as a JSON object.
        if let obj = try? JSONSerialization.jsonObject(with: lineData),
           let dict = obj as? [String: Any] {
            DispatchQueue.main.async { [weak self] in self?.onLine(dict) }
        }
    }

    private func handleTermination(code: Int32) {
        // Flush any trailing line without a newline.
        if !stdoutBuffer.isEmpty {
            let tail = stdoutBuffer
            stdoutBuffer.removeAll()
            deliver(tail)
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        lock.lock(); finished = true; let err = stderrText; lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onExit(code, err)
            self?.selfRetain = nil   // release after delivering the final event
        }
    }

    // MARK: - Environment

    /// A PATH-enriched copy of the current environment so spawned CLIs can find
    /// node / their own helpers even when Sourcepad was launched from Finder.
    static func inheritedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                     "\(NSHomeDirectory())/.local/bin"]
        let current = env["PATH"] ?? ""
        let parts = current.split(separator: ":").map(String.init)
        let merged = (parts + extra.filter { !parts.contains($0) }).joined(separator: ":")
        env["PATH"] = merged
        return env
    }
}
