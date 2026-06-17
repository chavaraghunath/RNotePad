// SPDX-License-Identifier: MIT
// Sourcepad — headless runner for CLI install / update / uninstall / sign-in.
//
// Runs a shell command through the user's LOGIN shell (`-lc`) so PATH, pipes
// (`curl … | bash`) and package managers resolve exactly as they would in a real
// terminal, then streams combined stdout+stderr back line-by-line for a live
// progress log. The caller decides what "success" means: for installs it
// re-probes the registry; for sign-in it re-checks `CLIAuthStatus`.
//
// Non-interactive env hints (NONINTERACTIVE / HOMEBREW_NO_AUTO_UPDATE / CI) keep
// brew + npm from prompting or paging, which would otherwise hang a headless run.
// Mirrors the streaming pattern in MLXModelManager.pull.

import Foundation

public final class CLIInstaller {

    /// A running job. `cancel()` terminates the shell subprocess.
    public final class Job {
        private let process: Process
        private let lock = NSLock()
        private var finished = false
        fileprivate init(_ p: Process) { process = p }

        public func cancel() {
            lock.lock(); let done = finished; lock.unlock()
            guard !done, process.isRunning else { return }
            process.interrupt()
            // Escalate if it ignores SIGINT.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak process] in
                if process?.isRunning == true { process?.terminate() }
            }
        }
        fileprivate func markFinished() { lock.lock(); finished = true; lock.unlock() }
    }

    /// Run `shellCommand` headlessly. `progress` fires on the main queue per
    /// output chunk (newlines and carriage returns split into lines);
    /// `completion(success)` fires on the main queue with the exit status.
    @discardableResult
    public static func run(shellCommand: String,
                           progress: @escaping (String) -> Void,
                           completion: @escaping (Bool) -> Void) -> Job {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: loginShell())
        p.arguments = ["-lc", shellCommand]

        var env = AgentProcessRunner.inheritedEnvironment()
        env["NONINTERACTIVE"] = "1"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["CI"] = "1"
        env["TERM"] = "dumb"
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        let job = Job(p)
        let done = DispatchSemaphore(value: 0)
        var carry = ""   // partial line buffer (handler may split mid-line)

        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; done.signal(); return }
            let chunk = String(decoding: d, as: UTF8.self)
            carry += chunk
            // Emit complete lines; keep any trailing partial for the next chunk.
            let parts = carry.components(separatedBy: CharacterSet(charactersIn: "\n\r"))
            carry = parts.last ?? ""
            for line in parts.dropLast() {
                let s = line.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { DispatchQueue.main.async { progress(s) } }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async { progress("$ \(shellCommand)") }
            do {
                try p.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                job.markFinished()
                DispatchQueue.main.async {
                    progress("launch failed: \(error.localizedDescription)")
                    completion(false)
                }
                return
            }
            p.waitUntilExit()
            done.wait()   // drain through EOF so the final line isn't lost
            job.markFinished()
            let tail = carry.trimmingCharacters(in: .whitespaces)
            let ok = p.terminationStatus == 0
            DispatchQueue.main.async {
                if !tail.isEmpty { progress(tail) }
                progress(ok ? "✓ Done." : "✗ Exited with status \(p.terminationStatus).")
                completion(ok)
            }
        }
        return job
    }

    /// The user's login shell, so profile-defined PATH entries (nvm, pyenv, …)
    /// are visible. Falls back to zsh.
    private static func loginShell() -> String {
        if let s = ProcessInfo.processInfo.environment["SHELL"], !s.isEmpty,
           FileManager.default.isExecutableFile(atPath: s) { return s }
        return "/bin/zsh"
    }
}
