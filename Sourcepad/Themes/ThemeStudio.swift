// SPDX-License-Identifier: MIT
// Sourcepad — Phase 34 theme studio + keymap.
//
// Theme studio reads/writes JSON theme files from
//   ~/Library/Application Support/Sourcepad/Themes/<name>.json
// Keymap reads ~/Library/Application Support/Sourcepad/keymap.json and
// overlays on top of the default menu shortcuts.

import AppKit

public enum ThemeStudio {

    public static var themesDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = support.appendingPathComponent("Sourcepad/Themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// List user themes (JSON files).
    public static func listThemes() -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: themesDir,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
                   .map { $0.deletingPathExtension().lastPathComponent }
                   .sorted()
    }

    /// Reveal the themes folder in Finder so the user can drop hand-written
    /// JSON in there.
    public static func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([themesDir])
    }
}

public enum KeymapStudio {

    public static var keymapURL: URL {
        ThemeStudio.themesDir.deletingLastPathComponent()
            .appendingPathComponent("keymap.json")
    }

    /// Load keymap overrides. Schema:
    ///   { "shortcuts": { "Selector:": "⌘⇧K" } }
    public static func loadOverrides() -> [String: String] {
        guard let data = try? Data(contentsOf: keymapURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let shortcuts = obj["shortcuts"] as? [String: String] else { return [:] }
        return shortcuts
    }

    public static func revealFile() {
        if !FileManager.default.fileExists(atPath: keymapURL.path) {
            let stub = """
            {
              "_comment": "Override menu shortcuts by mapping selector name to a key. ⌘⇧⌥⌃ modifiers prefix the key.",
              "shortcuts": {
                "sourcepadCommandPalette:": "⌘⇧P"
              }
            }
            """
            try? stub.write(to: keymapURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([keymapURL])
    }
}
