// SPDX-License-Identifier: MIT
// Rnotepad — NSSplitViewController hosting the editor pane and a
// collapsible preview pane. NSSplitViewItem handles show/hide layout
// correctly via `isCollapsed`.

import AppKit

public final class EditorViewController: NSSplitViewController {

    public weak var document: TextDocument?

    public let editorPane: EditorPaneViewController
    public let previewPane: PreviewPaneViewController

    private let editorItem: NSSplitViewItem
    private let previewItem: NSSplitViewItem

    private var pendingRender: DispatchWorkItem?

    public init(document: TextDocument) {
        self.document = document

        let ep = EditorPaneViewController(document: document)
        let pp = PreviewPaneViewController()
        self.editorPane = ep
        self.previewPane = pp

        let ei = NSSplitViewItem(viewController: ep)
        ei.minimumThickness = 320
        ei.holdingPriority = NSLayoutConstraint.Priority(250)
        self.editorItem = ei

        let pi = NSSplitViewItem(viewController: pp)
        pi.minimumThickness = 240
        pi.canCollapse = true
        pi.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        pi.holdingPriority = NSLayoutConstraint.Priority(260)
        self.previewItem = pi

        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        addSplitViewItem(ei)
        addSplitViewItem(pi)

        // Start collapsed.
        pi.isCollapsed = true

        // When the editor's text changes, debounce a preview re-render.
        ep.onTextChanged = { [weak self] in
            self?.schedulePreviewRender(immediate: false)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        editorPane.documentContentsDidLoad()
        invalidateRestorableState()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.toolbar?.validateVisibleItems()
    }

    // MARK: - Methods proxied to the editor pane (used by NSDocument flow)

    public func documentContentsDidLoad() {
        editorPane.documentContentsDidLoad()
        if !previewItem.isCollapsed { schedulePreviewRender(immediate: true) }
        view.window?.toolbar?.validateVisibleItems()
    }

    public var currentText: String { editorPane.currentText }
    public func markSavePoint() { editorPane.markSavePoint() }
    public func setLexer(_ name: String?) {
        editorPane.setLexer(name)
        if !previewItem.isCollapsed { schedulePreviewRender(immediate: true) }
    }
    public var activeLexer: String? { editorPane.activeLexer }

    // MARK: - Preview toggle

    public var canShowPreview: Bool {
        guard let doc = document else { return false }
        return PreviewRenderer.kind(
            forFilename: doc.fileURL?.lastPathComponent ?? "",
            fallbackLexer: editorPane.activeLexer
        ) != nil
    }

    public var isShowingPreview: Bool { !previewItem.isCollapsed }

    public func togglePreview() {
        guard canShowPreview else {
            NSSound.beep()
            return
        }
        // animator() drives a smooth show/hide; NSSplitViewItem handles layout.
        previewItem.animator().isCollapsed = !previewItem.isCollapsed
        if !previewItem.isCollapsed {
            schedulePreviewRender(immediate: true)
        }
        view.window?.toolbar?.validateVisibleItems()
    }

    private func schedulePreviewRender(immediate: Bool) {
        pendingRender?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.renderPreviewNow() }
        pendingRender = work
        let delay: DispatchTimeInterval = immediate ? .milliseconds(0) : .milliseconds(300)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func renderPreviewNow() {
        guard !previewItem.isCollapsed else { return }
        let filename = document?.fileURL?.lastPathComponent ?? ""
        guard let kind = PreviewRenderer.kind(forFilename: filename, fallbackLexer: editorPane.activeLexer) else { return }
        let source = editorPane.currentText
        let baseURL = document?.fileURL?.deletingLastPathComponent()
        let isDark = ThemeMode.from(view.effectiveAppearance) == .dark
        previewPane.render(source: source, kind: kind, baseURL: baseURL, isDark: isDark)
    }
}
