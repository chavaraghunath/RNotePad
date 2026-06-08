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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }
}
