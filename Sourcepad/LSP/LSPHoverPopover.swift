// SPDX-License-Identifier: MIT
// Sourcepad — popover showing the LSP hover-text near the caret.
//
// Triggered by F1 (configurable). Future phases will surface this on
// mouse-dwell too via the SCN_DWELLSTART notification (Phase 1 wired
// the dispatcher; we just need a small dwell-time setter call).

import AppKit

public final class LSPHoverPopover {

    public static let shared = LSPHoverPopover()

    private var popover: NSPopover?

    /// Show the popover anchored to the caret's pixel location in `view`.
    /// `markdown` is the raw markdown from the LSP server's hover response.
    public func show(markdown: String,
                     anchoredTo view: NSView,
                     atCaretByte caretByte: Int) {
        dismiss()
        let anchorPoint = SciPointFromPosition(view, caretByte)

        // Render the markdown as attributed string. We keep it simple —
        // monospace, foreground = label color. Full markdown rendering
        // (links, code blocks, headings) lands in a later UI polish pass.
        let attr = NSMutableAttributedString(
            string: markdown,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
            ])

        let textView = NSTextView()
        textView.isEditable = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textStorage?.setAttributedString(attr)
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let size = NSSize(width: 420, height: 200)
        scroll.frame = NSRect(origin: .zero, size: size)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.frame = NSRect(origin: .zero, size: size)

        let host = NSViewController()
        host.view = scroll
        host.preferredContentSize = size

        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = host
        pop.show(relativeTo: NSRect(x: anchorPoint.x, y: anchorPoint.y, width: 1, height: 14),
                 of: view,
                 preferredEdge: .maxY)
        self.popover = pop
    }

    public func dismiss() {
        popover?.performClose(nil)
        popover = nil
    }
}
