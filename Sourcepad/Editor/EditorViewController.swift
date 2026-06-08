// SPDX-License-Identifier: MIT
// Sourcepad — NSSplitViewController hosting (sidebar, editor, preview).
// Sidebar and preview start collapsed; both toggle via menu/toolbar.

import AppKit

public final class EditorViewController: NSSplitViewController {

    private static let sidebarVisibleKey = "Sourcepad.sidebarVisible"

    public weak var document: TextDocument?

    public let sidebarPane: SidebarViewController
    public let editorPane: EditorPaneViewController
    public let previewPane: PreviewPaneViewController

    private let sidebarItem: NSSplitViewItem
    private let editorItem: NSSplitViewItem
    private let previewItem: NSSplitViewItem

    private var pendingRender: DispatchWorkItem?

    public init(document: TextDocument) {
        self.document = document

        let sp = SidebarViewController()
        let ep = EditorPaneViewController(document: document)
        let pp = PreviewPaneViewController()
        self.sidebarPane = sp
        self.editorPane = ep
        self.previewPane = pp

        let si = NSSplitViewItem(sidebarWithViewController: sp)
        si.minimumThickness = 180
        si.maximumThickness = 480
        si.canCollapse = true
        si.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        si.holdingPriority = NSLayoutConstraint.Priority(270)
        self.sidebarItem = si

        let ei = NSSplitViewItem(viewController: ep)
        ei.minimumThickness = 320
        ei.holdingPriority = NSLayoutConstraint.Priority(250)
        self.editorItem = ei

        let pi = NSSplitViewItem(viewController: pp)
        pi.minimumThickness = 240
        pi.canCollapse = true
        pi.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        pi.holdingPriority = NSLayoutConstraint.Priority(260)
        self.previewItem = pi

        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        addSplitViewItem(si)
        addSplitViewItem(ei)
        addSplitViewItem(pi)

        // Sidebar visibility persists across launches; default = visible.
        let sidebarVisible = UserDefaults.standard.object(forKey: Self.sidebarVisibleKey) as? Bool ?? true
        si.isCollapsed = !sidebarVisible
        pi.isCollapsed = true

        // Sidebar opens files via NSDocumentController.
        sp.onOpen = { url in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSLog("[Sourcepad] sidebar open failed: \(url.path) — \(error)") }
            }
        }

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
        // Default sidebar root = enclosing folder of the document.
        if let url = document?.fileURL {
            sidebarPane.setRoot(url.deletingLastPathComponent())
        }
        // Auto-open the preview pane for images and SVGs.
        if let url = document?.fileURL,
           PreviewRenderer.kind(forFilename: url.lastPathComponent, fallbackLexer: nil) == .image
           || PreviewRenderer.kind(forFilename: url.lastPathComponent, fallbackLexer: nil) == .svg {
            previewItem.isCollapsed = false
            schedulePreviewRender(immediate: true)
        }
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
    public func currentCaretByte() -> Int { editorPane.currentCaretByte() }
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
        previewItem.animator().isCollapsed = !previewItem.isCollapsed
        if !previewItem.isCollapsed {
            schedulePreviewRender(immediate: true)
        }
        view.window?.toolbar?.validateVisibleItems()
    }

    // MARK: - Sidebar toggle

    public var isShowingSidebar: Bool { !sidebarItem.isCollapsed }

    public func toggleSidebar() {
        sidebarItem.animator().isCollapsed = !sidebarItem.isCollapsed
        UserDefaults.standard.set(!sidebarItem.isCollapsed, forKey: Self.sidebarVisibleKey)
        view.window?.toolbar?.validateVisibleItems()
    }

    public func setSidebarRoot(_ url: URL) {
        sidebarPane.setRoot(url)
        if sidebarItem.isCollapsed {
            sidebarItem.animator().isCollapsed = false
        }
        view.window?.toolbar?.validateVisibleItems()
    }

    // MARK: - Menu-action entry points (nil-target selectors)

    @objc public func sourcepadToggleSidebar(_ sender: Any?) {
        toggleSidebar()
    }

    @objc public func sourcepadOpenFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        panel.beginSheetModal(for: view.window ?? NSApp.keyWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.setSidebarRoot(url)
        }
    }

    // MARK: - Preview rendering

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
        previewPane.render(source: source, kind: kind, baseURL: baseURL, isDark: isDark,
                           fileURL: document?.fileURL)
    }
}
