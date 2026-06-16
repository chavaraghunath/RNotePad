// SPDX-License-Identifier: MIT
// Sourcepad — auto-configure a CLI from its own `--help`.
//
// The user types a command (e.g. "agy"); this runs `<cmd> --help`, scans for the
// flags Sourcepad needs (headless prompt, model, full-access/plan), discovers the
// model list (via a `models` subcommand when present), and returns a DRAFT CLISpec
// the user can review/edit before saving. The help-analysis is pure and
// exhaustively headless-testable; only `probe()` touches the process/disk.

import Foundation

public enum CLIProbe {

    public struct Draft {
        public var spec: CLISpec
        public let headlessSupported: Bool   // a usable prompt flag was found
        public let summary: [String]         // human-readable capability bullets
    }

    // MARK: - Pure analysis

    /// Analyse `<cmd> --help` text into a draft spec (models filled in later by
    /// `probe()`). Detection is conservative and produces an *editable* draft.
    public static func analyze(help: String, command: String) -> Draft {
        let promptFlag = detectPromptFlag(help)
        let modelFlag = detectModelFlag(help)
        let (planArgs, autoArgs) = detectModeArgs(help)
        let modelsSub = detectModelsSubcommand(help)

        let slug = command
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
            .lowercased()
        let spec = CLISpec(
            id: slug.isEmpty ? command : slug,
            displayName: command.prefix(1).uppercased() + command.dropFirst(),
            command: command,
            models: [],
            modelsSubcommand: modelsSub,
            promptFlag: promptFlag ?? "-p",
            modelFlag: modelFlag,
            baseArgs: [],
            planArgs: planArgs,
            autoArgs: autoArgs,
            output: .text,            // generic, universal default
            builtIn: false)

        var summary: [String] = []
        summary.append("Prompt flag: \(promptFlag ?? "— not found (may not support headless use)")")
        summary.append("Model flag: \(modelFlag ?? "— none")")
        summary.append("Full-access (Auto): \(autoArgs.isEmpty ? "— none found" : autoArgs.joined(separator: " "))")
        summary.append("Read-only (Plan): \(planArgs.isEmpty ? "— none found" : planArgs.joined(separator: " "))")
        summary.append("Model discovery: \(modelsSub != nil ? "`\(command) \(modelsSub!)`" : "manual")")

        return Draft(spec: spec, headlessSupported: promptFlag != nil, summary: summary)
    }

    // MARK: - Detection helpers

    /// Match `flag` as a standalone token in the help text (so `-p` doesn't match
    /// inside `--prompt`). Case-sensitive (flags are).
    static func hasFlag(_ help: String, _ flag: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: flag)
        let pattern = "(?:^|[\\s,\\[])" + escaped + "(?:$|[\\s,=\\]])"
        return help.range(of: pattern, options: .regularExpression) != nil
    }

    /// The flag that triggers a single non-interactive prompt, preferring the
    /// clearest long form.
    static func detectPromptFlag(_ help: String) -> String? {
        for f in ["--prompt", "--print", "-p"] where hasFlag(help, f) { return f }
        return nil
    }

    static func detectModelFlag(_ help: String) -> String? {
        if hasFlag(help, "-m") { return "-m" }
        if hasFlag(help, "--model") { return "--model" }
        return nil
    }

    /// (planArgs, autoArgs) for read-only vs full-access.
    static func detectModeArgs(_ help: String) -> ([String], [String]) {
        var plan: [String] = []
        var auto: [String] = []
        if hasFlag(help, "--approval-mode") {
            plan = ["--approval-mode", "plan"]
            auto = ["--approval-mode", "yolo"]
        } else if hasFlag(help, "--permission-mode") {
            plan = ["--permission-mode", "plan"]
        }
        if auto.isEmpty {
            if hasFlag(help, "--dangerously-skip-permissions") {
                auto = ["--dangerously-skip-permissions"]
            } else if hasFlag(help, "--dangerously-bypass-approvals-and-sandbox") {
                auto = ["--dangerously-bypass-approvals-and-sandbox"]
            } else if hasFlag(help, "--yolo") || hasFlag(help, "-y") {
                auto = ["--yolo"]
            }
        }
        return (plan, auto)
    }

    /// A `models` subcommand listed in help (line starting with `models`).
    static func detectModelsSubcommand(_ help: String) -> String? {
        help.range(of: "(?m)^\\s*models\\b", options: .regularExpression) != nil ? "models" : nil
    }
}
