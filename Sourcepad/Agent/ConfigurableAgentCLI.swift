// SPDX-License-Identifier: MIT
// Sourcepad — a single adapter that drives any CLI described by a CLISpec.
//
// This is how Sourcepad runs gemini, agy, and user-added CLIs without bespoke
// Swift per CLI. Invocation is built from the spec's flags; output is parsed by
// the spec's OutputMode (plain text, or Gemini's stream-json events). Continuity
// uses Sourcepad's re-seed-transcript mechanism (no native session resume yet),
// which works uniformly across CLIs.

import Foundation

public final class ConfigurableAgentCLI: AgentCLI {

    public let spec: CLISpec
    public init(spec: CLISpec) { self.spec = spec }

    public var id: String { spec.id }
    public var displayName: String { spec.displayName }
    public var executableURL: URL? { AgentExecutable.locate(spec.command) }
    public var isAvailable: Bool { executableURL != nil }

    public func discoverModels() -> [AgentModel] {
        let cliID = id
        // Prefer a live `<cmd> <modelsSubcommand>` listing when the CLI offers one.
        if let sub = spec.modelsSubcommand, let exe = executableURL {
            let models = runForLines(exe: exe, args: [sub]).compactMap { line -> AgentModel? in
                let s = line.trimmingCharacters(in: .whitespaces)
                guard !s.isEmpty, s.count < 120 else { return nil }
                return AgentModel(cliID: cliID, id: s, displayName: s)
            }
            if !models.isEmpty { return models }
        }
        return spec.models.map { AgentModel(cliID: cliID, id: $0.id, displayName: $0.label) }
    }

    @discardableResult
    public func startTurn(_ request: AgentTurnRequest,
                          onEvent: @escaping (AgentEvent) -> Void) -> AgentTurnHandle {
        let command = spec.command
        guard let exe = executableURL else {
            DispatchQueue.main.async { onEvent(.error("\(command) not installed")) }
            return NullTurnHandle()
        }

        let args = ConfigurableCLILogic.buildArguments(spec: spec, request: request)

        var finished = false
        let emit: (AgentEvent) -> Void = { ev in
            if case .turnFinished = ev { finished = true }
            if case .error = ev { finished = true }
            onEvent(ev)
        }
        let onExit: (Int32, String) -> Void = { code, stderr in
            guard !finished else { return }
            if code == 0 { onEvent(.turnFinished(stopReason: nil)) }
            else { onEvent(.error(stderr.isEmpty ? "\(command) exited \(code)" : stderr)) }
        }

        let runner: AgentProcessRunner
        switch spec.output {
        case .geminiStreamJSON:
            runner = AgentProcessRunner(
                executable: exe, arguments: args, workingDirectory: request.workingDirectory,
                onLine: { dict in ConfigurableCLILogic.parseGemini(dict, command: command, emit: emit) },
                onExit: onExit)
        case .text:
            runner = AgentProcessRunner(
                executable: exe, arguments: args, workingDirectory: request.workingDirectory,
                onLine: { _ in },
                onRawLine: { line in emit(.textDelta(line + "\n")) },
                onExit: onExit)
        }
        runner.start()
        return runner
    }

    // MARK: - Helpers

    /// Run `<exe> <args>` to completion and return its stdout split into lines.
    /// Used for model discovery (`<cmd> models`).
    private func runForLines(exe: URL, args: [String]) -> [String] {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.environment = AgentProcessRunner.inheritedEnvironment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
