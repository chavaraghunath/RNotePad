// SPDX-License-Identifier: MIT
// Sourcepad — left pane of the editor split. Hosts the Scintilla NSView, the
// file-drop overlay, and the appearance-change forwarder.

import AppKit

public final class EditorPaneViewController: NSViewController {

    public weak var document: TextDocument?
    public var onTextChanged: (() -> Void)?

    private var sciView: NSView!
    private var currentLexer: String?

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
        root.autoresizingMask = [.width, .height]

        let editor = SciMakeView(root.bounds)
        editor.autoresizingMask = [.width, .height]
        root.addSubview(editor)
        self.sciView = editor

        let dropOverlay = FileDropOverlay(frame: root.bounds)
        dropOverlay.autoresizingMask = [.width, .height]
        root.addSubview(dropOverlay)

        SciShowLineNumbers(editor, true)
        installNotificationHandler()
        self.view = root
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

    // MARK: - Light/dark hot-swap

    private func applyColorScheme() {
        let mode = ThemeMode.from(view.effectiveAppearance)
        let scheme = SchemeLibrary.scheme(for: currentLexer, mode: mode)
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
