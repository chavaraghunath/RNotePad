// SPDX-License-Identifier: MIT
// Sourcepad — wraps the editor split view + bottom status bar in a single
// content view controller so the window has one root responder.

import AppKit

public final class RootContentViewController: NSViewController {

    public let editorVC: EditorViewController
    public let statusBar: StatusBarView

    public init(editor: EditorViewController, statusBar: StatusBarView) {
        self.editorVC = editor
        self.statusBar = statusBar
        super.init(nibName: nil, bundle: nil)
        addChild(editor)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1180, height: 720))

        let editorView = editorVC.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(editorView)

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusBar)

        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: root.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),
        ])

        self.view = root
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        statusBar.refresh()
    }
}
