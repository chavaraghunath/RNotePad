// SPDX-License-Identifier: MIT
// Sourcepad — Phase 19 daily notes.
//
// ⌘⇧D opens (or creates) today's YYYY-MM-DD.md in the configured Daily
// folder. The folder defaults to <first workspace root>/Daily/.

import AppKit

public enum DailyNotes {

    public static func openToday() {
        guard let folder = dailyFolder() else {
            NSSound.beep(); return
        }
        try? FileManager.default.createDirectory(at: folder,
                                                 withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let filename = "\(formatter.string(from: Date())).md"
        let url = folder.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            let template = "# \(formatter.string(from: Date()))\n\n## Notes\n\n"
            try? template.write(to: url, atomically: true, encoding: .utf8)
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    private static func dailyFolder() -> URL? {
        if let raw = UserDefaults.standard.string(forKey: "Sourcepad.dailyNotesFolder") {
            return URL(fileURLWithPath: raw)
        }
        guard let root = WorkspaceManager.shared.activeWorkspace.roots.first else {
            return nil
        }
        return root.appendingPathComponent("Daily", isDirectory: true)
    }
}
