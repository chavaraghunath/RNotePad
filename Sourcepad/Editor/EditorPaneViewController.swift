// SPDX-License-Identifier: MIT
// Sourcepad — left pane of the editor split. Hosts the Scintilla NSView, the
// file-drop overlay, the appearance-change forwarder, and the find/replace bar.

import AppKit

public final class EditorPaneViewController: NSViewController {

    public weak var document: TextDocument?
    public var onTextChanged: (() -> Void)?

    private var sciView: NSView!
    private var currentLexer: String?
    private var findBar: FindBar!
    private var findBarHeight: NSLayoutConstraint!

    public init(document: TextDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    public override func loadView() {
        let root = AppearanceForwardingView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        root.onAppearanceChange = { [weak self] in self?.applyColorScheme() }

        // Find bar at the top, height 0 by default (hidden).
        let bar = FindBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.onClose = { [weak self] in self?.hideFindBar() }
        root.addSubview(bar)
        self.findBar = bar

        // Editor container — sits below find bar, fills remaining space.
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(container)

        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 0)
        self.findBarHeight = heightConstraint

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            heightConstraint,

            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: bar.bottomAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        // Scintilla view + drop overlay use autoresizing inside the container.
        let editor = SciMakeView(NSRect(x: 0, y: 0, width: 600, height: 600))
        editor.autoresizingMask = [.width, .height]
        container.addSubview(editor)
        self.sciView = editor

        let dropOverlay = FileDropOverlay(frame: editor.frame)
        dropOverlay.autoresizingMask = [.width, .height]
        container.addSubview(dropOverlay)

        installNotificationHandler()
        bar.editorView = editor
        applyPreferences()  // sets font, tab width, line-number visibility

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged(_:)),
            name: .sourcepadPreferencesChanged,
            object: nil
        )

        self.view = root
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func preferencesChanged(_ note: Notification) {
        applyPreferences()
        applyColorScheme()
    }

    private func applyPreferences() {
        let p = Preferences.shared
        SciSetEditorFont(sciView, p.fontName, p.fontSize)
        SciSetTabWidth(sciView, p.tabWidth)
        SciSetUseTabs(sciView, !p.useSpacesForTabs)
        SciShowLineNumbers(sciView, p.showLineNumbers)
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(sciView)
    }

    // MARK: - Document wiring

    public func documentContentsDidLoad() {
        guard let doc = document else { return }
        SciSetText(sciView, doc.contents)

        let filename = doc.fileURL?.lastPathComponent ?? "untitled.txt"
        let lexerName = LexerRegistry.lexer(for: filename)
        currentLexer = lexerName
        _ = SciApplyLexer(sciView, lexerName)
        applyColorScheme()
        SciSetSavePoint(sciView)
    }

    public var currentText: String { SciGetText(sciView) }

    public func markSavePoint() { SciSetSavePoint(sciView) }

    public func setLexer(_ name: String?) {
        currentLexer = name
        _ = SciApplyLexer(sciView, name)
        applyColorScheme()
    }

    public var activeLexer: String? { currentLexer }

    /// Debug helper: dump the first `maxBytes` of the buffer with their style indices.
    public func dumpStyles(maxBytes: Int) -> String {
        return SciDumpStyles(sciView, maxBytes)
    }

    // MARK: - Find bar

    public func showFindBar(prefill: String? = nil, withReplace: Bool = false) {
        findBarHeight.constant = withReplace ? 66 : 34
        findBar.show(prefill: prefill, withReplace: withReplace)
    }

    public func hideFindBar() {
        findBarHeight.constant = 0
        view.window?.makeFirstResponder(sciView)
    }

    public var isFindBarVisible: Bool { findBarHeight.constant > 0 }

    public func findBarNext()     { findBar.findNext(nil) }
    public func findBarPrevious() { findBar.findPrevious(nil) }

    // Responder-chain entry points wired from MainMenu (nil-target items).

    @objc public func sourcepadShowFind(_ sender: Any?) {
        showFindBar(prefill: nil, withReplace: false)
    }

    @objc public func sourcepadShowFindReplace(_ sender: Any?) {
        showFindBar(prefill: nil, withReplace: true)
    }

    @objc public func sourcepadFindNext(_ sender: Any?) {
        if !isFindBarVisible { showFindBar() }
        findBarNext()
    }

    @objc public func sourcepadFindPrevious(_ sender: Any?) {
        if !isFindBarVisible { showFindBar() }
        findBarPrevious()
    }

    // MARK: - Light/dark hot-swap

    private func applyColorScheme() {
        let mode = ThemeMode.from(view.effectiveAppearance)
        let scheme = SchemeLibrary.scheme(for: currentLexer, mode: mode)
        // Font/size must be set BEFORE SciApplyPalette — STYLECLEARALL propagates
        // STYLE_DEFAULT to every style slot, including font.
        let p = Preferences.shared
        SciSetEditorFont(sciView, p.fontName, p.fontSize)
        SciApplyPalette(
            sciView,
            scheme.bridgePalette(),
            scheme.defaultFg,
            scheme.defaultBg,
            scheme.lineNumberFg,
            scheme.lineNumberBg
        )
        if let lex = currentLexer {
            _ = SciApplyLexer(sciView, lex)
            // Lexilla's hypertext lexer doesn't sub-lex CSS — post-process to
            // color content inside <style> blocks.
            if lex == "hypertext" || lex == "xml" {
                CSSStyler.applyToHTML(view: sciView, text: SciGetText(sciView))
            }
        }
    }

    // MARK: - Scintilla notifications

    private func installNotificationHandler() {
        SciSetNotificationHandler(sciView) { [weak self] type in
            guard let self else { return }
            switch type {
            case .savePointReached:
                self.document?.updateChangeCount(.changeCleared)
            case .savePointLeft:
                self.document?.updateChangeCount(.changeDone)
            case .modified:
                self.onTextChanged?()
            default:
                break
            }
        }
    }
}
