// SPDX-License-Identifier: MIT
// RNotePad — root container for the editor. Two jobs:
//   1. Forward viewDidChangeEffectiveAppearance to the view controller
//      (NSViewController doesn't receive this call, NSView does).
//   2. Accept file drops anywhere on the editor surface and hand each URL
//      to NSDocumentController so it opens in a (new) window.

import AppKit

final class AppearanceForwardingView: NSView {
    var onAppearanceChange: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Accept file URLs (including from Finder).
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil),
              let urls = items as? [URL], !urls.isEmpty else { return false }
        let dc = NSDocumentController.shared
        for url in urls {
            dc.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSLog("[RNotePad] drag-open failed: \(url.path) — \(error)") }
            }
        }
        return true
    }
}
