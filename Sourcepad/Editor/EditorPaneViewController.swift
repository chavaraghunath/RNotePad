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

        // Find bar — auto-layout, height starts at 0 (hidden).
        let bar = FindBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.onClose = { [weak self] in self?.hideFindBar() }
        root.addSubview(bar)
        self.findBar = bar

        // Scintilla view — pinned to fill from the find bar's bottom downward.
        // Pure auto-layout (no autoresizing-inside-constraint-container hybrid)
        // so the editor always gets a valid size, which is what trackpad scroll
        // routing depends on.
        let editor = SciMakeView(.zero)
        editor.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(editor)
        self.sciView = editor

        // Drop overlay — same frame as the editor.
        let dropOverlay = FileDropOverlay(frame: .zero)
        dropOverlay.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(dropOverlay)

        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 0)
        self.findBarHeight = heightConstraint

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            heightConstraint,

            editor.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            editor.topAnchor.constraint(equalTo: bar.bottomAnchor),
            editor.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            dropOverlay.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            dropOverlay.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            dropOverlay.topAnchor.constraint(equalTo: editor.topAnchor),
            dropOverlay.bottomAnchor.constraint(equalTo: editor.bottomAnchor),
        ])

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

        // Restore caret from previous session if we have a record.
        if let url = doc.fileURL, let savedCaret = SessionRestore.shared.savedCaret(for: url) {
            let clamped = max(0, min(savedCaret, SciTextLengthBytes(sciView)))
            SciSetSelectionBytes(sciView, clamped, clamped)
        }
    }

    public func currentCaretByte() -> Int {
        let sel = SciGetSelectionBytes(sciView)
        return sel.location == NSNotFound ? 0 : Int(sel.location)
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

    // MARK: - Quick find (driven by the toolbar search field)

    private var quickQuery: String = ""

    /// Live-search from the toolbar: jump to the first match of `query`
    /// starting at the current selection (wrapping to the top if nothing found).
    public func quickFind(_ query: String) {
        quickQuery = query
        guard !query.isEmpty else { return }
        let sel = SciGetSelectionBytes(sciView)
        let start = sel.location == NSNotFound ? 0 : Int(sel.location)
        if let r = matchOrWrap(from: start, query: query) {
            SciSetSelectionBytes(sciView, Int(r.location), Int(r.location) + Int(r.length))
        }
    }

    /// Advance to the next or previous match of the last toolbar query.
    public func quickFindAdvance(forward: Bool) {
        guard !quickQuery.isEmpty else { return }
        let sel = SciGetSelectionBytes(sciView)
        if forward {
            let from = sel.location == NSNotFound ? 0 : Int(sel.location) + Int(sel.length)
            if let r = matchOrWrap(from: from, query: quickQuery) {
                SciSetSelectionBytes(sciView, Int(r.location), Int(r.location) + Int(r.length))
            }
        } else {
            let upper = sel.location == NSNotFound ? SciTextLengthBytes(sciView) : Int(sel.location)
            if let r = lastMatchBefore(upper, query: quickQuery) {
                SciSetSelectionBytes(sciView, Int(r.location), Int(r.location) + Int(r.length))
            }
        }
    }

    private func matchOrWrap(from start: Int, query: String) -> NSRange? {
        let r = SciFind(sciView, query, SciFindFlags(rawValue: 0), start, -1)
        if r.location != NSNotFound { return r }
        let wrap = SciFind(sciView, query, SciFindFlags(rawValue: 0), 0, -1)
        return wrap.location == NSNotFound ? nil : wrap
    }

    private func lastMatchBefore(_ upper: Int, query: String) -> NSRange? {
        var pos = 0
        var last: NSRange? = nil
        while pos < upper {
            let r = SciFind(sciView, query, SciFindFlags(rawValue: 0), pos, upper)
            if r.location == NSNotFound { break }
            last = r
            pos = Int(r.location) + max(1, Int(r.length))
        }
        if last != nil { return last }
        // Wrap: take the last match anywhere in the document.
        pos = 0
        let docLen = SciTextLengthBytes(sciView)
        while pos < docLen {
            let r = SciFind(sciView, query, SciFindFlags(rawValue: 0), pos, docLen)
            if r.location == NSNotFound { break }
            last = r
            pos = Int(r.location) + max(1, Int(r.length))
        }
        return last
    }

    // Responder-chain entry points wired from MainMenu (nil-target items).

    @objc public func sourcepadShowFindReplace(_ sender: Any?) {
        showFindBar(prefill: nil, withReplace: true)
    }

    @objc public func sourcepadFindNext(_ sender: Any?) {
        if !quickQuery.isEmpty {
            quickFindAdvance(forward: true)
        } else if isFindBarVisible {
            findBarNext()
        }
    }

    @objc public func sourcepadFindPrevious(_ sender: Any?) {
        if !quickQuery.isEmpty {
            quickFindAdvance(forward: false)
        } else if isFindBarVisible {
            findBarPrevious()
        }
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
