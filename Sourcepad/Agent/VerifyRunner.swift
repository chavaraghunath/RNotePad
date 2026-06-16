// SPDX-License-Identifier: MIT
// Sourcepad — runs a VerifyPlan's steps and reports pass/fail + output.
//
// Each step runs through the user's login shell (so the full dev PATH — nvm,
// pyenv, etc. — is available) in the workspace directory. Steps run in order and
// stop at the first failure (a failed build makes the tests moot). Output is
// captured (combined stdout+stderr) and capped so a noisy build can't bloat the UI.

import Foundation

public final class VerifyRunner {

    public struct StepResult {
        public let step: VerifyPlan.Step
        public let exitCode: Int32
        public let output: String
        public var passed: Bool { exitCode == 0 }
    }

    private let plan: VerifyPlan
    private let workingDirectory: String
    private let maxOutputBytes = 16 * 1024
    private var cancelled = false
    private var current: Process?

    public init(plan: VerifyPlan, workingDirectory: String) {
        self.plan = plan
        self.workingDirectory = workingDirectory
    }

    /// Run all steps in order. `onStep` fires (main queue) as each finishes;
    /// `onFinish(allPassed, results)` fires once at the end. Stops at the first
    /// failing step.
    public func run(onStep: @escaping (StepResult) -> Void,
                    onFinish: @escaping (_ allPassed: Bool, _ results: [StepResult]) -> Void) {
        // Capture self strongly so the run completes even if the caller doesn't
        // retain the runner (the async work keeps it alive until it finishes).
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [StepResult] = []
            var allPassed = true
            for step in self.plan.steps {
                if self.cancelled { break }
                let (code, out) = self.runOne(step.command)
                let r = StepResult(step: step, exitCode: code, output: out)
                results.append(r)
                DispatchQueue.main.async { onStep(r) }
                if !r.passed { allPassed = false; break }
            }
            let passed = allPassed && !results.isEmpty && !self.cancelled
            DispatchQueue.main.async { onFinish(passed, results) }
        }
    }

    public func cancel() {
        cancelled = true
        current?.terminate()
    }

    // MARK: - Internals

    private func runOne(_ command: String) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.loginShell())
        p.arguments = ["-lc", command]
        p.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        p.environment = AgentProcessRunner.inheritedEnvironment()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice

        // A single reader thread (the readability handler, which GCD never runs
        // concurrently with itself) owns `data`; the semaphore signalled at EOF
        // gives the waiting thread a happens-before edge before it reads `data`.
        // This avoids the prior race between the handler and a post-exit drain.
        var data = Data()
        let handle = pipe.fileHandleForReading
        let done = DispatchSemaphore(value: 0)
        handle.readabilityHandler = { h in
            let chunk = h.availableData
            if chunk.isEmpty {
                h.readabilityHandler = nil
                done.signal()
            } else {
                data.append(chunk)
            }
        }
        current = p
        do { try p.run() } catch {
            handle.readabilityHandler = nil
            return (-1, "failed to launch: \(error.localizedDescription)")
        }
        p.waitUntilExit()
        done.wait()   // wait for the reader to drain through EOF
        current = nil

        var text = String(decoding: data, as: UTF8.self)
        if text.utf8.count > maxOutputBytes {
            text = "… (output truncated)\n" + String(text.suffix(maxOutputBytes / 2))
        }
        return (p.terminationStatus, text)
    }

    private static func loginShell() -> String {
        if let s = ProcessInfo.processInfo.environment["SHELL"],
           !s.isEmpty, FileManager.default.isExecutableFile(atPath: s) { return s }
        return "/bin/zsh"
    }
}
