// SPDX-License-Identifier: MIT
// Sourcepad — conversation history picker (popover).
//
// Lists persisted conversations newest-first; typing in the search field ranks
// them by semantic similarity (AgentEmbedder + AgentStore.semanticRank over the
// stored Float-BLOB vectors) instead of recency. Enter/double-click opens the
// selection; Delete removes it.

import AppKit

public final class AgentHistoryPopover: NSViewController,
                                        NSTableViewDataSource, NSTableViewDelegate,
                                        NSSearchFieldDelegate {

    public var onSelect: ((Int64) -> Void)?
    public var onDelete: ((Int64) -> Void)?

    private let search = NSSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var rows: [AgentStore.ConversationRow] = []
    private let store = AgentStore.shared

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 380))

        search.placeholderString = "Search conversations…"
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(search)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 44
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.style = .inset

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),

            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
        ])
        self.view = root
        reload(query: "")
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(search)
    }

    private func reload(query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            rows = store?.recentConversations(limit: 200) ?? []
        } else if let store {
            let ranked = store.semanticRank(query: AgentEmbedder.embed(q), limit: 50)
            let byID = Dictionary(uniqueKeysWithValues: store.recentConversations(limit: 500).map { ($0.id, $0) })
            // Keep semantic order, then fall back to substring matches not yet included.
            var seen = Set<Int64>()
            var out: [AgentStore.ConversationRow] = []
            for r in ranked where r.score > 0.01 {
                if let row = byID[r.id] { out.append(row); seen.insert(row.id) }
            }
            for row in byID.values where !seen.contains(row.id) && row.title.localizedCaseInsensitiveContains(q) {
                out.append(row)
            }
            rows = out
        }
        table.reloadData()
    }

    // MARK: - Search

    public func controlTextDidChange(_ obj: Notification) {
        reload(query: search.stringValue)
    }

    // MARK: - Table

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? HistoryCell) ?? HistoryCell(id: id)
        cell.configure(with: rows[row])
        return cell
    }

    @objc private func openSelected() {
        guard table.selectedRow >= 0, table.selectedRow < rows.count else { return }
        onSelect?(rows[table.selectedRow].id)
    }

    public func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard edge == .trailing else { return [] }
        let del = NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self] _, idx in
            guard let self, idx < self.rows.count else { return }
            let id = self.rows[idx].id
            self.store?.deleteConversation(id)
            self.onDelete?(id)
            self.reload(query: self.search.stringValue)
        }
        return [del]
    }
}

/// A two-line history row: title + "cli · model · when".
private final class HistoryCell: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    init(id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [titleLabel, subtitle])
        stack.orientation = .vertical
        stack.spacing = 1
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    func configure(with row: AgentStore.ConversationRow) {
        titleLabel.stringValue = row.title.isEmpty ? "Untitled" : row.title
        let bits = [row.currentCLI, row.currentModel].compactMap { $0 }.joined(separator: " · ")
        let date = Self.dateFmt.string(from: Date(timeIntervalSince1970: row.updatedAt))
        subtitle.stringValue = bits.isEmpty ? date : "\(bits) · \(date)"
    }
}
