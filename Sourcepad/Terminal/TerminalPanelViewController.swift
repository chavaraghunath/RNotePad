// SPDX-License-Identifier: MIT
// Sourcepad — the bottom integrated-terminal panel.
//
// Owns a tab strip and a stack of TerminalSessions (one PTY-backed shell
// each). One panel exists per window. RootContentViewController hosts it as
// the bottom item of a vertical split and drives show/hide.
//
// Lifecycle: sessions are created lazily — the first one is spawned when the
// panel is first revealed (ensureSession). Closing a tab terminates its shell;
// when a shell exits on its own (e.g. `exit`) its tab is dropped. The window
// controller calls terminateAll() on close so no shells are orphaned.

import AppKit

public final class TerminalPanelViewController: NSViewController {

    /// Resolves the directory a new shell should start in. Injected by the
    /// owner (RootContentViewController) so the terminal opens at the project
    /// root / current document, not always $HOME.
    public var workingDirectoryProvider: (() -> String)?

    private let tabBar = TerminalTabBar()
    private let container = NSView()
    private let emptyLabel = NSTextField(labelWithString: "No terminal sessions")

    private var sessions: [TerminalSession] = []
    private var activeID: Int = -1

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 240))
        root.wantsLayer = true

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.onSelect = { [weak self] id in self?.select(id: id) }
        tabBar.onClose  = { [weak self] id in self?.closeSession(id: id) }
        tabBar.onNew    = { [weak self] in self?.newSession(focus: true) }
        root.addSubview(tabBar)

        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(container)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: root.topAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: TerminalTabBar.barHeight),

            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        self.view = root
    }

    // MARK: - Public API (called by RootContentViewController)

    /// Ensure at least one session exists. Called when the panel is revealed.
    public func ensureSession() {
        if sessions.isEmpty { newSession(focus: true) }
    }

    /// Always spawn a fresh session and make it active (the "+" / New Terminal
    /// command). Distinct from ensureSession, which is a no-op when non-empty.
    public func newTerminal() {
        newSession(focus: true)
    }

    /// Move keyboard focus into the active terminal.
    public func focusActiveTerminal() {
        guard let s = activeSession else { return }
        view.window?.makeFirstResponder(s.terminalView)
    }

    /// Terminate every shell. Called on window close.
    public func terminateAll() {
        for s in sessions { s.terminate() }
        sessions.removeAll()
        activeID = -1
    }

    public var sessionCount: Int { sessions.count }

    // MARK: - Session management

    private var activeSession: TerminalSession? {
        sessions.first { $0.id == activeID }
    }

    @discardableResult
    private func newSession(focus: Bool) -> TerminalSession {
        let cwd = workingDirectoryProvider?() ?? FileManager.default.homeDirectoryForCurrentUser.path
        let session = TerminalSession(startDirectory: cwd)
        session.onTitleChanged = { [weak self] _ in self?.refreshTabBar() }
        session.onExited = { [weak self] s in self?.handleExit(of: s) }
        addChild(session)
        sessions.append(session)
        activeID = session.id
        installActiveView()
        refreshTabBar()
        if focus {
            // The view must be in the hierarchy before it can take first responder.
            DispatchQueue.main.async { [weak self] in self?.focusActiveTerminal() }
        }
        return session
    }

    private func select(id: Int) {
        guard id != activeID, sessions.contains(where: { $0.id == id }) else { return }
        activeID = id
        installActiveView()
        refreshTabBar()
        focusActiveTerminal()
    }

    private func closeSession(id: Int) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions.remove(at: idx)
        session.terminate()
        session.removeFromParent()
        if activeID == id {
            // Activate the neighbour that takes its place (or the new last one).
            activeID = sessions[safe: idx]?.id ?? sessions.last?.id ?? -1
        }
        installActiveView()
        refreshTabBar()
    }

    private func handleExit(of session: TerminalSession) {
        // Shell exited on its own (e.g. user typed `exit`). Drop its tab.
        closeSession(id: session.id)
    }

    // MARK: - View swapping

    private func installActiveView() {
        for sub in container.subviews where sub !== emptyLabel {
            sub.removeFromSuperview()
        }
        guard let s = activeSession else {
            emptyLabel.isHidden = false
            return
        }
        emptyLabel.isHidden = true
        let v = s.view
        v.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            v.topAnchor.constraint(equalTo: container.topAnchor),
            v.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func refreshTabBar() {
        let models = sessions.map { TerminalTabModel(id: $0.id, title: $0.displayTitle) }
        tabBar.update(tabs: models, selectedID: activeID)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
