// SPDX-License-Identifier: MIT
// Sourcepad — `@`-mention chips for the agent input.
//
// When the user accepts an `@`-completion, the typed `@query` run is replaced
// by a single attachment "pill" (Cursor/Claude-style) that renders as a small
// rounded chip and carries the exact file path as data. This makes mentions
// unambiguous (paths with spaces, duplicates, deletions) — the input no longer
// relies on whitespace-delimited path scanning for accepted mentions.
//
// A `Mention` always resolves to a concrete file path, so the rest of the
// pipeline (AgentContextProvider) only ever needs a list of paths to attach.

import AppKit

/// One accepted `@`-mention. Everything resolves to a real file path, so the
/// "active file" affordance is just a file mention pre-filled with the active
/// document's path — no special-casing downstream.
public struct Mention: Equatable {
    public enum Kind { case file, symbol }
    public let kind: Kind
    /// Absolute, canonical path the mention attaches.
    public let absolutePath: String
    /// Short label shown in the chip (basename, or symbol name).
    public let displayName: String

    public init(kind: Kind, absolutePath: String, displayName: String) {
        self.kind = kind
        self.absolutePath = absolutePath
        self.displayName = displayName
    }
}

/// An `NSTextAttachment` carrying a `Mention`. Lives inside the input's text
/// storage as a single object-replacement character.
public final class MentionAttachment: NSTextAttachment {
    public let mention: Mention

    public init(mention: Mention, font: NSFont) {
        self.mention = mention
        super.init(data: nil, ofType: nil)
        attachmentCell = MentionCell(mention: mention, font: font)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}

/// Draws the pill: rounded accent-tinted background, SF Symbol glyph, and the
/// mention's display name. Appearance-aware (resolves colors at draw time).
final class MentionCell: NSTextAttachmentCell {
    private let mention: Mention
    private let chipFont: NSFont

    private static let hPad: CGFloat = 6
    private static let iconGap: CGFloat = 3
    private static let iconSize: CGFloat = 11

    init(mention: Mention, font: NSFont) {
        self.mention = mention
        self.chipFont = font
        super.init()
    }
    required init(coder: NSCoder) { fatalError("init(coder:) not used") }

    private var glyph: String {
        mention.kind == .symbol ? "number" : "doc.text"
    }

    private var labelAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: max(10, chipFont.pointSize - 1)),
         .foregroundColor: NSColor.controlAccentColor]
    }

    private var textWidth: CGFloat {
        (mention.displayName as NSString).size(withAttributes: labelAttributes).width
    }

    override func cellSize() -> NSSize {
        let w = Self.hPad + Self.iconSize + Self.iconGap + ceil(textWidth) + Self.hPad
        return NSSize(width: w, height: chipFont.pointSize + 7)
    }

    /// Keep the pill visually centered on the text baseline.
    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: floor(chipFont.descender) - 1)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let accent = NSColor.controlAccentColor
        let bg = accent.withAlphaComponent(0.14)

        let rect = cellFrame.insetBy(dx: 0, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        bg.setFill()
        path.fill()

        var x = rect.minX + Self.hPad
        if let img = NSImage(systemSymbolName: glyph, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: Self.iconSize, weight: .regular)
                .applying(.init(paletteColors: [accent]))
            let tinted = img.withSymbolConfiguration(cfg) ?? img
            let iconRect = NSRect(x: x,
                                  y: rect.midY - Self.iconSize / 2,
                                  width: Self.iconSize,
                                  height: Self.iconSize)
            tinted.draw(in: iconRect)
            x += Self.iconSize + Self.iconGap
        }

        let label = mention.displayName as NSString
        let attrs = labelAttributes
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
}
