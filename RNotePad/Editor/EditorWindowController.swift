// SPDX-License-Identifier: MIT
// RNotePad — one window per text document.

import AppKit

public final class EditorWindowController: NSWindowController {

    public let editorViewController: EditorViewController

    public init(document: TextDocument) {
        let frame = NSRect(x: 0, y: 0, width: 960, height: 640)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred
        window.center()
        window.setFrameAutosaveName("RNotePadMainWindow")

        let vc = EditorViewController(document: document)
        self.editorViewController = vc

        super.init(window: window)
        window.contentViewController = vc
        window.delegate = self
        self.document = document
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    public override func windowDidLoad() {
        super.windowDidLoad()
    }
}

extension EditorWindowController: NSWindowDelegate {
    // Title automatically reflects document.displayName; nothing extra here for v0.
}
