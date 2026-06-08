// SPDX-License-Identifier: MIT
// RNotePad — one window per text document.

import AppKit

public final class EditorWindowController: NSWindowController, NSWindowDelegate {

    public let editorViewController: EditorViewController

    public init(document: TextDocument) {
        let vc = EditorViewController(document: document)
        self.editorViewController = vc

        let window = NSWindow(contentViewController: vc)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 960, height: 640))
        window.title = "RNotePad"
        window.tabbingMode = .preferred
        window.setFrameAutosaveName("RNotePadMainWindow")
        window.center()

        super.init(window: window)
        window.delegate = self
        window.registerForDraggedTypes([.fileURL])
    }

    // NSWindow forwards these to its delegate when no view consumed the drag.

    public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
            ? .copy : []
    }

    public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil),
              let urls = items as? [URL], !urls.isEmpty else { return false }
        let dc = NSDocumentController.shared
        for url in urls {
            dc.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSLog("[RNotePad] window-drag-open failed: \(url.path) — \(error)") }
            }
        }
        return true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }
}
