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

    /// Attempts to reopen every saved URL via NSDocumentController. Returns true
    /// if there was a restorable session to attempt (so the caller can skip its
    /// own fallback). Opens are async; if EVERY open ultimately fails, `fallback`
    /// is invoked on the main thread so the app still ends up with a window.
    /// Returns false when there's nothing to restore (no saved/extant files).
    @discardableResult
    public func tryRestore(fallbackIfNoneOpened fallback: @escaping () -> Void) -> Bool {
        guard let paths = UserDefaults.standard.array(forKey: openURLsKey) as? [String], !paths.isEmpty
        else { return false }
        let existing = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return false }

        let dc = NSDocumentController.shared
        // Completions are delivered on the main thread, so these counters are
        // only ever touched there — no synchronization needed.
        var remaining = existing.count
        var anyOpened = false
        for url in existing {
            dc.openDocument(withContentsOf: url, display: true) { doc, _, error in
                if doc != nil, error == nil { anyOpened = true }
                else if let error { NSLog("[Sourcepad] session restore: \(url.path) — \(error)") }
                remaining -= 1
                if remaining == 0 && !anyOpened { fallback() }
            }
        }
        return true
    }

    /// Forget the saved session (use when user explicitly closes everything
    /// and prefers a clean slate next launch — not currently wired).
    public func clear() {
        UserDefaults.standard.removeObject(forKey: openURLsKey)
        UserDefaults.standard.removeObject(forKey: caretsKey)
    }
}
