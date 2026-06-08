// SPDX-License-Identifier: MIT
// RNotePad — view controller that hosts the Scintilla NSView and routes
// notifications back to NSDocument.

import AppKit

public final class EditorViewController: NSViewController {

    public weak var document: TextDocument?
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
        // Root container fills the window; Scintilla sits inside. We use a custom
        // NSView subclass so we can intercept viewDidChangeEffectiveAppearance,
        // which only exists on NSView (not NSViewController).
        let root = AppearanceForwardingView(frame: NSRect(x: 0, y: 0, width: 960, height: 640))
        root.autoresizingMask = [.width, .height]
        root.onAppearanceChange = { [weak self] in self?.applyColorScheme() }
        self.view = root

        let editor = SciMakeView(root.bounds)
        editor.autoresizingMask = [.width, .height]
        root.addSubview(editor)
        self.sciView = editor

        // Sits ABOVE the editor; only intercepts .fileURL drag types so plain
        // text drags still reach Scintilla.
        let dropOverlay = FileDropOverlay(frame: root.bounds)
        dropOverlay.autoresizingMask = [.width, .height]
        root.addSubview(dropOverlay)

        SciShowLineNumbers(editor, true)
        installNotificationHandler()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        documentContentsDidLoad()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(sciView)
    }

    /// Called by TextDocument once contents are available (either at open
    /// time, after viewDidLoad fires, or when read(from:ofType:) replaces
    /// the buffer e.g. via Revert).
    public func documentContentsDidLoad() {
        guard let doc = document else { return }
        SciSetText(sciView, doc.contents)

        // Pick lexer from filename.
        let filename = doc.fileURL?.lastPathComponent ?? "untitled.txt"
        let lexerName = LexerRegistry.lexer(for: filename)
        currentLexer = lexerName
        _ = SciApplyLexer(sciView, lexerName)

        applyColorScheme()
        SciSetSavePoint(sciView)
    }

    /// Pull current editor contents so NSDocument can write them.
    public var currentText: String {
        return SciGetText(sciView)
    }

    /// Tell Scintilla "this state is clean" — usually called after a successful save.
    public func markSavePoint() {
        SciSetSavePoint(sciView)
    }

    /// Force a specific Lexilla lexer (e.g. via View → Language menu). Pass
    /// `nil` to clear and revert to plain text.
    public func setLexer(_ name: String?) {
        currentLexer = name
        _ = SciApplyLexer(sciView, name)
        applyColorScheme()
    }

    /// Name of the currently-active lexer (or `nil` if plain text).
    public var activeLexer: String? { currentLexer }

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
        // Re-apply the lexer so its styles re-tokenise against the fresh palette.
        if let lex = currentLexer {
            _ = SciApplyLexer(sciView, lex)
        }
    }

    // MARK: - Scintilla notifications → NSDocument

    private func installNotificationHandler() {
        SciSetNotificationHandler(sciView) { [weak self] type in
            guard let self, let doc = self.document else { return }
            switch type {
            case .savePointReached:
                doc.updateChangeCount(.changeCleared)
            case .savePointLeft:
                doc.updateChangeCount(.changeDone)
            default:
                break
            }
        }
    }
}
