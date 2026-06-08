// SPDX-License-Identifier: MIT
// Rnotepad — transparent overlay that catches file-URL drops above the
// Scintilla editor view. Scintilla's NSView consumes drag events for plain
// text DnD; we only want to override file-URL drops so the rest of Scintilla's
// drag handling still works.
//
// Strategy:
//   - register for ONLY .fileURL drag types
//   - return nil from hitTest so mouse events pass through to Scintilla
//   - AppKit uses the registered-types list (not hitTest) to find drop
//     targets, so file drops still hit us

import AppKit

final class FileDropOverlay: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    // Make all mouse events pass through to underlying views.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // We're transparent — don't draw anything.
    override func draw(_ dirtyRect: NSRect) { /* no-op */ }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        DebugLog.log("FileDropOverlay.draggingEntered")
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
            ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        DebugLog.log("FileDropOverlay.performDragOperation")
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil),
              let urls = items as? [URL], !urls.isEmpty else { return false }
        let dc = NSDocumentController.shared
        for url in urls {
            DebugLog.log("  drop-open: \(url.path)")
            dc.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { DebugLog.log("  drop-open failed: \(url.path) — \(error)") }
            }
        }
        return true
    }
}
