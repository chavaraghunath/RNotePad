// SPDX-License-Identifier: MIT
// Sourcepad — most-recently-closed document stack for Cmd-Shift-T.

import Foundation
import AppKit

public final class ClosedTabHistory {

    public static let shared = ClosedTabHistory()

    private let maxEntries = 20
    private var urls: [URL] = []

    private init() {}

    public func push(_ url: URL) {
        // Move-to-front semantics: if already in list, lift it; cap at maxEntries.
        urls.removeAll(where: { $0 == url })
        urls.insert(url, at: 0)
        if urls.count > maxEntries {
            urls = Array(urls.prefix(maxEntries))
        }
    }

    public func popLatest() -> URL? {
        guard !urls.isEmpty else { return nil }
        return urls.removeFirst()
    }

    public var hasEntries: Bool { !urls.isEmpty }
}
