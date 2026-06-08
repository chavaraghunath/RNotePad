// SPDX-License-Identifier: MIT
// Sourcepad — one window per text document. Hosts the editor split view and a
// unified toolbar with sidebar toggle, navigation arrows, a search field,
// and a preview toggle.

import AppKit

public final class EditorWindowController: NSWindowController,
                                           NSWindowDelegate,
                                           NSToolbarDelegate,
                                           NSSearchFieldDelegate {

    public let editorViewController: EditorViewController

    private weak var searchField: NSSearchField?
    private var localKeyMonitor: Any?

    public init(document: TextDocument) {
        let vc = EditorViewController(document: document)
        self.editorViewController = vc

        let bar = StatusBarView()
        bar.editorPane = vc.editorPane
        bar.document = document

        let root = RootContentViewController(editor: vc, statusBar: bar)

        let window = NSWindow(contentViewController: root)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1180, height: 720))
        window.title = "Sourcepad"
        window.tabbingMode = .preferred
        window.setFrameAutosaveName("SourcepadMainWindow")
        window.center()

        super.init(window: window)
        window.delegate = self
        window.registerForDraggedTypes([.fileURL])

        installToolbar(on: window)
        installAutoPairMonitor()
    }

    deinit {
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Auto-pair monitor

    private func installAutoPairMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Only act on events targeting our window.
            guard event.window === self.window else { return event }
            // Skip if the first responder is the toolbar search or any non-editor field.
            let editorPaneView = self.editorViewController.editorPane.view
            guard let responder = self.window?.firstResponder as? NSView else { return event }
            guard responder === editorPaneView || responder.isDescendant(of: editorPaneView) else {
                return event
            }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.shift, .capsLock]) == [] else { return event }
            guard let chars = event.characters, chars.count == 1,
                  let first = chars.first,
                  AutoPair.pairs[first] != nil || AutoPair.closers.contains(first)
            else { return event }
            if self.editorViewController.editorPane.tryAutoPair(character: first) {
                return nil  // consume — we did the insert via the bridge
            }
            return event
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    // MARK: - Toolbar identifiers

    private static let sidebarItemId = NSToolbarItem.Identifier("SourcepadSidebarToggle")
    private static let navItemId     = NSToolbarItem.Identifier("SourcepadNavigation")
    private static let searchItemId  = NSToolbarItem.Identifier("SourcepadSearch")
    private static let previewItemId = NSToolbarItem.Identifier("SourcepadPreviewToggle")

    private func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "SourcepadMain")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarItemId, .space, Self.navItemId, Self.searchItemId, .flexibleSpace, Self.previewItemId]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarItemId, Self.navItemId, Self.searchItemId, Self.previewItemId,
         .flexibleSpace, .space]
    }

    public func toolbar(_ toolbar: NSToolbar,
                        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.sidebarItemId:  return makeSidebarItem(id: itemIdentifier)
        case Self.navItemId:      return makeNavItem(id: itemIdentifier)
        case Self.searchItemId:   return makeSearchItem(id: itemIdentifier)
        case Self.previewItemId:  return makePreviewItem(id: itemIdentifier)
        default: return nil
        }
    }

    // MARK: - Toolbar items

    private func makeSidebarItem(id: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = "Sidebar"
        item.paletteLabel = "Sidebar"
        item.toolTip = "Show/Hide Sidebar (⌘0)"
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: "sidebar.leading",
                                 accessibilityDescription: "Toggle Sidebar")
        } else {
            item.image = NSImage(named: NSImage.touchBarSidebarTemplateName)
        }
        item.target = self
        item.action = #selector(toggleSidebarFromToolbar(_:))
        item.isBordered = true
        return item
    }

    private func makeNavItem(id: NSToolbarItem.Identifier) -> NSToolbarItem {
        // Disabled placeholders — document navigation history isn't wired yet
        // but the chevrons keep the toolbar visually consistent with the spec.
        let back = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("SourcepadNavBack"))
        back.image = NSImage(systemSymbolName: "chevron.left",
                             accessibilityDescription: "Back") ?? NSImage()
        back.isEnabled = false
        back.action = nil
        back.label = ""

        let forward = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("SourcepadNavForward"))
        forward.image = NSImage(systemSymbolName: "chevron.right",
                                accessibilityDescription: "Forward") ?? NSImage()
        forward.isEnabled = false
        forward.action = nil
        forward.label = ""

        let group = NSToolbarItemGroup(itemIdentifier: id)
        group.subitems = [back, forward]
        if #available(macOS 10.15, *) {
            group.controlRepresentation = .expanded
            group.selectionMode = .momentary
        }
        group.label = ""
        group.paletteLabel = "Navigation"
        return group
    }

    private func makeSearchItem(id: NSToolbarItem.Identifier) -> NSToolbarItem {
        if #available(macOS 11.0, *) {
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.preferredWidthForSearchField = 480
            item.resignsFirstResponderWithCancel = true
            let field = item.searchField
            field.placeholderString = "Search (⌘ E)"
            field.delegate = self
            field.target = self
            field.action = #selector(searchSubmitted(_:))
            field.sendsSearchStringImmediately = false
            field.sendsWholeSearchString = false
            self.searchField = field
            return item
        } else {
            // Pre-Big Sur fallback — bare NSSearchField in a custom toolbar item.
            let field = NSSearchField()
            field.placeholderString = "Search"
            field.delegate = self
            field.target = self
            field.action = #selector(searchSubmitted(_:))
            self.searchField = field
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = field
            item.minSize = NSSize(width: 200, height: 22)
            item.maxSize = NSSize(width: 800, height: 22)
            return item
        }
    }

    private func makePreviewItem(id: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = "Preview"
        item.paletteLabel = "Preview"
        item.toolTip = "Toggle Preview (⇧⌘P)"
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: "sidebar.right",
                                 accessibilityDescription: "Toggle Preview")
        } else {
            item.image = NSImage(named: NSImage.quickLookTemplateName)
        }
        item.target = self
        item.action = #selector(togglePreviewFromToolbar(_:))
        item.isBordered = true
        return item
    }

    // MARK: - Toolbar actions

    @objc private func toggleSidebarFromToolbar(_ sender: Any?) {
        editorViewController.toggleSidebar()
    }

    @objc private func togglePreviewFromToolbar(_ sender: Any?) {
        editorViewController.togglePreview()
        window?.toolbar?.validateVisibleItems()
    }

    @objc private func searchSubmitted(_ sender: NSSearchField) {
        // Enter in the search field → advance to next match.
        editorViewController.editorPane.quickFindAdvance(forward: true)
    }

    // MARK: - NSSearchFieldDelegate / NSControl

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === searchField else { return }
        editorViewController.editorPane.quickFind(field.stringValue)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === searchField {
            if selector == #selector(cancelOperation(_:)) {
                searchField?.stringValue = ""
                window?.makeFirstResponder(editorViewController.editorPane.view)
                return true
            }
        }
        return false
    }

    // MARK: - Focus toolbar search (Cmd-E / Cmd-F)

    @objc public func sourcepadFocusToolbarSearch(_ sender: Any?) {
        guard let field = searchField else { return }
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    // MARK: - NSWindow drag-and-drop (catches drops on title bar)

    public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ? .copy : []
    }

    public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil),
              let urls = items as? [URL], !urls.isEmpty else { return false }
        let dc = NSDocumentController.shared
        for url in urls {
            dc.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSLog("[Sourcepad] window-drag-open failed: \(url.path) — \(error)") }
            }
        }
        return true
    }
}

extension EditorWindowController: NSToolbarItemValidation {
    public func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.previewItemId: return editorViewController.canShowPreview
        case Self.sidebarItemId: return true
        default: return true
        }
    }
}
