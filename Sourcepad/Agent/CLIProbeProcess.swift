// SPDX-License-Identifier: MIT
// Sourcepad — the process side of CLIProbe (kept separate so CLIProbe's pure
// `--help` analysis stays dependency-light and headless-testable).

import Foundation

public extension CLIProbe {

    /// Locate `command`, run `<cmd> --help`, analyse it, then fill models from a
    /// `models` subcommand when available. Returns nil if the command isn't found.
    static func probe(command: String) -> Draft? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let exe = AgentExecutable.locate(trimmed) else { return nil }
        // Some CLIs print help via `--help`, others only via a `help` subcommand.
        let help = run(exe, ["--help"]) + "\n" + run(exe, ["help"])
        var draft = analyze(help: help, command: trimmed)
        if let sub = draft.spec.modelsSubcommand {
            let models = run(exe, [sub])
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count < 120 }
                .map { CLISpec.Model(id: $0, label: $0) }
            draft.spec.models = models
        }
        return draft
    }

    private static func run(_ exe: URL, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.environment = AgentProcessRunner.inheritedEnvironment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out   // many CLIs print help to stderr
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
