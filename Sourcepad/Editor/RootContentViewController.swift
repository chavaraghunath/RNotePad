// SPDX-License-Identifier: MIT
// Sourcepad — wraps the editor split view, bottom terminal, right-side agent
// panel, and status bar in a single content view controller so the window has
// one root responder.
//
// Layout (VS Code geometry):
//   ┌───────────────────────────────────────────────┬──────────┐
//   │  vertical split (left column)                  │  agent   │
//   │   ├─ EditorViewController (sidebar|edit|prev)  │  panel   │
//   │   └─ TerminalPanelViewController (collapsible) │ (collap- │
//   │                                                │  sible)  │
//   ├────────────────────────────────────────────────┴─────────┤
//   │  StatusBarView (22pt, fixed)                              │
//   └──────────────────────────────────────────────────────────┘
//
//   • Outer horizontal split: [ left column | agent panel ].
//   • Left column is itself a vertical split: editor stacked over terminal.
//   So the terminal sits under the editor only, while the agent panel spans the
//   full height of the right column — exactly VS Code's panel/secondary-sidebar
//   arrangement. All three toggles reuse the same
//   NSSplitViewItem.animator().isCollapsed pattern.

import AppKit

public final class RootContentViewController: NSViewController {

    public let editorVC: EditorViewController
    public let statusBar: StatusBarView
    public let terminalPanel: TerminalPanelViewController
    public let agentPanel: AgentPanelViewController

    private let hSplit = NSSplitViewController()   // [ leftColumn | agent ]
    private let vSplit = NSSplitViewController()   // [ editor / terminal ]
    private var editorItem: NSSplitViewItem!
    private var terminalItem: NSSplitViewItem!
    private var leftColumnItem: NSSplitViewItem!
    private var agentItem: NSSplitViewItem!

    /// Default thickness panels expand to the first time they are shown.
    private static let defaultTerminalHeight: CGFloat = 220
    private static let defaultAgentWidth: CGFloat = 360

    public init(editor: EditorViewController, statusBar: StatusBarView) {
        self.editorVC = editor
        self.statusBar = statusBar
        self.terminalPanel = TerminalPanelViewController()
        self.agentPanel = AgentPanelViewController()
        super.init(nibName: nil, bundle: nil)

        // New shells / conversations open at the project root, falling back to
        // the current document's folder, then $HOME.
        let cwdProvider: () -> String = { [weak self] in
            self?.resolveWorkingDirectory()
                ?? FileManager.default.homeDirectoryForCurrentUser.path
        }
        terminalPanel.workingDirectoryProvider = cwdProvider
        agentPanel.workingDirectoryProvider = cwdProvider

        // --- Left column: editor stacked over terminal (horizontal divider) ---
        vSplit.splitView.isVertical = false
        vSplit.splitView.dividerStyle = .thin
        // Deliberately no autosaveName: like the preview pane, the terminal must
        // always start hidden. Persisting the divider would restore it expanded.

        editorItem = NSSplitViewItem(viewController: editor)
        editorItem.canCollapse = false
        editorItem.holdingPriority = NSLayoutConstraint.Priority(250)

        terminalItem = NSSplitViewItem(viewController: terminalPanel)
        terminalItem.canCollapse = true
        terminalItem.minimumThickness = 120
        terminalItem.holdingPriority = NSLayoutConstraint.Priority(260)
        terminalItem.isCollapsed = true   // always start hidden

        vSplit.addSplitViewItem(editorItem)
        vSplit.addSplitViewItem(terminalItem)

        // --- Outer column split: left column | agent panel (vertical divider) ---
        hSplit.splitView.isVertical = true
        hSplit.splitView.dividerStyle = .thin

        leftColumnItem = NSSplitViewItem(viewController: vSplit)
        leftColumnItem.canCollapse = false
        leftColumnItem.holdingPriority = NSLayoutConstraint.Priority(250)

        agentItem = NSSplitViewItem(viewController: agentPanel)
        agentItem.canCollapse = true
        agentItem.minimumThickness = 280
        agentItem.holdingPriority = NSLayoutConstraint.Priority(260)
        agentItem.isCollapsed = true   // always start hidden, like the terminal

        hSplit.addSplitViewItem(leftColumnItem)
        hSplit.addSplitViewItem(agentItem)
        addChild(hSplit)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1180, height: 720))

        let splitView = hSplit.view
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

    /// Show or hide the bottom terminal panel. Spawns the first session on first
    /// reveal and focuses the shell.
    public func toggleTerminal() {
        let willShow = terminalItem.isCollapsed
        if willShow {
            ensureReasonableTerminalHeight()
            terminalItem.animator().isCollapsed = false
            terminalPanel.ensureSession()
            DispatchQueue.main.async { [weak self] in self?.terminalPanel.focusActiveTerminal() }
        } else {
            terminalItem.animator().isCollapsed = true
            if let pane = editorVC.editorPane?.view { view.window?.makeFirstResponder(pane) }
        }
        view.window?.toolbar?.validateVisibleItems()
    }

    private func ensureReasonableTerminalHeight() {
        let split = vSplit.splitView
        let h = split.bounds.height
        guard h > 0 else { return }
        let current = terminalPanel.view.bounds.height
        if current < 60 {
            split.setPosition(h - Self.defaultTerminalHeight, ofDividerAt: 0)
        }
    }

    // MARK: - Agent panel

    public var isShowingAgent: Bool { !agentItem.isCollapsed }

    /// Show or hide the right-side agent conversation panel.
    public func toggleAgent() {
        let willShow = agentItem.isCollapsed
        if willShow {
            ensureReasonableAgentWidth()
            agentItem.animator().isCollapsed = false
            DispatchQueue.main.async { [weak self] in self?.agentPanel.focusInput() }
        } else {
            agentItem.animator().isCollapsed = true
            if let pane = editorVC.editorPane?.view { view.window?.makeFirstResponder(pane) }
        }
        view.window?.toolbar?.validateVisibleItems()
    }

    private func ensureReasonableAgentWidth() {
        let split = hSplit.splitView
        let w = split.bounds.width
        guard w > 0 else { return }
        if agentPanel.view.bounds.width < 120 {
            split.setPosition(w - Self.defaultAgentWidth, ofDividerAt: 0)
        }
    }

    // MARK: - Menu / responder-chain actions

    @objc public func sourcepadToggleTerminal(_ sender: Any?) { toggleTerminal() }

    @objc public func sourcepadNewTerminal(_ sender: Any?) {
        if terminalItem.isCollapsed {
            ensureReasonableTerminalHeight()
            terminalItem.animator().isCollapsed = false
            view.window?.toolbar?.validateVisibleItems()
        }
        terminalPanel.newTerminal()
    }

    @objc public func sourcepadToggleAgent(_ sender: Any?) { toggleAgent() }

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

extension RootContentViewController: NSMenuItemValidation {
    /// Check-mark the View-menu toggles while their panel is showing.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(sourcepadToggleTerminal(_:)) {
            menuItem.state = isShowingTerminal ? .on : .off
        } else if menuItem.action == #selector(sourcepadToggleAgent(_:)) {
            menuItem.state = isShowingAgent ? .on : .off
        }
        return true
    }
}
