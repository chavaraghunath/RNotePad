// SPDX-License-Identifier: MIT
// RNotePad — view controller hosting the editor and an optional side-by-side
// preview pane. Layout is an NSSplitView; the preview pane is collapsed by
// default and toggled via the window toolbar.

import AppKit
import WebKit

public final class EditorViewController: NSViewController {

    public weak var document: TextDocument?

    private var splitView: NSSplitView!
    private var editorContainer: AppearanceForwardingView!
    private var previewContainer: NSView!
    private var sciView: NSView!
    private var webView: WKWebView!

    private var currentLexer: String?
    private var previewRenderKind: PreviewRenderer.Kind?
    private var isPreviewVisible = false
    private var pendingRenderWorkItem: DispatchWorkItem?

    public init(document: TextDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    // MARK: - View hierarchy

    public override func loadView() {
        let initialFrame = NSRect(x: 0, y: 0, width: 960, height: 640)

        // Left pane: existing editor (Scintilla + drop overlay) wrapped in our
        // appearance-forwarding container.
        editorContainer = AppearanceForwardingView(frame: initialFrame)
        editorContainer.onAppearanceChange = { [weak self] in self?.applyColorScheme() }

        let editor = SciMakeView(editorContainer.bounds)
        editor.autoresizingMask = [.width, .height]
        editorContainer.addSubview(editor)
        self.sciView = editor

        let dropOverlay = FileDropOverlay(frame: editorContainer.bounds)
        dropOverlay.autoresizingMask = [.width, .height]
        editorContainer.addSubview(dropOverlay)

        SciShowLineNumbers(editor, true)
        installNotificationHandler()

        // Right pane: WKWebView preview, created lazily but the container holds
        // its place in the split so we can show/hide it instantly.
        previewContainer = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: initialFrame.height))

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: previewContainer.bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        previewContainer.addSubview(wv)
        self.webView = wv

        // Split view — vertical divider, editor on left, preview on right.
        splitView = NSSplitView(frame: initialFrame)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        splitView.addArrangedSubview(editorContainer)
        splitView.addArrangedSubview(previewContainer)

        // Preview starts hidden.
        splitView.setPosition(initialFrame.width, ofDividerAt: 0)
        previewContainer.isHidden = true

        self.view = splitView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        documentContentsDidLoad()
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

        previewRenderKind = PreviewRenderer.kind(forFilename: filename, fallbackLexer: lexerName)
        if isPreviewVisible { schedulePreviewRender(immediate: true) }
        // Sync the toolbar button's enabled state.
        invalidateRestorableState()
        view.window?.toolbar?.validateVisibleItems()
    }

    public var currentText: String {
        return SciGetText(sciView)
    }

    public func markSavePoint() {
        SciSetSavePoint(sciView)
    }

    public func setLexer(_ name: String?) {
        currentLexer = name
        _ = SciApplyLexer(sciView, name)
        applyColorScheme()
        previewRenderKind = PreviewRenderer.kind(
            forFilename: document?.fileURL?.lastPathComponent ?? "",
            fallbackLexer: name
        )
        if isPreviewVisible { schedulePreviewRender(immediate: true) }
    }

    public var activeLexer: String? { currentLexer }

    // MARK: - Preview toggle

    public var canShowPreview: Bool {
        guard let doc = document else { return false }
        return PreviewRenderer.kind(
            forFilename: doc.fileURL?.lastPathComponent ?? "",
            fallbackLexer: currentLexer
        ) != nil
    }

    public var isShowingPreview: Bool { isPreviewVisible }

    public func togglePreview() {
        guard canShowPreview else {
            NSSound.beep()
            return
        }
        isPreviewVisible.toggle()
        if isPreviewVisible {
            previewContainer.isHidden = false
            let total = splitView.bounds.width
            splitView.setPosition(total / 2, ofDividerAt: 0)
            schedulePreviewRender(immediate: true)
        } else {
            previewContainer.isHidden = true
            splitView.setPosition(splitView.bounds.width, ofDividerAt: 0)
        }
        view.window?.toolbar?.validateVisibleItems()
    }

    private func schedulePreviewRender(immediate: Bool) {
        pendingRenderWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.renderPreviewNow() }
        pendingRenderWorkItem = work
        let delay: DispatchTimeInterval = immediate ? .milliseconds(0) : .milliseconds(300)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func renderPreviewNow() {
        guard isPreviewVisible, let kind = previewRenderKind else { return }
        let source = currentText
        let baseURL = document?.fileURL?.deletingLastPathComponent()
        let isDark = ThemeMode.from(view.effectiveAppearance) == .dark
        PreviewRenderer.render(source: source, kind: kind, baseURL: baseURL, isDark: isDark, into: webView)
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
        if let lex = currentLexer { _ = SciApplyLexer(sciView, lex) }
        if isPreviewVisible { schedulePreviewRender(immediate: true) }
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
                if self.isPreviewVisible { self.schedulePreviewRender(immediate: false) }
            default:
                break
            }
        }
    }
}
