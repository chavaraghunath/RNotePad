// SPDX-License-Identifier: MIT
// Sourcepad — data sources for the agent input's `@`/`/` completion popup.
//
//   • MentionCompletions — fuzzy `@` results over the workspace file index and
//     symbol index (same data as ⌘P / ⌘T), plus the active file as a shortcut.
//     Every result carries a `Mention` (a concrete path) for chip insertion.
//   • SlashCommandRegistry — the `/` command set. Each command is either a
//     LOCAL action (run in the panel, never sent to the agent) or a prompt
//     TEMPLATE (expanded into the input for the user to send).

import AppKit

// MARK: - `@` mentions

public enum MentionCompletions {

    /// Fuzzy `@` results. Empty query surfaces the active file first, then a
    /// listing of indexed files so the popup is immediately useful.
    public static func items(query: String,
                             workspaceRoot: String,
                             activeFilePath: String?) -> [PaletteItem] {
        let index = WorkspaceIndexHost.shared.index
        let files = index?.allFiles() ?? []
        let symbols = index?.allSymbols() ?? []

        func relativize(_ abs: String) -> String {
            let root = workspaceRoot.hasSuffix("/") ? workspaceRoot : workspaceRoot + "/"
            return abs.hasPrefix(root) ? String(abs.dropFirst(root.count)) : abs
        }

        func fileItem(abs: String, language: String?, match: FuzzyMatch?, score: Int) -> PaletteItem {
            let name = (abs as NSString).lastPathComponent
            let mention = Mention(kind: .file, absolutePath: abs, displayName: name)
            return PaletteItem(title: name,
                               subtitle: relativize(abs),
                               symbol: fileSymbol(language),
                               payload: mention,
                               matchedIndices: match?.indices ?? [],
                               score: score)
        }

        if query.isEmpty {
            var out: [PaletteItem] = []
            if let active = activeFilePath {
                out.append(PaletteItem(title: "Active file",
                                       subtitle: (active as NSString).lastPathComponent,
                                       symbol: "doc.badge.gearshape",
                                       payload: Mention(kind: .file, absolutePath: active,
                                                        displayName: (active as NSString).lastPathComponent),
                                       matchedIndices: [],
                                       score: 0))
            }
            let sorted = files.sorted {
                ($0.absolutePath as NSString).lastPathComponent
                    .localizedCaseInsensitiveCompare(($1.absolutePath as NSString).lastPathComponent) == .orderedAscending
            }
            out.append(contentsOf: sorted.prefix(50).map { fileItem(abs: $0.absolutePath, language: $0.language, match: nil, score: 0) })
            return out
        }

        var ranked: [PaletteItem] = []
        for f in files {
            let name = (f.absolutePath as NSString).lastPathComponent
            guard let m = PaletteFuzzy.match(query: query, candidate: name) else { continue }
            ranked.append(fileItem(abs: f.absolutePath, language: f.language, match: m, score: m.score))
        }
        for s in symbols {
            guard let m = PaletteFuzzy.match(query: query, candidate: s.name) else { continue }
            let mention = Mention(kind: .symbol, absolutePath: s.absolutePath, displayName: s.name)
            let where_ = "\((s.absolutePath as NSString).lastPathComponent):\(s.line)"
            ranked.append(PaletteItem(title: s.name,
                                      subtitle: (s.kind.map { "\($0)  " } ?? "") + where_,
                                      symbol: "number",
                                      // Slight penalty so a file basename hit ranks above a symbol hit.
                                      payload: mention,
                                      matchedIndices: m.indices,
                                      score: m.score - 1))
        }
        ranked.sort { $0.score > $1.score }
        return ranked
    }

    private static func fileSymbol(_ language: String?) -> String {
        switch language {
        case "python":           return "chevron.left.forwardslash.chevron.right"
        case "markdown":         return "text.alignleft"
        case "hypertext", "xml": return "doc.text.below.ecg"
        case "json":             return "curlybraces"
        case "yaml":             return "list.bullet.rectangle"
        case "css", "scss":      return "paintbrush"
        default:                 return "doc"
        }
    }
}

// MARK: - `/` commands

/// A slash command. `template == nil` ⇒ a LOCAL panel action keyed by `id`;
/// otherwise the template text is expanded into the input for the user to send.
public struct SlashCommand {
    public let id: String
    public let title: String        // shown as "/<id>"
    public let aliases: [String]
    public let subtitle: String
    public let symbol: String
    public let template: String?

    public var isTemplate: Bool { template != nil }
}

public enum SlashCommandRegistry {

    /// The command set. Local actions map to existing panel methods by `id`
    /// (see AgentPanelViewController.runSlashCommand). Templates seed a prompt.
    public static let all: [SlashCommand] = [
        // Local panel actions.
        .init(id: "new",     title: "/new",     aliases: ["clear", "reset"], subtitle: "Start a fresh conversation",        symbol: "square.and.pencil",        template: nil),
        .init(id: "verify",  title: "/verify",  aliases: ["build"],          subtitle: "Run the project's build / test",    symbol: "checkmark.seal",           template: nil),
        .init(id: "compare", title: "/compare", aliases: ["bestof"],         subtitle: "Run this prompt across agents (best-of-N)", symbol: "square.split.2x1",  template: nil),
        .init(id: "plan",    title: "/plan",    aliases: ["readonly", "safe"], subtitle: "Switch to Plan (read-only) mode",  symbol: "eye",                      template: nil),
        .init(id: "auto",    title: "/auto",    aliases: ["edit"],           subtitle: "Switch to Auto (edit/run) mode",    symbol: "bolt",                     template: nil),
        .init(id: "model",   title: "/model",   aliases: [],                 subtitle: "Choose the model",                  symbol: "cpu",                      template: nil),
        .init(id: "cli",     title: "/cli",     aliases: ["agent"],          subtitle: "Choose the agent CLI",              symbol: "terminal",                 template: nil),
        .init(id: "budget",  title: "/budget",  aliases: ["cost"],           subtitle: "Set a spend budget",                symbol: "dollarsign.circle",        template: nil),
        .init(id: "history", title: "/history", aliases: [],                 subtitle: "Open past conversations",           symbol: "clock.arrow.circlepath",   template: nil),
        .init(id: "copy",    title: "/copy",    aliases: [],                 subtitle: "Copy the last reply to the clipboard", symbol: "doc.on.doc",            template: nil),
        // Prompt templates.
        .init(id: "review",  title: "/review",  aliases: [],                 subtitle: "Review the current changes",        symbol: "checklist",
              template: "Review the current changes for correctness bugs and obvious cleanups. Be concise and specific."),
        .init(id: "explain", title: "/explain", aliases: ["describe"],       subtitle: "Explain the selection / active file", symbol: "text.bubble",
              template: "Explain what this code does, at a high level then key details. "),
        .init(id: "fix",     title: "/fix",     aliases: ["debug"],          subtitle: "Find and fix the problem",          symbol: "wrench.and.screwdriver",
              template: "Find and fix the problem in this code. Explain the root cause briefly, then apply the fix."),
        .init(id: "tests",   title: "/tests",   aliases: ["test"],           subtitle: "Write tests for this code",         symbol: "testtube.2",
              template: "Write thorough unit tests for this code, covering edge cases."),
        .init(id: "doc",     title: "/doc",     aliases: ["document"],       subtitle: "Add documentation comments",        symbol: "text.justify.left",
              template: "Add clear documentation comments to this code in the surrounding style."),
    ]

    /// Fuzzy results for the popup. `query` is the text after the leading `/`.
    public static func items(for query: String) -> [PaletteItem] {
        func item(_ cmd: SlashCommand, indices: [Int], score: Int) -> PaletteItem {
            PaletteItem(title: cmd.title,
                        subtitle: cmd.subtitle,
                        symbol: cmd.symbol,
                        payload: cmd,
                        matchedIndices: [],   // highlight over "/id" is noisy; skip
                        score: score)
        }
        if query.isEmpty {
            return all.map { item($0, indices: [], score: 0) }
        }
        var ranked: [(PaletteItem, Int)] = []
        for cmd in all {
            // Match against id + aliases; keep the best score.
            let candidates = [cmd.id] + cmd.aliases
            let best = candidates.compactMap { PaletteFuzzy.match(query: query, candidate: $0)?.score }.max()
            guard let score = best else { continue }
            ranked.append((item(cmd, indices: [], score: score), score))
        }
        ranked.sort { $0.1 > $1.1 }
        return ranked.map { $0.0 }
    }

    public static func command(id: String) -> SlashCommand? {
        all.first { $0.id == id }
    }
}
