// SPDX-License-Identifier: MIT
// Sourcepad — protocol every palette content type implements.
//
// A provider supplies a fixed item set (or a fresh one on each query) and
// knows how to dispatch the chosen item's action. The palette window calls
// `items(for:)` on every keystroke (debounced lightly), then `activate(_:)`
// when the user presses Enter.

import AppKit

public struct PaletteItem {
    /// Primary label, shown bold in the row. The match-highlight runs
    /// across this string.
    public let title: String

    /// Secondary label, shown grey to the right or below.
    public let subtitle: String?

    /// SF Symbol name for the row leading icon. nil = no icon.
    public let symbol: String?

    /// Opaque payload — providers stash whatever they need to dispatch.
    public let payload: Any

    /// Indices into `title` (matched chars) populated by the search pass;
    /// the cell view uses this to draw highlights.
    public var matchedIndices: [Int]

    /// Score from PaletteFuzzy. Higher = better.
    public var score: Int

    public init(title: String,
                subtitle: String? = nil,
                symbol: String? = nil,
                payload: Any,
                matchedIndices: [Int] = [],
                score: Int = 0) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.payload = payload
        self.matchedIndices = matchedIndices
        self.score = score
    }
}

public protocol PaletteProvider: AnyObject {
    /// Human label shown in the palette title bar.
    var displayName: String { get }

    /// Placeholder text for the search field.
    var placeholder: String { get }

    /// Maximum results returned per query (palette displays this many).
    var maxResults: Int { get }

    /// Return ranked + filtered items for `query`. Implementations should
    /// run fuzzy matching internally so the palette window stays generic.
    func items(for query: String) -> [PaletteItem]

    /// Activate the item the user picked.
    func activate(_ item: PaletteItem)
}

public extension PaletteProvider {
    var maxResults: Int { 200 }
}
