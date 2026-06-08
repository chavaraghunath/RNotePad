// SPDX-License-Identifier: MIT
// Sourcepad — left pane of the editor split. Hosts the Scintilla NSView, the
// file-drop overlay, the appearance-change forwarder, and the find/replace bar.

import AppKit

public final class EditorPaneViewController: NSViewController, EditorContent {

    public weak var document: TextDocument?
    public var onTextChanged: (() -> Void)?

    private var sciView: NSView!
    private var currentLexer: String?
    private var findBar: FindBar!
    private var findBarHeight: NSLayoutConstraint!
    private var gitGutter: GitDiffGutter!
    private var gitDebounce: DispatchWorkItem?

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
        installMarginClickHandler()
        bar.editorView = editor
        SciSetMultipleSelectionEnabled(editor, true)
        // Bookmark marker setup — scheme palette is light by default, refined
        // in applyColorScheme() once the doc loads.
        let mode = ThemeMode.from(root.effectiveAppearance)
        Bookmarks.shared.setupMarker(in: editor, scheme: SchemeLibrary.scheme(for: nil, mode: mode))

        // Git diff gutter
        self.gitGutter = GitDiffGutter(sciView: editor)
        gitGutter.setup(addedColor:    NSColor.systemGreen,
                        modifiedColor: NSColor.systemBlue,
                        deletedColor:  NSColor.systemRed)

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
        SciSetWrapMode(sciView, p.wordWrap ? .word : .none)
        SciSetZoom(sciView, p.zoomLevel)
        SciSetIndentGuides(sciView, p.indentGuides ? .lookBoth : .none)
        SciSetViewWhitespace(sciView, p.showInvisibles ? .visibleAlways : .invisible)
        SciSetViewEOL(sciView, p.showEOL)
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
        // Filename → lexer first; if that fails, fall back to shebang detection.
        let lexerName = LexerRegistry.lexer(for: filename) ?? doc.shebangLexer
        currentLexer = lexerName
        _ = SciApplyLexer(sciView, lexerName)
        applyColorScheme()
        SciSetSavePoint(sciView)

        // Restore caret from previous session if we have a record.
        if let url = doc.fileURL, let savedCaret = SessionRestore.shared.savedCaret(for: url) {
            let clamped = max(0, min(savedCaret, SciTextLengthBytes(sciView)))
            SciSetSelectionBytes(sciView, clamped, clamped)
        }

        // Restore persisted bookmarks for this file.
        Bookmarks.shared.restore(for: doc.fileURL, in: sciView)

        // Refresh git gutter against HEAD.
        if Preferences.shared.gitGutterEnabled {
            gitGutter.refresh(for: doc.fileURL, currentText: doc.contents)
        }

        // Spin up Tree-sitter for languages we have a grammar for.
        setupTreeSitter(for: lexerName, source: doc.contents)

        // Spin up the LSP session (no-op if no server is configured for
        // this language). Posts didOpen with the initial buffer.
        setupLSP(for: lexerName, source: doc.contents)
    }

    // MARK: - AI ghost text (Phase 11)

    public let ghostText = GhostText()

    private func charAddedForAI(codePoint: Int, position: Int) {
        // Skip on non-printable code points (newline, tab, etc.)
        guard codePoint >= 0x20 else { ghostText.dismiss(); return }
        let buf = SciGetText(sciView)
        // Convert UTF-16-ish position to a clamped int for substring slicing.
        // We rely on byte positions throughout; convert to String index.
        let bytePos = position
        let utf8 = buf.utf8
        guard bytePos <= utf8.count else { return }
        let prefixUTF8 = utf8.prefix(bytePos)
        let suffixUTF8 = utf8.dropFirst(bytePos)
        let prefix = String(decoding: Array(prefixUTF8), as: UTF8.self).suffix(2000)
        let suffix = String(decoding: Array(suffixUTF8), as: UTF8.self).prefix(500)
        ghostText.pane = self
        ghostText.scheduleAfterCharAdded(caretByte: bytePos,
                                         prefix: String(prefix),
                                         suffix: String(suffix))
    }

    @objc public func sourcepadAcceptGhostText(_ sender: Any?) {
        if !ghostText.acceptIfAvailable() { NSSound.beep() }
    }

    @objc public func sourcepadRewriteSelection(_ sender: Any?) {
        guard MLXService.shared.isAvailable else {
            NSSound.beep()
            return
        }
        RewriteSheet.shared.present(editor: self)
    }

    @objc public func sourcepadExplainSelection(_ sender: Any?) {
        let sel = SciGetSelectionBytes(sciView)
        guard sel.length > 0 else { NSSound.beep(); return }
        let text = SciGetText(sciView)
        let bytes = Array(text.utf8)
        guard sel.location + sel.length <= bytes.count else { return }
        let snippet = String(decoding: bytes[sel.location..<sel.location+sel.length], as: UTF8.self)
        AIAuxiliaries.explainSelection(text: snippet) { [weak self] explanation in
            guard let self, let explanation else { return }
            LSPHoverPopover.shared.show(markdown: explanation,
                                        anchoredTo: self.sciView,
                                        atCaretByte: sel.location)
        }
    }

    @objc public func sourcepadAICommit(_ sender: Any?) {
        AIAuxiliaries.generateCommitMessage { message in
            guard let message else { NSSound.beep(); return }
            let alert = NSAlert()
            alert.messageText = "AI Commit Message"
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
            tv.string = message
            tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let scroll = NSScrollView(frame: tv.frame)
            scroll.documentView = tv
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            alert.accessoryView = scroll
            alert.addButton(withTitle: "Copy")
            alert.addButton(withTitle: "Close")
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tv.string, forType: .string)
            }
        }
    }

    @objc public func sourcepadGenerateTest(_ sender: Any?) {
        let sel = SciGetSelectionBytes(sciView)
        let text = SciGetText(sciView)
        let snippet: String
        if sel.length > 0 {
            let bytes = Array(text.utf8)
            snippet = String(decoding: bytes[sel.location..<sel.location+sel.length], as: UTF8.self)
        } else {
            snippet = text
        }
        AIAuxiliaries.generateTestStub(for: snippet, language: currentLexer) { result in
            guard let result else { NSSound.beep(); return }
            // Open a new untitled document with the test stub.
            let doc = (try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)) as? TextDocument
            doc?.primaryEditorViewController()?.editorPane?.replaceWholeBuffer(with: result)
        }
    }

    // MARK: - LSP wiring (Phase 6)

    private var lspSession: LSPDocumentSession?

    private func setupLSP(for lexer: String?, source: String) {
        _ = lexer  // lexer kept in the signature for future hooks; LSP keys on URL extension
        // Close any prior session.
        lspSession?.close()
        lspSession = nil
        guard let doc = document,
              let url = doc.fileURL else { return }
        let workspaceRoot = WorkspaceManager.shared.activeWorkspace.roots.first
            ?? url.deletingLastPathComponent()
        guard let session = LSPDocumentSession(documentURL: url,
                                               workspaceRoot: workspaceRoot,
                                               sciView: sciView) else { return }
        session.start(initialText: source)
        lspSession = session
        // Enable hover-on-dwell — 500ms idle triggers SCN_DWELLSTART which
        // the notification dispatcher routes to hover lookup.
        SciSetMouseDwellTime(sciView, 500)
        // Phase 9: pull document symbols and broadcast to the outline panel.
        refreshDocumentSymbols()
    }

    private func refreshDocumentSymbols() {
        guard let session = lspSession,
              let doc = document, let url = doc.fileURL else { return }
        session.requestDocumentSymbols { symbols in
            NotificationCenter.default.post(
                name: .sourcepadOutlineDidUpdate,
                object: nil,
                userInfo: ["url": url, "symbols": symbols])
        }
    }

    private func lspSyncChange() {
        guard let session = lspSession else { return }
        session.didChange(text: SciGetText(sciView))
    }

    @objc public func sourcepadShowHover(_ sender: Any?) {
        guard let session = lspSession else { NSSound.beep(); return }
        let caret = currentCaretByte()
        session.requestHover(atCaretByte: caret) { [weak self] hover in
            guard let self else { return }
            if let hover = hover {
                LSPHoverPopover.shared.show(markdown: hover.markdown,
                                            anchoredTo: self.sciView,
                                            atCaretByte: caret)
            } else {
                NSSound.beep()
            }
        }
    }

    @objc public func sourcepadGoToDefinition(_ sender: Any?) {
        guard let session = lspSession else { NSSound.beep(); return }
        let caret = currentCaretByte()
        session.requestDefinition(atCaretByte: caret) { locations in
            guard let first = locations.first,
                  let path = LSP.path(forURI: first.uri) else {
                NSSound.beep(); return
            }
            let url = URL(fileURLWithPath: path)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, _ in
                guard let editor = (doc as? TextDocument)?.primaryEditorViewController() else { return }
                editor.editorPane?.goToLine(first.range.start.line + 1)
            }
        }
    }

    @objc public func sourcepadFindReferences(_ sender: Any?) {
        guard let session = lspSession else { NSSound.beep(); return }
        let caret = currentCaretByte()
        session.requestReferences(atCaretByte: caret) { locations in
            LSPReferencesWindowController.shared.show(locations: locations)
        }
    }

    @objc public func sourcepadRenameSymbol(_ sender: Any?) {
        guard let session = lspSession else { NSSound.beep(); return }
        let caret = currentCaretByte()
        let alert = NameAlert()
        alert.messageText = "Rename Symbol"
        alert.informativeText = "New name:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        field.bezelStyle = .roundedBezel
        alert.accessoryView = field
        alert.field = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        DispatchQueue.main.async { field.becomeFirstResponder() }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = alert.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        session.requestRename(atCaretByte: caret, newName: newName) { edit in
            LSPWorkspaceEditApplier.apply(edit)
        }
    }

    // MARK: - Tree-sitter wiring (Phase 5)

    private var treeSitterManager: TreeSitterManager?
    private let smartSelection = SmartSelection()

    private func setupTreeSitter(for lexer: String?, source: String) {
        guard let tsLang = TreeSitterLanguage.fromLexer(lexer),
              let mgr = TreeSitterManager(language: tsLang) else {
            treeSitterManager = nil
            return
        }
        treeSitterManager = mgr
        mgr.reparse(source: source)
    }

    /// Called by the .modified notification path. Cheap if Tree-sitter
    /// isn't active for this language.
    public func treeSitterReparseFullBuffer() {
        guard let mgr = treeSitterManager else { return }
        mgr.reparse(source: SciGetText(sciView))
        // Edits invalidate any in-flight smart-selection stack.
        smartSelection.reset()
    }

    public func currentCaretByte() -> Int {
        let sel = SciGetSelectionBytes(sciView)
        return sel.location == NSNotFound ? 0 : Int(sel.location)
    }

    // MARK: - Status-bar accessors

    public var currentCursorLine: Int     { SciGetCurrentLine(sciView) }
    public var currentCursorColumn: Int   { SciGetCurrentColumn(sciView) }
    public var currentLineCount: Int      { SciGetLineCount(sciView) }
    public var currentBufferByteCount: Int { SciTextLengthBytes(sciView) }
    public var currentSelectionByteCount: Int {
        let r = SciGetSelectionBytes(sciView)
        return r.location == NSNotFound ? 0 : Int(r.length)
    }

    /// Public wrapper used by external callers (e.g. Find in Files results).
    public func goToLine(_ line1Based: Int) {
        SciGoToLine(sciView, line1Based)
    }

    /// Replace the full buffer (used by EOL conversion in the status bar).
    /// Preserves caret position by clamping to new length.
    public func replaceWholeBuffer(with text: String) {
        let oldPos = currentCaretByte()
        SciSetText(sciView, text)
        let newLen = SciTextLengthBytes(sciView)
        let clamped = max(0, min(oldPos, newLen))
        SciSetSelectionBytes(sciView, clamped, clamped)
    }

    public var currentText: String { SciGetText(sciView) }

    public func markSavePoint() { SciSetSavePoint(sciView) }

    public func setLexer(_ name: String?) {
        currentLexer = name
        _ = SciApplyLexer(sciView, name)
        applyColorScheme()
    }

    public var activeLexer: String? { currentLexer }

    // MARK: - EditorContent conformance (Phase 4)

    /// The NSView our container installs as the document region.
    public var contentView: NSView { view }

    /// Caret + selection info for the status bar.
    public var caretInfo: EditorCaretInfo {
        EditorCaretInfo(
            line0Based: currentCursorLine,
            column0Based: currentCursorColumn,
            byteOffset: currentCaretByte(),
            lineCount: currentLineCount,
            bufferByteCount: currentBufferByteCount,
            selectionByteCount: currentSelectionByteCount)
    }

    /// Scintilla path always offers a preview opportunity; the preview
    /// pane decides whether to render based on filename / lexer.
    public var supportsPreview: Bool { true }

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
        // Apply non-token style colors (brace match, indent guides, whitespace).
        SciSetBraceStyles(sciView, scheme.braceLightFg, scheme.braceLightBg, scheme.braceBadFg)
        SciSetIndentGuideColor(sciView, scheme.indentGuideFg)
        SciSetWhitespaceColors(sciView, scheme.whitespaceFg, nil)
        if let lex = currentLexer {
            _ = SciApplyLexer(sciView, lex)
        }
        // Folding must be enabled BEFORE the CSSStyler post-pass — setting the
        // "fold" lexer property triggers a re-tokenize that erases any custom
        // SCI_STARTSTYLING / SCI_SETSTYLING styles. (Otherwise CSS-in-HTML
        // coloring would vanish whenever the theme changes.)
        let supports = EditorPaneViewController.lexerSupportsFolding(currentLexer)
        SciEnableFolding(sciView, supports,
                         scheme.lineNumberFg,
                         scheme.defaultBg)
        if let lex = currentLexer, lex == "hypertext" || lex == "xml" {
            // Lexilla's hypertext lexer doesn't sub-lex CSS — post-process to
            // color content inside <style> blocks. Must run AFTER folding setup.
            CSSStyler.applyToHTML(view: sciView, text: SciGetText(sciView))
        }
    }

    private static let foldableLexers: Set<String> = [
        "cpp", "rust", "python", "ruby", "lua", "bash", "hypertext", "xml",
        "css", "json", "yaml", "phpscript", "sql", "mssql", "makefile",
        "perl", "powershell", "batch", "pascal", "haskell", "lisp", "scheme",
        "fortran", "vhdl", "verilog", "tcl", "ada", "fsharp", "caml", "julia",
        "markdown", "nim", "nimrod", "go",
    ]

    static func lexerSupportsFolding(_ lexer: String?) -> Bool {
        guard let l = lexer else { return false }
        return foldableLexers.contains(l)
    }

    // MARK: - Scintilla notifications

    private func installNotificationHandler() {
        SciSetNotificationHandler(sciView) { [weak self] type, detail in
            guard let self else { return }
            switch type {
            case .savePointReached:
                self.document?.updateChangeCount(.changeCleared)
            case .savePointLeft:
                self.document?.updateChangeCount(.changeDone)
            case .modified:
                self.onTextChanged?()
                self.scheduleGitGutterRefresh()
                self.treeSitterReparseFullBuffer()
                self.lspSyncChange()
            case .updateUI:
                SciUpdateBraceMatch(self.sciView)
                if Preferences.shared.autocompleteEnabled {
                    AutoComplete.update(in: self.sciView, lexer: self.currentLexer)
                }
                NotificationCenter.default.post(name: .sourcepadEditorUIDidUpdate, object: self)
            case .charAdded:
                // AI ghost text trigger.
                if let cp = (detail?[SciDetailCodePoint] as? NSNumber)?.intValue,
                   let pos = (detail?[SciDetailPosition] as? NSNumber)?.intValue {
                    self.charAddedForAI(codePoint: cp, position: pos)
                }
            case .dwellStart:
                // LSP hover-on-dwell — only fires if a session is active.
                if let session = self.lspSession,
                   let pos = (detail?[SciDetailPosition] as? NSNumber)?.intValue {
                    session.requestHover(atCaretByte: pos) { [weak self] hover in
                        guard let self, let hover else { return }
                        LSPHoverPopover.shared.show(markdown: hover.markdown,
                                                    anchoredTo: self.sciView,
                                                    atCaretByte: pos)
                    }
                }
            case .dwellEnd:
                LSPHoverPopover.shared.dismiss()
            case .zoom,
                 .autoCSelection,
                 .indicatorClick, .indicatorRelease,
                 .marginClick,        // handled via SciSetMarginClickHandler
                 .focusIn, .focusOut:
                // Subscribers wire in later phases (AI ghost text,
                // signature help, etc.). Acknowledged here so the dispatcher
                // doesn't appear silent to future readers.
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: - View options (menu actions)

    @objc public func sourcepadToggleWordWrap(_ sender: Any?) {
        Preferences.shared.wordWrap.toggle()
    }

    @objc public func sourcepadToggleIndentGuides(_ sender: Any?) {
        Preferences.shared.indentGuides.toggle()
    }

    @objc public func sourcepadToggleShowInvisibles(_ sender: Any?) {
        let newValue = !Preferences.shared.showInvisibles
        Preferences.shared.showInvisibles = newValue
        // EOL markers paired with whitespace visibility for clarity.
        Preferences.shared.showEOL = newValue
    }

    @objc public func sourcepadZoomIn(_ sender: Any?) {
        Preferences.shared.zoomLevel = SciGetZoom(sciView) + 1
    }

    @objc public func sourcepadZoomOut(_ sender: Any?) {
        Preferences.shared.zoomLevel = SciGetZoom(sciView) - 1
    }

    @objc public func sourcepadZoomReset(_ sender: Any?) {
        Preferences.shared.zoomLevel = 0
    }

    // MARK: - Phase 3 actions

    @objc public func sourcepadAddNextOccurrence(_ sender: Any?) {
        if !SciAddNextOccurrenceToSelection(sciView) { NSSound.beep() }
    }

    // MARK: - Phase 5 smart selection (Tree-sitter)

    @objc public func sourcepadExpandSelection(_ sender: Any?) {
        guard let mgr = treeSitterManager else { NSSound.beep(); return }
        let sel = SciGetSelectionBytes(sciView)
        let start = sel.location == NSNotFound ? 0 : Int(sel.location)
        let end = start + sel.length
        guard let newRange = smartSelection.expand(currentStart: start,
                                                   currentEnd: end,
                                                   in: mgr) else {
            NSSound.beep()
            return
        }
        SciSetSelectionBytes(sciView, newRange.start, newRange.end)
    }

    @objc public func sourcepadShrinkSelection(_ sender: Any?) {
        guard let prior = smartSelection.shrink() else { NSSound.beep(); return }
        SciSetSelectionBytes(sciView, prior.start, prior.end)
    }

    @objc public func sourcepadGoToLine(_ sender: Any?) {
        guard let window = view.window else { return }
        let total = SciGetLineCount(sciView)
        GoToLinePanel.shared.show(in: window, totalLines: total) { [weak self] line in
            guard let self else { return }
            SciGoToLine(self.sciView, line)
        }
    }

    /// Called from the window-level event monitor when a paired character was
    /// typed in the editor. Returns true to consume the event.
    public func tryAutoPair(character: Character) -> Bool {
        return AutoPair.handle(typedChar: character,
                               in: sciView,
                               currentText: { SciGetText(self.sciView) })
    }

    // MARK: - Phase 4 actions (comment toggle, sort, case, bookmarks)

    @objc public func sourcepadToggleLineComment(_ sender: Any?) {
        let syntax = CommentSyntax.forLexer(currentLexer)
        if let prefix = syntax.linePrefix {
            toggleLineCommentLines(prefix: prefix)
        } else if let bo = syntax.blockOpen, let bc = syntax.blockClose {
            toggleBlockComment(open: bo, close: bc)
        } else {
            NSSound.beep()
        }
    }

    @objc public func sourcepadSortLinesAsc(_ sender: Any?)   { sortSelectedLines(ascending: true, unique: false, reverse: false) }
    @objc public func sourcepadSortLinesDesc(_ sender: Any?)  { sortSelectedLines(ascending: false, unique: false, reverse: false) }
    @objc public func sourcepadSortLinesUnique(_ sender: Any?) { sortSelectedLines(ascending: true, unique: true, reverse: false) }
    @objc public func sourcepadReverseLines(_ sender: Any?)   { sortSelectedLines(ascending: true, unique: false, reverse: true) }

    @objc public func sourcepadConvertCaseUpper(_ sender: Any?) { transformSelection { $0.uppercased() } }
    @objc public func sourcepadConvertCaseLower(_ sender: Any?) { transformSelection { $0.lowercased() } }
    @objc public func sourcepadConvertCaseTitle(_ sender: Any?) { transformSelection { $0.capitalized } }
    @objc public func sourcepadConvertCaseCamel(_ sender: Any?) { transformSelection { CaseConvert.camel($0) } }
    @objc public func sourcepadConvertCaseSnake(_ sender: Any?) { transformSelection { CaseConvert.snake($0) } }
    @objc public func sourcepadConvertCaseKebab(_ sender: Any?) { transformSelection { CaseConvert.kebab($0) } }

    @objc public func sourcepadToggleBookmark(_ sender: Any?) {
        let line = SciGetCurrentLine(sciView)
        Bookmarks.shared.toggle(line: line, in: sciView, url: document?.fileURL)
    }

    @objc public func sourcepadJumpNextBookmark(_ sender: Any?) {
        let current = SciGetCurrentLine(sciView)
        let next = SciMarkerNext(sciView, current + 1, BookmarkConstants.markerNumber)
        if next < 0 {
            let wrap = SciMarkerNext(sciView, 0, BookmarkConstants.markerNumber)
            if wrap < 0 { NSSound.beep(); return }
            SciGoToLine(sciView, wrap + 1)
        } else {
            SciGoToLine(sciView, next + 1)
        }
    }

    @objc public func sourcepadJumpPreviousBookmark(_ sender: Any?) {
        let current = SciGetCurrentLine(sciView)
        let prev = SciMarkerPrevious(sciView, max(0, current - 1), BookmarkConstants.markerNumber)
        if prev < 0 {
            let last = SciMarkerPrevious(sciView, SciGetLineCount(sciView) - 1, BookmarkConstants.markerNumber)
            if last < 0 { NSSound.beep(); return }
            SciGoToLine(sciView, last + 1)
        } else {
            SciGoToLine(sciView, prev + 1)
        }
    }

    @objc public func sourcepadClearBookmarks(_ sender: Any?) {
        Bookmarks.shared.clearAll(in: sciView, url: document?.fileURL)
    }

    // MARK: - Folding actions

    @objc public func sourcepadToggleFoldAtCursor(_ sender: Any?) {
        SciToggleFoldAtLine(sciView, SciGetCurrentLine(sciView))
    }

    @objc public func sourcepadFoldAll(_ sender: Any?)   { SciFoldAll(sciView) }
    @objc public func sourcepadUnfoldAll(_ sender: Any?) { SciUnfoldAll(sciView) }

    private func installMarginClickHandler() {
        SciSetMarginClickHandler(sciView) { [weak self] bytePos, margin in
            guard let self else { return }
            if margin == 2 {
                let line = SciLineFromByte(self.sciView, bytePos)
                SciToggleFoldAtLine(self.sciView, line)
            }
        }
    }

    private func scheduleGitGutterRefresh() {
        guard Preferences.shared.gitGutterEnabled else { return }
        gitDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.gitGutter.refresh(for: self.document?.fileURL, currentText: SciGetText(self.sciView))
        }
        gitDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Line-level edit helpers

    private func selectedLineRange() -> (firstLine: Int, lastLine: Int) {
        let sel = SciGetSelectionBytes(sciView)
        let startByte = Int(sel.location)
        let endByte   = startByte + Int(sel.length)
        let startLine = SciLineFromByte(sciView, startByte)
        var endLine   = SciLineFromByte(sciView, max(startByte, endByte))
        // If selection ends exactly at line start (zero-length on next line), trim back.
        if sel.length > 0 && SciLineStartByte(sciView, endLine) == endByte && endLine > startLine {
            endLine -= 1
        }
        return (startLine, endLine)
    }

    private func toggleLineCommentLines(prefix: String) {
        let (first, last) = selectedLineRange()
        // Are ALL non-blank lines already commented?
        var allCommented = true
        var anyNonBlank = false
        for line in first...last {
            let text = SciGetLineText(sciView, line)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            anyNonBlank = true
            if !trimmed.hasPrefix(prefix) { allCommented = false; break }
        }
        guard anyNonBlank else { NSSound.beep(); return }

        SciBeginUndoAction(sciView)
        for line in first...last {
            let lineText = SciGetLineText(sciView, line)
            let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let lineStart = SciLineStartByte(sciView, line)
            let lineEnd   = SciLineEndByte(sciView, line)
            if allCommented {
                // Remove the first occurrence of `prefix` (preserving following space if present).
                if let r = lineText.range(of: prefix) {
                    var stripCount = (prefix as NSString).lengthOfBytes(using: String.Encoding.utf8.rawValue)
                    let after = lineText.index(r.lowerBound, offsetBy: prefix.count, limitedBy: lineText.endIndex)
                    if let after, after < lineText.endIndex, lineText[after] == " " {
                        stripCount += 1
                    }
                    let leadingBytes = lineText[..<r.lowerBound].utf8.count
                    let pos = lineStart + leadingBytes
                    _ = SciReplaceBytesRange(sciView, pos, pos + stripCount, "")
                }
            } else {
                // Find first non-whitespace position and insert "prefix " there.
                if let nonWS = lineText.firstIndex(where: { !$0.isWhitespace }) {
                    let leadingBytes = lineText[..<nonWS].utf8.count
                    let insertAt = lineStart + leadingBytes
                    _ = SciReplaceBytesRange(sciView, insertAt, insertAt, prefix + " ")
                } else {
                    // Pure whitespace line — insert prefix at line start.
                    _ = SciReplaceBytesRange(sciView, lineStart, lineStart, prefix + " ")
                }
                _ = lineEnd  // unused
            }
        }
        SciEndUndoAction(sciView)
    }

    private func toggleBlockComment(open: String, close: String) {
        let sel = SciGetSelectionBytes(sciView)
        guard sel.length > 0 else { NSSound.beep(); return }
        let start = Int(sel.location)
        let end   = start + Int(sel.length)
        let inner = sliceBuffer(start: start, end: end)
        SciBeginUndoAction(sciView)
        if inner.hasPrefix(open) && inner.hasSuffix(close) {
            let stripped = String(inner.dropFirst(open.count).dropLast(close.count))
            _ = SciReplaceBytesRange(sciView, start, end, stripped)
        } else {
            _ = SciReplaceBytesRange(sciView, start, end, open + inner + close)
        }
        SciEndUndoAction(sciView)
    }

    private func sortSelectedLines(ascending: Bool, unique: Bool, reverse: Bool) {
        let (first, last) = selectedLineRange()
        guard last > first else { return }
        let startByte = SciLineStartByte(sciView, first)
        let endByte   = SciLineEndByte(sciView, last)
        let block = sliceBuffer(start: startByte, end: endByte)
        var lines = block.components(separatedBy: "\n")
        if reverse {
            lines.reverse()
        } else {
            lines.sort { ascending ? $0 < $1 : $0 > $1 }
        }
        if unique {
            var seen = Set<String>()
            lines = lines.filter { seen.insert($0).inserted }
        }
        let joined = lines.joined(separator: "\n")
        SciBeginUndoAction(sciView)
        _ = SciReplaceBytesRange(sciView, startByte, endByte, joined)
        SciEndUndoAction(sciView)
    }

    private func transformSelection(_ transform: (String) -> String) {
        let sel = SciGetSelectionBytes(sciView)
        let start: Int
        let end: Int
        if sel.length > 0 {
            start = Int(sel.location)
            end   = start + Int(sel.length)
        } else {
            // No selection — operate on the word under the caret.
            let caret = Int(sel.location)
            let full = SciGetText(sciView)
            let utf8 = Array(full.utf8)
            var wStart = caret
            while wStart > 0, let ch = scalarAt(utf8, wStart - 1), ch.isWordChar { wStart -= 1 }
            var wEnd = caret
            while wEnd < utf8.count, let ch = scalarAt(utf8, wEnd), ch.isWordChar { wEnd += 1 }
            if wStart == wEnd { NSSound.beep(); return }
            start = wStart; end = wEnd
        }
        let inner = sliceBuffer(start: start, end: end)
        let out = transform(inner)
        SciBeginUndoAction(sciView)
        let newEnd = SciReplaceBytesRange(sciView, start, end, out)
        SciSetSelectionBytes(sciView, start, newEnd)
        SciEndUndoAction(sciView)
    }

    private func sliceBuffer(start: Int, end: Int) -> String {
        let utf8 = Array(SciGetText(sciView).utf8)
        guard start <= end, end <= utf8.count else { return "" }
        return String(decoding: utf8[start..<end], as: UTF8.self)
    }

    private func scalarAt(_ utf8: [UInt8], _ idx: Int) -> Unicode.Scalar? {
        guard idx >= 0, idx < utf8.count else { return nil }
        return Unicode.Scalar(utf8[idx])
    }
}

private extension Unicode.Scalar {
    var isWordChar: Bool {
        // ASCII word definition — Phase 4 keeps it simple; non-ASCII identifiers
        // still work fine when used inside a selection.
        if value >= 0x30 && value <= 0x39 { return true }      // 0-9
        if value >= 0x41 && value <= 0x5A { return true }      // A-Z
        if value >= 0x61 && value <= 0x7A { return true }      // a-z
        if value == 0x5F { return true }                       // _
        return false
    }
}

public enum CaseConvert {
    /// Splits on non-word characters, lowercases first piece, capitalizes rest.
    public static func camel(_ s: String) -> String {
        let pieces = split(s)
        guard let first = pieces.first else { return "" }
        return first.lowercased() + pieces.dropFirst().map { $0.capitalized }.joined()
    }
    public static func snake(_ s: String) -> String { split(s).map { $0.lowercased() }.joined(separator: "_") }
    public static func kebab(_ s: String) -> String { split(s).map { $0.lowercased() }.joined(separator: "-") }

    private static func split(_ s: String) -> [String] {
        // Split on non-letters/digits AND on lowercase→uppercase transitions
        // (so "fooBar" → ["foo", "Bar"]).
        var pieces: [String] = []
        var current = ""
        var prev: Character = " "
        for c in s {
            let isWord = c.isLetter || c.isNumber
            let upperTransition = c.isUppercase && prev.isLowercase
            if !isWord || upperTransition {
                if !current.isEmpty { pieces.append(current); current = "" }
                if isWord { current.append(c) }
            } else {
                current.append(c)
            }
            prev = c
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}

public extension Notification.Name {
    /// Posted whenever Scintilla sends SCN_UPDATEUI (caret/selection/content
    /// changed). Status bar / outline pane / autocomplete observe this.
    static let sourcepadEditorUIDidUpdate = Notification.Name("SourcepadEditorUIDidUpdate")
}
