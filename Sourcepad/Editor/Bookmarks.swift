// SPDX-License-Identifier: MIT
// Sourcepad — bookmark marker management + per-URL persistence.

import AppKit

public enum BookmarkConstants {
    /// Scintilla marker slot. 1 is unused by default styles; 0-23 are fold-related.
    public static let markerNumber: Int32 = 24
}

public final class Bookmarks {

    public static let shared = Bookmarks()

    private let key = "Sourcepad.bookmarks"
    private var byURL: [String: Set<Int>] = [:]

    private init() {
        if let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [Int]] {
            byURL = raw.mapValues { Set($0) }
        }
    }

    public func setupMarker(in sciView: NSView, scheme: ColorScheme) {
        let fg = NSColor.white
        let bg = NSColor.systemBlue
        SciDefineBookmarkMarker(sciView, BookmarkConstants.markerNumber, fg, bg)
        _ = scheme  // reserved for future theme-aware coloring
    }

    public func restore(for url: URL?, in sciView: NSView) {
        guard let url, let lines = byURL[url.path] else { return }
        for line in lines { SciMarkerAdd(sciView, line, BookmarkConstants.markerNumber) }
    }

    public func toggle(line: Int, in sciView: NSView, url: URL?) {
        if SciMarkerExistsOnLine(sciView, line, BookmarkConstants.markerNumber) {
            SciMarkerRemove(sciView, line, BookmarkConstants.markerNumber)
            if let url { byURL[url.path]?.remove(line) }
        } else {
            SciMarkerAdd(sciView, line, BookmarkConstants.markerNumber)
            if let url {
                byURL[url.path, default: []].insert(line)
            }
        }
        persist()
    }

    public func clearAll(in sciView: NSView, url: URL?) {
        SciMarkerDeleteAll(sciView, BookmarkConstants.markerNumber)
        if let url { byURL[url.path] = [] }
        persist()
    }

    private func persist() {
        let raw = byURL.mapValues { Array($0).sorted() }
        UserDefaults.standard.set(raw, forKey: key)
    }
}
