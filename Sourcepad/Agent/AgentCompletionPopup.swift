// SPDX-License-Identifier: MIT
// Sourcepad — inline `@`/`/` completion dropdown for the agent input.
//
// Unlike the centered ⌘P PaletteWindowController (which takes focus into its
// own search field), this is a borderless, NON-activating child window anchored
// at the input's caret. The input text view keeps first responder and drives
// the popup directly (move/accept/dismiss), which is the standard autocomplete
// pattern: you keep typing and the list filters under the caret.
//
// Rows reuse the shared PaletteCell so they look identical to the palette.

import AppKit

public final class AgentCompletionPopup: NSWindowController,
                                          NSTableViewDataSource,
                                          NSTableViewDelegate {

    /// Fires when the user accepts a row (Enter / Tab / click).
    public var onChoose: ((PaletteItem) -> Void)?

    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var items: [PaletteItem] = []
    private var selectedRow = 0

    private static let rowHeight: CGFloat = 36
    private static let maxVisibleRows = 8
    private static let width: CGFloat = 340

    public var isVisible: Bool { window?.isVisible ?? false }
    public var selectedItem: PaletteItem? {
        (selectedRow >= 0 && selectedRow < items.count) ? items[selectedRow] : nil
    }

    public init() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                             styleMask: [.borderless],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        super.init(window: panel)
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func buildLayout() {
        guard let window else { return }
        let content = NSVisualEffectView()
        content.material = .menu
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 8
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor.separatorColor.cgColor
        window.contentView = content

        table.headerView = nil
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.allowsEmptySelection = false
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked(_:))
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AgentCompletionCol"))
        col.width = Self.width - 12
        table.addTableColumn(col)
        table.style = .plain

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    // MARK: - Presentation

    /// Show or update the popup with `items`, anchored under `caretRectScreen`
    /// (in screen coordinates) and parented to `host`'s window. Hides when empty.
    public func present(items: [PaletteItem], caretRectScreen: NSRect, host: NSView) {
        guard !items.isEmpty else { hide(); return }
        self.items = items
        self.selectedRow = 0
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.scrollRowToVisible(0)

        guard let window, let hostWindow = host.window else { return }

        let rows = min(items.count, Self.maxVisibleRows)
        let height = CGFloat(rows) * (Self.rowHeight + 2) + 8
        window.setContentSize(NSSize(width: Self.width, height: height))

        // Prefer below the caret; flip above if it would clip the screen bottom.
        let screen = hostWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var origin = NSPoint(x: caretRectScreen.minX,
                             y: caretRectScreen.minY - height - 4)
        if origin.y < visible.minY {
            origin.y = caretRectScreen.maxY + 4
        }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - Self.width - 4)
        window.setFrameOrigin(origin)

        if window.parent == nil {
            hostWindow.addChildWindow(window, ordered: .above)
        }
        window.orderFront(nil)
    }

    public func hide() {
        guard let window else { return }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        items = []
        selectedRow = 0
    }

    // MARK: - Keyboard (driven by the input view)

    /// Move selection; positive = down. Returns true if it handled the move.
    @discardableResult
    public func move(by delta: Int) -> Bool {
        guard isVisible, !items.isEmpty else { return false }
        let newRow = max(0, min(items.count - 1, selectedRow + delta))
        if newRow != selectedRow {
            selectedRow = newRow
            table.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
            table.scrollRowToVisible(newRow)
        }
        return true
    }

    /// Accept the highlighted row. Returns true if it consumed the key.
    @discardableResult
    public func acceptSelected() -> Bool {
        guard isVisible, let item = selectedItem else { return false }
        hide()
        onChoose?(item)
        return true
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = table.clickedRow
        guard row >= 0, row < items.count else { return }
        selectedRow = row
        acceptSelected()
    }

    // MARK: - Table data

    public func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    public func tableView(_ tableView: NSTableView,
                          viewFor tableColumn: NSTableColumn?,
                          row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let id = NSUserInterfaceItemIdentifier("AgentCompletionCell")
        let cell: PaletteCell
        if let recycled = tableView.makeView(withIdentifier: id, owner: self) as? PaletteCell {
            cell = recycled
        } else {
            cell = PaletteCell()
            cell.identifier = id
        }
        cell.configure(with: items[row])
        return cell
    }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.rowHeight
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        if table.selectedRow >= 0 { selectedRow = table.selectedRow }
    }
}
