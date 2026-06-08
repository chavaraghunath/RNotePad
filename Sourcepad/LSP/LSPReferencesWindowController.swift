// SPDX-License-Identifier: MIT
// Sourcepad — window showing LSP textDocument/references results.
//
// Single shared instance (matches FindInFiles UX). Each row shows
// "<basename>:<line>" → click opens that file at the line.

import AppKit

public final class LSPReferencesWindowController: NSWindowController,
                                                   NSTableViewDataSource,
                                                   NSTableViewDelegate {

    public static let shared = LSPReferencesWindowController()

    private let table = NSTableView()
    private var locations: [LSP.Location] = []

    private init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
                           styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "References"
        super.init(window: win)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func buildUI() {
        guard let window else { return }
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        window.contentView?.addSubview(scroll)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ref"))
        col.title = "Location"
        col.width = 500
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked(_:))
        table.style = .plain
    }

    public func show(locations: [LSP.Location]) {
        self.locations = locations
        if let window {
            window.title = "References (\(locations.count))"
        }
        table.reloadData()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func rowDoubleClicked(_ sender: Any?) {
        let row = table.clickedRow
        guard row >= 0, row < locations.count else { return }
        let loc = locations[row]
        guard let path = LSP.path(forURI: loc.uri) else { return }
        let url = URL(fileURLWithPath: path)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, _ in
            guard let editor = (doc as? TextDocument)?.primaryEditorViewController() else { return }
            editor.editorPane?.goToLine(loc.range.start.line + 1)
        }
    }

    // MARK: - NSTableViewDataSource

    public func numberOfRows(in tableView: NSTableView) -> Int { locations.count }

    public func tableView(_ tableView: NSTableView,
                          objectValueFor tableColumn: NSTableColumn?,
                          row: Int) -> Any? {
        let loc = locations[row]
        let path = LSP.path(forURI: loc.uri) ?? loc.uri
        let base = (path as NSString).lastPathComponent
        return "\(base):\(loc.range.start.line + 1)"
    }
}
