// SPDX-License-Identifier: MIT
// Sourcepad — left-pane sidebar showing a file tree rooted at a folder.
// Double-clicking a file opens it via NSDocumentController; folders expand inline.

import AppKit

/// NSAlert subclass that surfaces its accessory text field for easy retrieval.
final class NameAlert: NSAlert {
    weak var field: NSTextField?
    var input: String { field?.stringValue ?? "" }
}

public final class SidebarViewController: NSViewController,
                                          NSOutlineViewDataSource,
                                          NSOutlineViewDelegate {

    /// Folder shown at the top of the tree. nil = "no folder picked".
    public private(set) var rootURL: URL?

    /// Called when the user activates (double-click or Enter) a file row.
    public var onOpen: ((URL) -> Void)?

    private let outline = NSOutlineView()
    private let scroll  = NSScrollView()
    private let header  = NSTextField(labelWithString: "No folder open")
    private let openFolderButton = NSButton(title: "Open Folder…", target: nil, action: nil)
    private let emptyState = NSStackView()

    // Cache of children per URL so the outline doesn't re-read the filesystem
    // on every isItemExpandable / numberOfChildren call.
    private var childrenCache: [URL: [URL]] = [:]

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Header strip: folder name + a refresh button.
        header.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.lineBreakMode = .byTruncatingMiddle
        header.translatesAutoresizingMaskIntoConstraints = false

        let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise",
                                              accessibilityDescription: "Refresh") ?? NSImage(),
                               target: self,
                               action: #selector(refreshTapped(_:)))
        refresh.isBordered = false
        refresh.controlSize = .small
        refresh.translatesAutoresizingMaskIntoConstraints = false
        refresh.toolTip = "Refresh"

        let headerStack = NSStackView(views: [header, NSView(), refresh])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 6)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(headerStack)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)

        // Outline view.
        outline.headerView = nil
        outline.rowSizeStyle = .small
        outline.indentationPerLevel = 14
        outline.indentationMarkerFollowsCell = true
        outline.usesAlternatingRowBackgroundColors = false
        outline.backgroundColor = .clear
        outline.style = .sourceList
        outline.target = self
        outline.action = #selector(rowClicked(_:))         // single-click: open file, toggle folder
        outline.doubleAction = #selector(rowClicked(_:))   // keep double-click working too
        outline.menu = makeContextMenu()

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.title = "Name"
        col.minWidth = 50
        col.width = 220
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.dataSource = self
        outline.delegate = self

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        // Empty state: button to open a folder.
        openFolderButton.target = self
        openFolderButton.action = #selector(openFolderTapped(_:))
        openFolderButton.bezelStyle = .rounded
        let emptyLabel = NSTextField(labelWithString: "No folder open.")
        emptyLabel.font = NSFont.systemFont(ofSize: 11)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyState.orientation = .vertical
        emptyState.spacing = 12
        emptyState.alignment = .centerX
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addArrangedSubview(emptyLabel)
        emptyState.addArrangedSubview(openFolderButton)
        root.addSubview(emptyState)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerStack.topAnchor.constraint(equalTo: root.topAnchor),
            headerStack.heightAnchor.constraint(equalToConstant: 30),

            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.topAnchor.constraint(equalTo: headerStack.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            emptyState.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])

        self.view = root
        updateEmptyState()
    }

    // MARK: - Public API

    public func setRoot(_ url: URL?) {
        rootURL = url
        childrenCache.removeAll()
        header.stringValue = url?.lastPathComponent ?? "No folder open"
        outline.reloadData()
        if let url { outline.expandItem(url) }
        updateEmptyState()
    }

    @objc public func refreshTapped(_ sender: Any?) {
        childrenCache.removeAll()
        outline.reloadData()
        if let rootURL { outline.expandItem(rootURL) }
    }

    @objc public func openFolderTapped(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        panel.beginSheetModal(for: view.window ?? NSApp.keyWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.setRoot(url)
        }
    }

    @objc private func rowClicked(_ sender: Any?) {
        // clickedRow is -1 when the action fires from keyboard nav or programmatic
        // selection — only act on actual mouse clicks so arrow-key navigation
        // doesn't open every file as you scroll past it.
        let row = outline.clickedRow
        guard row >= 0, let url = outline.item(atRow: row) as? URL else { return }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            if outline.isItemExpanded(url) { outline.collapseItem(url) }
            else                            { outline.expandItem(url) }
            return
        }
        onOpen?(url)
    }

    private func updateEmptyState() {
        let hasRoot = (rootURL != nil)
        scroll.isHidden = !hasRoot
        emptyState.isHidden = hasRoot
        header.isHidden = !hasRoot
    }

    // MARK: - Data source

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootURL != nil ? 1 : 0 }
        guard let url = item as? URL else { return 0 }
        return children(of: url).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootURL! }
        guard let url = item as? URL else { return URL(fileURLWithPath: "/") }
        return children(of: url)[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let url = item as? URL else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Delegate

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let url = item as? URL else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("FileRow")
        let cell: NSTableCellView
        if let recycled = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = recycled
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let iv = NSImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            let tf = NSTextField(labelWithString: "")
            tf.font = NSFont.systemFont(ofSize: 12)
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.imageView = iv
            cell.textField = tf
            cell.addSubview(iv)
            cell.addSubview(tf)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 16),
                iv.heightAnchor.constraint(equalToConstant: 16),
                tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = url.lastPathComponent
        cell.imageView?.image = NSWorkspace.shared.icon(forFile: url.path)
        return cell
    }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 20
    }

    // MARK: - Filesystem listing (cached)

    // MARK: - Context menu (right-click)

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = true
        for (title, sel) in [
            ("New File",      #selector(menuNewFile(_:))),
            ("New Folder",    #selector(menuNewFolder(_:))),
            ("Rename",        #selector(menuRename(_:))),
            ("Move to Trash", #selector(menuMoveToTrash(_:))),
            ("Reveal in Finder", #selector(menuReveal(_:))),
            ("Copy Path",     #selector(menuCopyPath(_:))),
        ] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            if title == "New Folder" || title == "Move to Trash" {
                menu.addItem(.separator())
            }
        }
        return menu
    }

    private func clickedURL() -> URL? {
        let row = outline.clickedRow
        guard row >= 0 else { return rootURL }
        return outline.item(atRow: row) as? URL
    }

    private func enclosingDir(for url: URL) -> URL {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue ? url : url.deletingLastPathComponent()
    }

    @objc private func menuNewFile(_ sender: Any?) {
        guard let target = clickedURL() else { return }
        let dir = enclosingDir(for: target)
        let alert = makePromptAlert(title: "New File", message: "Filename:")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = alert.input
        guard !name.isEmpty else { return }
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        refreshAfterMutation(parent: dir)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    @objc private func menuNewFolder(_ sender: Any?) {
        guard let target = clickedURL() else { return }
        let dir = enclosingDir(for: target)
        let alert = makePromptAlert(title: "New Folder", message: "Folder name:")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = alert.input
        guard !name.isEmpty else { return }
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: nil)
        refreshAfterMutation(parent: dir)
    }

    @objc private func menuRename(_ sender: Any?) {
        guard let url = clickedURL(), url != rootURL else { return }
        let alert = makePromptAlert(title: "Rename", message: "New name:", defaultValue: url.lastPathComponent)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = alert.input
        guard !name.isEmpty, name != url.lastPathComponent else { return }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            NSSound.beep()
            return
        }
        try? FileManager.default.moveItem(at: url, to: dest)
        refreshAfterMutation(parent: url.deletingLastPathComponent())
    }

    @objc private func menuMoveToTrash(_ sender: Any?) {
        guard let url = clickedURL(), url != rootURL else { return }
        NSWorkspace.shared.recycle([url]) { [weak self] _, _ in
            self?.refreshAfterMutation(parent: url.deletingLastPathComponent())
        }
    }

    @objc private func menuReveal(_ sender: Any?) {
        guard let url = clickedURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func menuCopyPath(_ sender: Any?) {
        guard let url = clickedURL() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    private func refreshAfterMutation(parent: URL) {
        childrenCache.removeValue(forKey: parent)
        DispatchQueue.main.async { [weak self] in
            self?.outline.reloadData()
            if let root = self?.rootURL { self?.outline.expandItem(root) }
        }
    }

    private func makePromptAlert(title: String, message: String, defaultValue: String = "") -> NameAlert {
        let alert = NameAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = defaultValue
        field.bezelStyle = .roundedBezel
        alert.accessoryView = field
        alert.field = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        DispatchQueue.main.async { field.becomeFirstResponder(); field.selectText(nil) }
        return alert
    }

    private func children(of url: URL) -> [URL] {
        if let cached = childrenCache[url] { return cached }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            childrenCache[url] = []
            return []
        }
        // Sort: directories first, then by name (case-insensitive).
        let sorted = entries.sorted { a, b in
            let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aIsDir != bIsDir { return aIsDir }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }
        childrenCache[url] = sorted
        return sorted
    }
}
