// SPDX-License-Identifier: MIT
// Sourcepad — persistence for user-added CLI specs.
//
// Built-in CLIs (claude/codex/opencode/gemini/agy) ship in code; CLIs the user
// adds via the "Manage Agent CLIs" UI are stored here as JSON so they survive
// relaunches and load into the AgentRegistry alongside the built-ins.

import Foundation

public final class CLISpecStore {

    public static let shared = CLISpecStore()

    private let url: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Sourcepad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("agent-clis.json")
    }

    /// User-added specs (never includes built-ins). Empty on first run / error.
    public func load() -> [CLISpec] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CLISpec].self, from: data)) ?? []
    }

    public func save(_ specs: [CLISpec]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(specs.filter { !$0.builtIn }) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Add or replace (by id) a user spec.
    public func upsert(_ spec: CLISpec) {
        var specs = load().filter { $0.id != spec.id }
        var s = spec
        s.builtIn = false
        specs.append(s)
        save(specs)
    }

    public func remove(id: String) {
        save(load().filter { $0.id != id })
    }
}
