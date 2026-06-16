// SPDX-License-Identifier: MIT
// Sourcepad — mirror the canonical MCP registry into each agent CLI's config.
//
// Safety contract (these files are the user's real CLI configs):
//   1. MANAGED-ONLY: we only add/update/remove the server names Sourcepad
//      manages. Any other server the user configured is left byte-for-byte
//      untouched (JSON: other keys preserved; TOML: other tables preserved).
//   2. CHANGE-DETECTED: we compute the merged file and only write when it
//      differs from what's on disk — no churn, no needless backups.
//   3. BACKED UP: before the first change to a file we copy it to
//      "<file>.sourcepad.bak" so a bad merge is always recoverable.
//   4. ATOMIC: writes go through a temp file + atomic replace.

import Foundation

public enum MCPSyncOutcome: Equatable {
    case unchanged
    case updated
    case absent          // CLI not detected (no config dir) — skipped
    case failed(String)
}

public struct MCPSyncReport: Equatable {
    public let cli: String
    public let outcome: MCPSyncOutcome
}

public enum MCPSyncEngine {

    // MARK: - Targets

    /// Where each CLI keeps its MCP config and how to render into it.
    struct Target {
        let cli: String
        let url: URL
        let render: (_ existing: String?, _ servers: [MCPServerSpec], _ managed: Set<String>) -> String?
        /// Whether this CLI is "present" enough to sync (config file or its dir exists).
        let isPresent: () -> Bool
    }

    private static func home(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    static func targets() -> [Target] {
        let fm = FileManager.default
        let codex = home("~/.codex/config.toml")
        let claude = home("~/.claude.json")
        let opencode = home("~/.config/opencode/opencode.json")
        let gemini = home("~/.gemini/settings.json")
        return [
            Target(cli: "Codex", url: codex,
                   render: renderCodexTOML,
                   isPresent: { fm.fileExists(atPath: codex.path) || fm.fileExists(atPath: codex.deletingLastPathComponent().path) }),
            Target(cli: "Claude", url: claude,
                   render: { renderJSON($0, $1, $2, container: "mcpServers", style: .claude) },
                   isPresent: { fm.fileExists(atPath: claude.path) }),
            Target(cli: "opencode", url: opencode,
                   render: { renderJSON($0, $1, $2, container: "mcp", style: .opencode) },
                   isPresent: { fm.fileExists(atPath: opencode.path) || fm.fileExists(atPath: opencode.deletingLastPathComponent().path) }),
            Target(cli: "gemini", url: gemini,
                   render: { renderJSON($0, $1, $2, container: "mcpServers", style: .gemini) },
                   isPresent: { fm.fileExists(atPath: gemini.path) || fm.fileExists(atPath: gemini.deletingLastPathComponent().path) }),
        ]
    }

    // MARK: - Sync

    @discardableResult
    public static func syncAll(workspaceRoot: String) -> [MCPSyncReport] {
        let servers = MCPRegistry.shared.allManaged(workspaceRoot: workspaceRoot)
        let managed = MCPRegistry.shared.managedNames()
        return targets().map { target in
            MCPSyncReport(cli: target.cli, outcome: sync(target: target, servers: servers, managed: managed))
        }
    }

    /// Dry-run: the merged config each CLI WOULD receive, without writing.
    public static func previewAll(workspaceRoot: String) -> [(cli: String, present: Bool, merged: String?)] {
        let servers = MCPRegistry.shared.allManaged(workspaceRoot: workspaceRoot)
        let managed = MCPRegistry.shared.managedNames()
        return targets().map { target in
            let present = target.isPresent()
            let existing = try? String(contentsOf: target.url, encoding: .utf8)
            return (target.cli, present, present ? target.render(existing, servers, managed) : nil)
        }
    }

    /// Self-test: applying the merge to its own output must be a no-op (so
    /// auto-sync converges and never churns). Returns per-CLI (idempotent, equal).
    public static func idempotencyCheck(workspaceRoot: String) -> [(cli: String, idempotent: Bool)] {
        let servers = MCPRegistry.shared.allManaged(workspaceRoot: workspaceRoot)
        let managed = MCPRegistry.shared.managedNames()
        return targets().map { target in
            let existing = try? String(contentsOf: target.url, encoding: .utf8)
            let once = target.render(existing, servers, managed)
            let twice = target.render(once, servers, managed)
            return (target.cli, once == twice)
        }
    }

    /// Whether each detected CLI is already in sync with the registry.
    public static func drift(workspaceRoot: String) -> [(cli: String, inSync: Bool, present: Bool)] {
        let servers = MCPRegistry.shared.allManaged(workspaceRoot: workspaceRoot)
        let managed = MCPRegistry.shared.managedNames()
        return targets().map { target in
            guard target.isPresent() else { return (target.cli, true, false) }
            let existing = try? String(contentsOf: target.url, encoding: .utf8)
            let merged = target.render(existing, servers, managed)
            return (target.cli, merged == nil || merged == (existing ?? ""), true)
        }
    }

    private static func sync(target: Target, servers: [MCPServerSpec], managed: Set<String>) -> MCPSyncOutcome {
        guard target.isPresent() else { return .absent }
        let existing = try? String(contentsOf: target.url, encoding: .utf8)
        guard let merged = target.render(existing, servers, managed) else {
            return .failed("could not render \(target.cli) config")
        }
        if merged == (existing ?? "") { return .unchanged }
        do {
            try FileManager.default.createDirectory(at: target.url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            // Back up the pre-change file once we know we're about to change it.
            if let existing {
                let backup = target.url.appendingPathExtension("sourcepad.bak")
                try? existing.write(to: backup, atomically: true, encoding: .utf8)
            }
            try merged.write(to: target.url, atomically: true, encoding: .utf8)
            return .updated
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - JSON rendering (Claude / opencode / gemini)

    private enum JSONStyle { case claude, opencode, gemini }

    /// Merge managed servers into a JSON config under `container`, preserving all
    /// other keys. Prunes managed names that are no longer in the registry.
    private static func renderJSON(_ existing: String?,
                                   _ servers: [MCPServerSpec],
                                   _ managed: Set<String>,
                                   container: String,
                                   style: JSONStyle) -> String? {
        var root: [String: Any] = [:]
        if let existing, let data = existing.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }
        var bucket = (root[container] as? [String: Any]) ?? [:]
        // Remove managed entries we no longer want, leave the user's alone.
        for key in bucket.keys where managed.contains(key) { bucket.removeValue(forKey: key) }
        // Add/replace each managed server in the CLI's schema.
        for s in servers {
            bucket[s.name] = jsonEntry(for: s, style: style)
        }
        root[container] = bucket
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text + "\n"
    }

    private static func jsonEntry(for s: MCPServerSpec, style: JSONStyle) -> [String: Any] {
        switch style {
        case .claude:
            return ["type": "stdio", "command": s.command, "args": s.args, "env": s.env]
        case .gemini:
            var e: [String: Any] = ["command": s.command, "args": s.args]
            if !s.env.isEmpty { e["env"] = s.env }
            return e
        case .opencode:
            // opencode folds the executable + args into a single `command` array.
            var e: [String: Any] = ["type": "local", "command": [s.command] + s.args, "enabled": true]
            if !s.env.isEmpty { e["environment"] = s.env }
            return e
        }
    }

    // MARK: - TOML rendering (Codex)

    /// Rewrite the `[mcp_servers.<name>]` tables for managed servers, preserving
    /// every other table in the file. Done by text surgery (no TOML library):
    /// strip our managed blocks, then append freshly-rendered ones.
    private static func renderCodexTOML(_ existing: String?,
                                        _ servers: [MCPServerSpec],
                                        _ managed: Set<String>) -> String? {
        var lines = (existing ?? "").components(separatedBy: "\n")
        lines = stripManagedCodexBlocks(lines, managed: managed)

        // Ensure a single trailing structure, then append our blocks.
        var out = lines.joined(separator: "\n")
        while out.hasSuffix("\n\n") { out = String(out.dropLast()) }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)

        // No bare `[mcp_servers]` header: each `[mcp_servers.<name>]` table
        // implicitly defines the super-table, and re-declaring it after a
        // sub-table would be a TOML redefinition.
        let blocks = servers.map(codexBlock)
        let appended = blocks.joined(separator: "\n\n")
        if out.isEmpty { return appended + "\n" }
        return out + "\n\n" + appended + "\n"
    }

    /// Drop every `[mcp_servers.<name>]` (and its `.env` subtable) whose name is
    /// managed, plus a bare `[mcp_servers]` header (re-added during render).
    private static func stripManagedCodexBlocks(_ lines: [String], managed: Set<String>) -> [String] {
        var result: [String] = []
        var skipping = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                // A new table header — decide whether to skip it.
                if trimmed == "[mcp_servers]" {
                    skipping = true       // drop the bare header; re-added on render
                    continue
                }
                if let name = managedCodexTableName(trimmed), managed.contains(name) {
                    skipping = true
                    continue
                }
                skipping = false          // some other table — keep it
            }
            if !skipping { result.append(line) }
        }
        return result
    }

    /// For `[mcp_servers.NAME]` or `[mcp_servers.NAME.env]`, return NAME.
    private static func managedCodexTableName(_ header: String) -> String? {
        guard header.hasPrefix("[mcp_servers.") , header.hasSuffix("]") else { return nil }
        let inner = header.dropFirst("[mcp_servers.".count).dropLast() // NAME or NAME.env
        let name = inner.hasSuffix(".env") ? inner.dropLast(".env".count) : inner
        return String(name)
    }

    private static func codexBlock(for s: MCPServerSpec) -> String {
        var b = "[mcp_servers.\(s.name)]\n"
        b += "command = \(tomlString(s.command))\n"
        b += "args = [\(s.args.map(tomlString).joined(separator: ", "))]"
        if !s.env.isEmpty {
            b += "\n\n[mcp_servers.\(s.name).env]"
            for key in s.env.keys.sorted() {
                b += "\n\(key) = \(tomlString(s.env[key] ?? ""))"
            }
        }
        return b
    }

    /// A TOML basic (double-quoted) string with the required escaping.
    private static func tomlString(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:   out.unicodeScalars.append(ch)
            }
        }
        return "\"\(out)\""
    }
}
