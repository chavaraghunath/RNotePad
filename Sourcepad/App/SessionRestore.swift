// SPDX-License-Identifier: MIT
// Sourcepad — persists the list of open document URLs (and their caret positions)
// across app restarts. Stored in UserDefaults; URLs that no longer exist on disk
// are silently skipped.

import AppKit

public final class SessionRestore {

    public static let shared = SessionRestore()

    private let openURLsKey = "Sourcepad.session.openURLs"
    private let caretsKey   = "Sourcepad.session.carets"

    private init() {}

    /// Saves the URLs and caret positions of every currently-open document.
    /// Call from `applicationWillTerminate`.
    public func saveCurrentSession() {
        var urls: [String] = []
        var carets: [String: Int] = [:]
        for case let doc as TextDocument in NSDocumentController.shared.documents {
            guard let url = doc.fileURL else { continue }
            urls.append(url.path)
            if let wc = doc.windowControllers.first as? EditorWindowController {
                carets[url.path] = wc.editorViewController.currentCaretByte()
            }
        }
        let d = UserDefaults.standard
        d.set(urls, forKey: openURLsKey)
        d.set(carets, forKey: caretsKey)
    }

    /// Returns the saved caret byte position for `url`, or nil if absent.
    public func savedCaret(for url: URL) -> Int? {
        guard let dict = UserDefaults.standard.dictionary(forKey: caretsKey) as? [String: Int]
        else { return nil }
        return dict[url.path]
    }

    /// Opens every saved URL via NSDocumentController. Returns true if at least
    /// one was opened. Files that no longer exist are skipped.
    @discardableResult
    public func tryRestore() -> Bool {
        guard let urls = UserDefaults.standard.array(forKey: openURLsKey) as? [String], !urls.isEmpty
        else { return false }
        let dc = NSDocumentController.shared
        var opened = 0
        for path in urls {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            dc.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSLog("[Sourcepad] session restore: \(url.path) — \(error)") }
            }
            opened += 1
        }
        return opened > 0
    }

    /// Forget the saved session (use when user explicitly closes everything
    /// and prefers a clean slate next launch — not currently wired).
    public func clear() {
        UserDefaults.standard.removeObject(forKey: openURLsKey)
        UserDefaults.standard.removeObject(forKey: caretsKey)
    }
}
