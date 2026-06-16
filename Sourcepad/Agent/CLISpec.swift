// SPDX-License-Identifier: MIT
// Sourcepad — a declarative spec describing how to drive an agent CLI.
//
// The first-class adapters (claude/codex/opencode) hand-roll their invocation +
// JSON event parsing for maximum fidelity. A CLISpec lets Sourcepad drive *other*
// CLIs — and user-added ones — without new Swift code: it captures the executable,
// the model list, the invocation flags, and how to read the CLI's output. Built-in
// specs ship for gemini + agy; future ones come from the "Manage Agent CLIs" UI.
//
// Codable so user-added specs persist to disk. Foundation-only.

import Foundation

public struct CLISpec: Codable, Equatable {

    /// How the CLI streams its answer back on stdout.
    public enum OutputMode: String, Codable {
        /// Plain text — every stdout line is part of the answer (e.g. agy).
        case text
        /// Gemini CLI `-o stream-json` newline-delimited JSON events.
        case geminiStreamJSON
    }

    public struct Model: Codable, Equatable {
        public var id: String       // value passed to the model flag
        public var label: String    // shown in the picker
        public init(id: String, label: String) { self.id = id; self.label = label }
    }

    public var id: String                  // stable id ("gemini", "agy", user slug)
    public var displayName: String         // picker label ("Gemini", "Antigravity")
    public var command: String             // executable name to locate on PATH
    public var models: [Model]             // curated models (when not discovered live)
    public var modelsSubcommand: String?   // e.g. "models" → run `<cmd> models` to list

    // Invocation
    public var promptFlag: String          // value-bearing flag for the prompt ("-p", "--print")
    public var modelFlag: String?          // "-m" / "--model"
    public var baseArgs: [String]          // always present (e.g. ["-o","stream-json","--skip-trust"])
    public var planArgs: [String]          // appended in Plan/read-only mode
    public var autoArgs: [String]          // appended in Auto mode (yolo / skip-permissions)
    public var output: OutputMode
    public var builtIn: Bool               // shipped with the app (not user-removable)

    public init(id: String, displayName: String, command: String,
                models: [Model] = [], modelsSubcommand: String? = nil,
                promptFlag: String, modelFlag: String? = nil,
                baseArgs: [String] = [], planArgs: [String] = [], autoArgs: [String] = [],
                output: OutputMode, builtIn: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.command = command
        self.models = models
        self.modelsSubcommand = modelsSubcommand
        self.promptFlag = promptFlag
        self.modelFlag = modelFlag
        self.baseArgs = baseArgs
        self.planArgs = planArgs
        self.autoArgs = autoArgs
        self.output = output
        self.builtIn = builtIn
    }
}

// MARK: - Built-in specs (verified against the installed CLIs)

public extension CLISpec {

    /// Gemini CLI — `-o stream-json` (init/message/result events), `--skip-trust`
    /// for headless, `--approval-mode plan|yolo` for read-only vs full access.
    /// Models are curated (the CLI has no machine-readable model list).
    static let gemini = CLISpec(
        id: "gemini", displayName: "Gemini", command: "gemini",
        models: [
            .init(id: "gemini-3-pro-preview",    label: "Gemini 3 Pro"),
            .init(id: "gemini-3-flash-preview",  label: "Gemini 3 Flash"),
            .init(id: "gemini-2.5-pro",          label: "Gemini 2.5 Pro"),
            .init(id: "gemini-2.5-flash",        label: "Gemini 2.5 Flash"),
            .init(id: "gemini-2.5-flash-lite",   label: "Gemini 2.5 Flash Lite"),
        ],
        promptFlag: "-p", modelFlag: "-m",
        baseArgs: ["-o", "stream-json", "--skip-trust"],
        planArgs: ["--approval-mode", "plan"],
        autoArgs: ["--approval-mode", "yolo"],
        output: .geminiStreamJSON, builtIn: true)

    /// Antigravity CLI (agy) — plain-text `--print` output, models listed live by
    /// `agy models`, `--dangerously-skip-permissions` for Auto.
    static let agy = CLISpec(
        id: "agy", displayName: "Antigravity", command: "agy",
        models: [], modelsSubcommand: "models",
        promptFlag: "--print", modelFlag: "--model",
        baseArgs: [], planArgs: [],
        autoArgs: ["--dangerously-skip-permissions"],
        output: .text, builtIn: true)

    static let builtIns: [CLISpec] = [.gemini, .agy]
}
