// SPDX-License-Identifier: MIT
// Sourcepad — sidebar "Tasks" tab.
//
// Lists every TODO / FIXME / HACK / XXX from TodoAggregator. Rescan
// fires when the panel becomes visible. Click a row → open the file at
// that line.

import AppKit

public final class TasksSidebarPanel: NSView, NSTableViewDataSource, NSTableViewDelegate {

    public var onActivate: ((URL, Int) -> Void)?

    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var entries: [TodoEntry] = []

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        addSubview(scroll)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task"))
        col.minWidth = 50
        col.width = 220
        table.addTableColumn(col)
        table.headerView = nil
        table.rowSizeStyle = .small
        table.backgroundColor = .clear
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked(_:))

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    public func refresh() {
        TodoAggregator.shared.rescan { [weak self] entries in
            self?.entries = entries
            self?.table.reloadData()
        }
    }

    @objc private func rowDoubleClicked(_ sender: Any?) {
        let row = table.clickedRow
        guard row >= 0, row < entries.count else { return }
        let e = entries[row]
        onActivate?(URL(fileURLWithPath: e.absolutePath), e.line)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    public func tableView(_ tableView: NSTableView,
                          objectValueFor tableColumn: NSTableColumn?,
                          row: Int) -> Any? {
        let e = entries[row]
        let base = (e.absolutePath as NSString).lastPathComponent
        return "[\(e.kind)] \(e.text) — \(base):\(e.line)"
    }
}
