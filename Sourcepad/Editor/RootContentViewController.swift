// SPDX-License-Identifier: MIT
// Sourcepad — wraps the editor split view + bottom status bar in a single
// content view controller so the window has one root responder.
//
// Layout (top → bottom):
//   ┌──────────────────────────────────────────┐
//   │  vertical NSSplitView                     │
//   │   ├─ EditorViewController (sidebar|edit|preview)  ← not collapsible
//   │   └─ TerminalPanelViewController          ← collapsible, full width
//   ├──────────────────────────────────────────┤
//   │  StatusBarView (22pt, fixed)              │
//   └──────────────────────────────────────────┘
//
// The terminal panel is a sibling of the editor split, so it spans the full
// window width (under sidebar + editor + preview), VS Code style. Toggling it
// reuses the same NSSplitViewItem.animator().isCollapsed pattern the sidebar
// and preview already use.

import AppKit

public final class RootContentViewController: NSViewController {

    public let editorVC: EditorViewController
    public let statusBar: StatusBarView
    public let terminalPanel: TerminalPanelViewController

    private let vSplit = NSSplitViewController()
    private var editorItem: NSSplitViewItem!
    private var terminalItem: NSSplitViewItem!

    /// Default height the terminal expands to the first time it is shown.
    private static let defaultTerminalHeight: CGFloat = 220

    public init(editor: EditorViewController, statusBar: StatusBarView) {
        self.editorVC = editor
        self.statusBar = statusBar
        self.terminalPanel = TerminalPanelViewController()
        super.init(nibName: nil, bundle: nil)

        // New shells open at the project root, falling back to the current
        // document's folder, then $HOME.
        terminalPanel.workingDirectoryProvider = { [weak self] in
            self?.resolveWorkingDirectory()
                ?? FileManager.default.homeDirectoryForCurrentUser.path
        }

        vSplit.splitView.isVertical = false           // horizontal divider → stack
        vSplit.splitView.dividerStyle = .thin
        vSplit.splitView.autosaveName = "SourcepadEditorTerminalSplit"

        editorItem = NSSplitViewItem(viewController: editor)
        editorItem.canCollapse = false
        editorItem.holdingPriority = NSLayoutConstraint.Priority(250)

        terminalItem = NSSplitViewItem(viewController: terminalPanel)
        terminalItem.canCollapse = true
        terminalItem.minimumThickness = 120
        terminalItem.holdingPriority = NSLayoutConstraint.Priority(260)
        // Always start hidden — like the preview pane. The panel only appears
        // when the user toggles it (⌃` or View ▸ Toggle Terminal), and no shell
        // is spawned until then.
        terminalItem.isCollapsed = true

        vSplit.addSplitViewItem(editorItem)
        vSplit.addSplitViewItem(terminalItem)
        addChild(vSplit)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1180, height: 720))

        let splitView = vSplit.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(splitView)

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusBar)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: root.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

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

    // MARK: - Terminal panel

    public var isShowingTerminal: Bool { !terminalItem.isCollapsed }

    /// Show or hide the bottom terminal panel. Spawns the first session on
    /// first reveal and focuses the shell.
    public func toggleTerminal() {
        let willShow = terminalItem.isCollapsed
        if willShow {
            ensureReasonableTerminalHeight()
            terminalItem.animator().isCollapsed = false
            terminalPanel.ensureSession()
            DispatchQueue.main.async { [weak self] in self?.terminalPanel.focusActiveTerminal() }
        } else {
            terminalItem.animator().isCollapsed = true
            // Return focus to the editor.
            if let pane = editorVC.editorPane?.view { view.window?.makeFirstResponder(pane) }
        }
        view.window?.toolbar?.validateVisibleItems()
    }

    /// If the divider sits flush at the bottom (no remembered height), give the
    /// terminal a sensible default the first time it is shown.
    private func ensureReasonableTerminalHeight() {
        let split = vSplit.splitView
        let h = split.bounds.height
        guard h > 0 else { return }
        let current = terminalPanel.view.bounds.height
        if current < 60 {
            split.setPosition(h - Self.defaultTerminalHeight, ofDividerAt: 0)
        }
    }

    // MARK: - Menu actions (routed via the responder chain)

    @objc public func sourcepadToggleTerminal(_ sender: Any?) {
        toggleTerminal()
    }

    @objc public func sourcepadNewTerminal(_ sender: Any?) {
        if terminalItem.isCollapsed {
            ensureReasonableTerminalHeight()
            terminalItem.animator().isCollapsed = false
            view.window?.toolbar?.validateVisibleItems()
        }
        terminalPanel.newTerminal()
    }

    // MARK: - Working directory resolution

    private func resolveWorkingDirectory() -> String? {
        if let root = WorkspaceManager.shared.activeWorkspace.roots.first {
            return root.path
        }
        if let docDir = editorVC.document?.fileURL?.deletingLastPathComponent() {
            return docDir.path
        }
        if let sidebarRoot = editorVC.sidebarPane.rootURL {
            return sidebarRoot.path
        }
        return nil
    }
}
