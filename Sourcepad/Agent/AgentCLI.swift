// SPDX-License-Identifier: MIT
// Sourcepad — agent CLI adapter protocol + discovery registry.
//
// An `AgentCLI` wraps one external agentic CLI (claude, codex, opencode, …).
// It knows how to (a) locate its executable, (b) list available models, and
// (c) run one conversation turn as a subprocess, parsing that CLI's JSON event
// dialect into the shared `AgentEvent` vocabulary.
//
// Transport is one-shot exec per turn (see AGENT-CLI-KNOWLEDGE-BASE.md): each
// turn spawns a fresh process, streams events, and resumes the prior turn by
// the CLI's native session id. This makes switching CLI/model between turns a
// non-event.
//
// Foundation-only — headlessly testable.

import Foundation

/// A running turn that can be cancelled.
public protocol AgentTurnHandle: AnyObject {
    func cancel()
}

public protocol AgentCLI: AnyObject {
    /// Stable id used in storage + UI ("claude", "codex", "opencode").
    var id: String { get }
    /// Human label ("Claude Code", "Codex", "opencode").
    var displayName: String { get }
    /// Located executable, or nil if not installed / not usable.
    var executableURL: URL? { get }
    /// True when the CLI is installed and looks usable.
    var isAvailable: Bool { get }

    /// Best-effort list of models. May spawn the CLI (e.g. `opencode models`)
    /// or return a curated set. Called off the main thread.
    func discoverModels() -> [AgentModel]

    /// Run one turn. `onEvent` fires on the main queue for each parsed event;
    /// the final event is always `.turnFinished` or `.error`.
    @discardableResult
    func startTurn(_ request: AgentTurnRequest,
                   onEvent: @escaping (AgentEvent) -> Void) -> AgentTurnHandle
}

// MARK: - Executable lookup

public enum AgentExecutable {
    /// Resolve a command name against a realistic PATH. GUI apps launched from
    /// Finder inherit a minimal PATH, so we also probe the common locations
    /// Homebrew / asdf / volta / system put these CLIs in.
    public static func locate(_ name: String) -> URL? {
        let fm = FileManager.default

        // 1. Anything already on PATH.
        if let pathVar = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathVar.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: candidate.path) { return candidate }
            }
        }

        // 2. Common install roots not always on a Finder-launched PATH.
        let home = NSHomeDirectory()
        let roots = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
            "\(home)/.local/bin", "\(home)/bin",
            "\(home)/.volta/bin", "\(home)/.asdf/shims",
            "\(home)/.bun/bin", "\(home)/.cargo/bin",
        ]
        for dir in roots {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

// MARK: - Registry

/// Discovers which agent CLIs are installed and caches their model lists.
/// Probing is done off the main thread and never blocks app launch.
public final class AgentRegistry {

    public static let shared = AgentRegistry()

    /// Built-in adapters Sourcepad ships with, in display order.
    private let builtInCLIs: [AgentCLI] = [
        ClaudeAgentCLI(),
        CodexAgentCLI(),
        OpencodeAgentCLI(),
        // Spec-driven adapters — no bespoke Swift per CLI. Built-in specs for
        // gemini + agy; user-added CLIs are appended from CLISpecStore.
        ConfigurableAgentCLI(spec: .gemini),
        ConfigurableAgentCLI(spec: .agy),
        // Local MLX models — appears only once MLX is installed + a model pulled.
        MLXAgentCLI(),
        // CursorAgentCLI() — deferred until it runs cleanly (dumps JS on --help).
    ]

    /// All adapters (built-in + user-added), in display order.
    public private(set) var allCLIs: [AgentCLI]

    private let queue = DispatchQueue(label: "sourcepad.agent.registry", qos: .utility)
    private var modelCache: [String: [AgentModel]] = [:]
    private var availabilityCache: [String: Bool] = [:]

    private init() {
        self.allCLIs = builtInCLIs
        reloadCustomCLIs()
    }

    /// Rebuild `allCLIs` = built-ins + user specs from CLISpecStore (ids that
    /// collide with a built-in are ignored). Clears probe caches so the new set
    /// is re-discovered on the next `warmUp`. Call after the user adds/removes a CLI.
    public func reloadCustomCLIs() {
        let builtInIDs = Set(builtInCLIs.map { $0.id })
        let custom = CLISpecStore.shared.load()
            .filter { !builtInIDs.contains($0.id) }
            .map { ConfigurableAgentCLI(spec: $0) as AgentCLI }
        allCLIs = builtInCLIs + custom
        availabilityCache.removeAll()
        modelCache.removeAll()
    }

    public func cli(withID id: String) -> AgentCLI? {
        allCLIs.first { $0.id == id }
    }

    /// CLIs that are actually installed. Cached after first probe.
    public func availableCLIs() -> [AgentCLI] {
        allCLIs.filter { isAvailable($0) }
    }

    public func isAvailable(_ cli: AgentCLI) -> Bool {
        if let cached = availabilityCache[cli.id] { return cached }
        let v = cli.isAvailable
        availabilityCache[cli.id] = v
        return v
    }

    /// Kick off background discovery of installed CLIs + their models. Safe to
    /// call at launch; results land in the cache and `onUpdate` (main queue)
    /// fires once probing completes.
    public func warmUp(onUpdate: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            for cli in self.allCLIs {
                let available = cli.isAvailable
                self.availabilityCache[cli.id] = available
                if available {
                    self.modelCache[cli.id] = cli.discoverModels()
                }
            }
            if let onUpdate {
                DispatchQueue.main.async { onUpdate() }
            }
        }
    }

    /// Cached models for a CLI (empty until warmUp completes).
    public func models(for cliID: String) -> [AgentModel] {
        modelCache[cliID] ?? []
    }
}
