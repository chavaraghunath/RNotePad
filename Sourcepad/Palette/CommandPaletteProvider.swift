// SPDX-License-Identifier: MIT
// Sourcepad — ⌘⇧P "Command Palette" provider.
//
// Walks NSApp.mainMenu and collects every enabled, leaf menu item the user
// could click. Activation re-dispatches the same selector via the standard
// responder chain so the action runs identically to a real menu click.
//
// This means every menu item you add anywhere in the app is automatically
// available in the palette — no separate registry.

import AppKit

public final class CommandPaletteProvider: PaletteProvider {

    public var displayName: String { "Run Command" }
    public var placeholder: String { "Type to search commands…" }

    public init() {}

    public func items(for query: String) -> [PaletteItem] {
        let all = collectCommands()
        if query.isEmpty {
            return Array(all.prefix(200)).map { entry in
                let shortcut = entry.item.keyEquivalentDisplay
                let pathString = entry.path.joined(separator: " ▸ ")
                return PaletteItem(
                    title: entry.item.title,
                    subtitle: pathString + (shortcut.isEmpty ? "" : "    \(shortcut)"),
                    symbol: "command",
                    payload: entry,
                    matchedIndices: [],
                    score: 0)
            }
        }

        var ranked: [PaletteItem] = []
        for entry in all {
            // Match against "<path joined> <title>" so users can find
            // an item by its menu path too.
            let searchable = (entry.path + [entry.item.title]).joined(separator: " ")
            guard let match = PaletteFuzzy.match(query: query, candidate: searchable) else { continue }
            // Use title for highlight (UI clarity); compute matched indices
            // relative to the title alone.
            let titleMatch = PaletteFuzzy.match(query: query, candidate: entry.item.title)
            let shortcut = entry.item.keyEquivalentDisplay
            ranked.append(PaletteItem(
                title: entry.item.title,
                subtitle: entry.path.joined(separator: " ▸ ") + (shortcut.isEmpty ? "" : "    \(shortcut)"),
                symbol: "command",
                payload: entry,
                matchedIndices: titleMatch?.indices ?? [],
                score: match.score))
        }
        ranked.sort { $0.score > $1.score }
        return ranked
    }

    public func activate(_ item: PaletteItem) {
        guard let entry = item.payload as? MenuEntry else { return }
        // Standard nil-target dispatch via the responder chain. Matches a
        // real menu click exactly.
        let action = entry.item.action
        let target = entry.item.target
        guard let action else { NSSound.beep(); return }
        if target != nil {
            _ = NSApp.sendAction(action, to: target, from: entry.item)
        } else {
            _ = NSApp.sendAction(action, to: nil, from: entry.item)
        }
    }

    // MARK: - Menu enumeration

    public struct MenuEntry {
        let path: [String]
        let item: NSMenuItem
    }

    private func collectCommands() -> [MenuEntry] {
        guard let main = NSApp.mainMenu else { return [] }
        var out: [MenuEntry] = []
        walk(menu: main, path: [], into: &out)
        return out
    }

    private func walk(menu: NSMenu, path: [String], into out: inout [MenuEntry]) {
        for item in menu.items {
            if item.isSeparatorItem { continue }
            if item.isHidden { continue }
            if let sub = item.submenu {
                let nextPath = path.isEmpty ? path : path + [item.title]
                // Skip the top-level menu titles ("Sourcepad", "File", etc.)
                // from the displayed path — they're noise for the user.
                walk(menu: sub, path: nextPath.isEmpty ? [item.title] : nextPath, into: &out)
            } else if item.action != nil {
                // Leaf command.
                out.append(MenuEntry(path: path, item: item))
            }
        }
    }
}

private extension NSMenuItem {
    /// Render the key equivalent + modifiers as something a human reads
    /// (⇧⌘P, F2, ⌥⌘W, etc.).
    var keyEquivalentDisplay: String {
        if keyEquivalent.isEmpty { return "" }
        var out = ""
        let mods = keyEquivalentModifierMask
        if mods.contains(.control) { out += "⌃" }
        if mods.contains(.option)  { out += "⌥" }
        if mods.contains(.shift)   { out += "⇧" }
        if mods.contains(.command) { out += "⌘" }
        // Map common special chars.
        switch keyEquivalent {
        case "\r":         out += "↵"
        case String(Character(UnicodeScalar(0x1B)!)): out += "⎋"
        case " ":          out += "Space"
        default:
            out += keyEquivalent.uppercased()
        }
        return out
    }
}
