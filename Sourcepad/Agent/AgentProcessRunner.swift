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
    /// PTY fds backing the child's stdin (when not piping a prompt in), so that
    /// TTY-requiring commands the agent runs (e.g. `docker run -it`) see a
    /// terminal. Closed right after launch so stdin also yields EOF (no hang).
    private var ptyMaster: Int32 = -1
    private var ptySlave: Int32 = -1
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

        // Either pipe a prompt in, or give the child a PTY-backed stdin so the
        // agent (and the commands it runs) detect a terminal and TTY-requiring
        // tools like `docker run -it` work — while stdout stays a pipe for clean
        // JSON. Falls back to /dev/null if a PTY can't be allocated.
        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            inPipe.fileHandleForWriting.closeFile()
        } else if let (master, slave) = Self.makePTY() {
            ptyMaster = master
            ptySlave = slave
            process.standardInput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        } else {
            process.standardInput = FileHandle.nullDevice
        }
    }

    /// Allocate a pseudo-terminal master/slave pair. The slave becomes the
    /// child's stdin (a real tty); both ends are closed right after launch so
    /// reads on stdin also see EOF and never block.
    private static func makePTY() -> (master: Int32, slave: Int32)? {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let name = ptsname(master) else {
            if master >= 0 { close(master) }
            return nil
        }
        let slave = open(name, O_RDWR | O_NOCTTY)
        guard slave >= 0 else { close(master); return nil }
        return (master, slave)
    }

    /// Close any PTY fds we opened for the child's stdin (after the child has
    /// dup'd them during launch). Idempotent.
    private func closePTY() {
        if ptySlave >= 0 { close(ptySlave); ptySlave = -1 }
        if ptyMaster >= 0 { close(ptyMaster); ptyMaster = -1 }
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
            // The child has dup'd the PTY slave; close our copies so stdin also
            // sees EOF (a real tty, but no blocking) and we don't leak fds.
            closePTY()
            return true
        } catch {
            closePTY()
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
        // `stdoutBuffer` is touched by both this stdout handler and
        // handleTermination (different threads) — guard it with `lock`. Deliver
        // outside the lock so we never hold it across a dispatch.
        var lines: [Data] = []
        lock.lock()
        stdoutBuffer.append(chunk)
        // Split on newlines; keep the trailing partial in the buffer.
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<nl)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nl)
            lines.append(lineData)
        }
        lock.unlock()
        for lineData in lines { deliver(lineData) }
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
        // Flush any trailing line without a newline. Snapshot under the lock so
        // we don't race a concurrent ingest() on stdoutBuffer.
        lock.lock()
        let tail = stdoutBuffer
        stdoutBuffer.removeAll()
        lock.unlock()
        if !tail.isEmpty { deliver(tail) }
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
