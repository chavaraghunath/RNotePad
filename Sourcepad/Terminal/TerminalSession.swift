// SPDX-License-Identifier: MIT
// Sourcepad — one integrated-terminal session.
//
// Thin wrapper around SwiftTerm's LocalProcessTerminalView (a real PTY-backed
// VT100/xterm emulator). Each session owns one shell subprocess. The view
// controller adopts LocalProcessTerminalViewDelegate to surface the title /
// working-directory the shell reports (via OSC sequences) and to notice when
// the shell exits so the panel can drop the tab.
//
// SwiftTerm is vendored under ThirdParty/SwiftTerm and compiled into the app
// module, so there is no `import SwiftTerm` — the types are in scope directly.

import AppKit

public final class TerminalSession: NSViewController, LocalProcessTerminalViewDelegate {

    /// Stable identity for tab tracking. Monotonic per process launch.
    public let id: Int

    /// The live emulator view. Created lazily in loadView.
    public private(set) var terminalView: LocalProcessTerminalView!

    /// Working directory the session was launched in (absolute path).
    public let startDirectory: String

    /// Human-facing tab label. Starts as the shell name, then tracks whatever
    /// the shell reports via OSC title / cwd updates.
    public private(set) var displayTitle: String

    /// True once the child shell has exited.
    public private(set) var hasExited = false

    /// Panel callbacks — set by TerminalPanelViewController.
    public var onTitleChanged: ((TerminalSession) -> Void)?
    public var onExited: ((TerminalSession) -> Void)?

    private static var nextID = 1

    public init(startDirectory: String) {
        self.id = TerminalSession.nextID
        TerminalSession.nextID += 1
        self.startDirectory = startDirectory
        self.displayTitle = (URL(fileURLWithPath: startDirectory).lastPathComponent.isEmpty
                      ? "Terminal" : URL(fileURLWithPath: startDirectory).lastPathComponent)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override func loadView() {
        let term = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 240))
        term.processDelegate = self
        term.translatesAutoresizingMaskIntoConstraints = true
        term.autoresizingMask = [.width, .height]
        self.terminalView = term
        self.view = term
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        applyAppearance()
        launch()
        // Follow editor font/size changes and system light/dark switches.
        NotificationCenter.default.addObserver(
            self, selector: #selector(reapplyAppearance),
            name: .sourcepadPreferencesChanged, object: nil)
        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(reapplyAppearance),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
    }

    @objc private func reapplyAppearance() {
        guard isViewLoaded else { return }
        applyAppearance()
    }

    // MARK: - Launch

    private func launch() {
        let shell = userLoginShell()
        // Launch as an interactive login shell so the user's normal profile,
        // PATH and prompt apply — same as opening Terminal.app.
        let env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        terminalView.startProcess(executable: shell,
                                  args: ["-l"],
                                  environment: env,
                                  execName: nil,
                                  currentDirectory: startDirectory)
    }

    private func userLoginShell() -> String {
        if let s = ProcessInfo.processInfo.environment["SHELL"], !s.isEmpty,
           FileManager.default.isExecutableFile(atPath: s) {
            return s
        }
        return "/bin/zsh"
    }

    /// Tear down the shell subprocess. Called when the tab or window closes.
    public func terminate() {
        guard !hasExited else { return }
        terminalView.processDelegate = nil
        // SwiftTerm's LocalProcess.terminate() sends SIGTERM to the shell.
        terminalView.process?.terminate()
    }

    // MARK: - Appearance

    /// Match the editor font and follow light/dark. Kept deliberately simple;
    /// a full themed palette can come later via installColors(_:).
    public func applyAppearance() {
        let size = max(9, Preferences.shared.fontSize)
        let name = Preferences.shared.fontName
        if let f = NSFont(name: name, size: size) {
            terminalView.font = f
        } else {
            terminalView.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        let dark = ThemeMode.from(view.effectiveAppearance) == .dark
        terminalView.nativeBackgroundColor = dark
            ? NSColor(calibratedWhite: 0.10, alpha: 1.0)
            : NSColor(calibratedWhite: 0.99, alpha: 1.0)
        terminalView.nativeForegroundColor = dark
            ? NSColor(calibratedWhite: 0.90, alpha: 1.0)
            : NSColor(calibratedWhite: 0.12, alpha: 1.0)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.displayTitle = trimmed
        onTitleChanged?(self)
    }

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let dir = directory, !dir.isEmpty else { return }
        let name = URL(fileURLWithPath: dir).lastPathComponent
        if !name.isEmpty {
            self.displayTitle = name
            onTitleChanged?(self)
        }
    }

    public func processTerminated(source: TerminalView, exitCode: Int32?) {
        hasExited = true
        onExited?(self)
    }
}
