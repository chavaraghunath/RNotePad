// SPDX-License-Identifier: MIT
// Sourcepad — the canonical MCP server registry.
//
// Each agent CLI (Claude, Codex, opencode, gemini, …) owns its own MCP config
// file in its own format. Sourcepad keeps a single canonical list of the MCP
// servers it manages and mirrors them, uniformly, into every detected CLI — so
// the same servers are available everywhere without hand-editing four files.
//
// Two kinds of managed server:
//   • built-in: the bundled SourceGraph knowledge-graph server (the Sourcepad
//     binary itself, launched with --sourcegraph-mcp <workspace>).
//   • custom: user-defined servers added in Settings ▸ MCP.
//
// Sourcepad only ever touches the entries it manages (tracked by name); a user's
// own MCP servers in those files are preserved untouched.

import Foundation

/// One MCP server, in Sourcepad's neutral form. Per-CLI adapters translate this
/// into each CLI's on-disk schema.
public struct MCPServerSpec: Codable, Equatable {
    public var name: String                 // stable, slug-like ([A-Za-z0-9_-]+)
    public var command: String              // executable
    public var args: [String]
    public var env: [String: String]
    public var builtIn: Bool                // shipped by Sourcepad (not user-removable)

    public init(name: String, command: String, args: [String] = [],
                env: [String: String] = [:], builtIn: Bool = false) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.builtIn = builtIn
    }

    /// A name is safe to use as an unquoted TOML table key / JSON key.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }
}

public final class MCPRegistry {

    public static let shared = MCPRegistry()

    /// Posted after the managed server set changes (add/edit/remove).
    public static let didChange = Notification.Name("SourcepadMCPRegistryDidChange")

    private let storeURL: URL
    private var custom: [MCPServerSpec]

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.storeURL = support
            .appendingPathComponent("Sourcepad", isDirectory: true)
            .appendingPathComponent("mcp-registry.json", isDirectory: false)
        self.custom = MCPRegistry.load(from: storeURL)
    }

    // MARK: - Built-in SourceGraph

    /// The built-in SourceGraph MCP server, pointed at `workspaceRoot`. The
    /// command is the running Sourcepad binary; it serves MCP when launched with
    /// --sourcegraph-mcp (see main.swift).
    public static func sourceGraphServer(workspaceRoot: String) -> MCPServerSpec {
        let binary = Bundle.main.executablePath
            ?? "/Applications/Sourcepad.app/Contents/MacOS/Sourcepad"
        return MCPServerSpec(name: "sourcegraph",
                             command: binary,
                             args: ["--sourcegraph-mcp", workspaceRoot],
                             env: [:],
                             builtIn: true)
    }

    // MARK: - Query

    /// Every server Sourcepad manages, for the given workspace: the built-in
    /// SourceGraph server plus the user's custom servers.
    public func allManaged(workspaceRoot: String) -> [MCPServerSpec] {
        [MCPRegistry.sourceGraphServer(workspaceRoot: workspaceRoot)] + custom
    }

    /// Names of every server Sourcepad manages (used to prune removed ones from
    /// CLI configs without touching the user's own entries).
    public func managedNames() -> Set<String> {
        Set(["sourcegraph"] + custom.map { $0.name })
    }

    public var customServers: [MCPServerSpec] { custom }

    // MARK: - Mutate

    @discardableResult
    public func upsertCustom(_ spec: MCPServerSpec) -> Bool {
        guard MCPServerSpec.isValidName(spec.name), spec.name != "sourcegraph",
              !spec.command.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        var s = spec; s.builtIn = false
        if let i = custom.firstIndex(where: { $0.name == s.name }) {
            custom[i] = s
        } else {
            custom.append(s)
        }
        persist()
        return true
    }

    public func removeCustom(name: String) {
        custom.removeAll { $0.name == name }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder.sortedPretty.encode(custom)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("[Sourcepad] MCP registry save failed: \(error)")
        }
        NotificationCenter.default.post(name: MCPRegistry.didChange, object: nil)
    }

    private static func load(from url: URL) -> [MCPServerSpec] {
        guard let data = try? Data(contentsOf: url),
              let specs = try? JSONDecoder().decode([MCPServerSpec].self, from: data) else { return [] }
        return specs
    }
}

extension JSONEncoder {
    /// Stable, human-diffable output for config + registry files.
    static var sortedPretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
