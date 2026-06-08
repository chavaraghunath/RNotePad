// SPDX-License-Identifier: MIT
// RNotePad — one window per text document. Hosts the editor split view and
// a toolbar with a preview-toggle button on the trailing side.

import AppKit

public final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {

    public let editorViewController: EditorViewController

    public init(document: TextDocument) {
        let vc = EditorViewController(document: document)
        self.editorViewController = vc

        let window = NSWindow(contentViewController: vc)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1080, height: 700))
        window.title = "RNotePad"
        window.tabbingMode = .preferred
        window.setFrameAutosaveName("RNotePadMainWindow")
        window.center()

        super.init(window: window)
        window.delegate = self
        window.registerForDraggedTypes([.fileURL])

        installToolbar(on: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    // MARK: - Toolbar

    private static let previewItemId = NSToolbarItem.Identifier("RNotePadPreviewToggle")

    private func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "RNotePadMain")
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
        [.flexibleSpace, Self.previewItemId]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.previewItemId]
    }

    public func toolbar(_ toolbar: NSToolbar,
                        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.previewItemId else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Preview"
        item.paletteLabel = "Preview"
        item.toolTip = "Toggle preview (Shift-Cmd-P)"
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: "sidebar.right",
                                 accessibilityDescription: "Toggle preview")
        } else {
            item.image = NSImage(named: NSImage.quickLookTemplateName)
        }
        item.target = self
        item.action = #selector(togglePreviewFromToolbar(_:))
        item.isBordered = true
        return item
    }

    @objc private func togglePreviewFromToolbar(_ sender: Any?) {
        editorViewController.togglePreview()
        window?.toolbar?.validateVisibleItems()
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
                if let error { NSLog("[RNotePad] window-drag-open failed: \(url.path) — \(error)") }
            }
        }
        return true
    }
}

// Validate the toolbar button so it dims when the doc isn't previewable.
extension EditorWindowController: NSToolbarItemValidation {
    public func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard item.itemIdentifier == Self.previewItemId else { return true }
        return editorViewController.canShowPreview
    }
}
