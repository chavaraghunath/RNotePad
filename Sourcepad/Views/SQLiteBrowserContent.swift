// SPDX-License-Identifier: MIT
// Sourcepad — Phase 15 SQLite browser.
//
// Read-only browser: lists tables in a sidebar; selecting a table runs
// "SELECT * FROM <name> LIMIT 1000" and shows rows in NSTableView.
// Edit mode is a follow-on (requires confirmation sheet + schema-aware
// editing). Connects via the system libsqlite3 (already linked via the
// ProjectIndex code path).

import AppKit
import SQLite3

public final class SQLiteBrowserContent: NSViewController, EditorContent,
                                          NSTableViewDataSource, NSTableViewDelegate {

    private let tablesList = NSTableView()
    private let rowsTable = NSTableView()
    private let split = NSSplitView()
    private var db: OpaquePointer?
    private var tableNames: [String] = []
    private var currentRows: [[Any]] = []
    private var currentColumns: [String] = []

    public init(fileURL: URL) {
        super.init(nibName: nil, bundle: nil)
        var handle: OpaquePointer?
        if sqlite3_open_v2(fileURL.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            self.db = handle
            loadTableList()
        }
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    deinit { if let db { sqlite3_close(db) } }

    public override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 440))
        split.translatesAutoresizingMaskIntoConstraints = false
        split.dividerStyle = .thin
        split.isVertical = true
        v.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            split.topAnchor.constraint(equalTo: v.topAnchor),
            split.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])

        let lhsScroll = NSScrollView()
        lhsScroll.documentView = tablesList
        lhsScroll.hasVerticalScroller = true
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.title = "Tables"; col.width = 160
        tablesList.addTableColumn(col)
        tablesList.headerView = nil
        tablesList.dataSource = self
        tablesList.delegate = self
        tablesList.target = self
        tablesList.action = #selector(tablePicked(_:))
        tablesList.style = .sourceList

        let rhsScroll = NSScrollView()
        rhsScroll.documentView = rowsTable
        rhsScroll.hasVerticalScroller = true
        rhsScroll.hasHorizontalScroller = true
        rowsTable.dataSource = self
        rowsTable.delegate = self
        rowsTable.style = .plain

        split.addArrangedSubview(lhsScroll)
        split.addArrangedSubview(rhsScroll)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow,  forSubviewAt: 1)
        self.view = v
    }

    private func loadTableList() {
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    tableNames.append(String(cString: c))
                }
            }
        }
        sqlite3_finalize(stmt)
    }

    @objc private func tablePicked(_ sender: Any?) {
        let row = tablesList.clickedRow
        guard row >= 0, row < tableNames.count else { return }
        loadRows(of: tableNames[row])
    }

    private func loadRows(of name: String) {
        guard let db else { return }
        currentRows.removeAll()
        currentColumns.removeAll()
        for col in rowsTable.tableColumns { rowsTable.removeTableColumn(col) }
        var stmt: OpaquePointer?
        // SAFE-ish: name comes from sqlite_master, not user input.
        let sql = "SELECT * FROM \"\(name.replacingOccurrences(of: "\"", with: "\"\""))\" LIMIT 1000"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let n = Int(sqlite3_column_count(stmt))
        for i in 0..<n {
            let colName = sqlite3_column_name(stmt, Int32(i)).map { String(cString: $0) } ?? "col\(i)"
            currentColumns.append(colName)
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(i)"))
            c.title = colName; c.width = 140
            rowsTable.addTableColumn(c)
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [Any] = []
            for i in 0..<n {
                let type = sqlite3_column_type(stmt, Int32(i))
                switch type {
                case SQLITE_INTEGER: row.append(sqlite3_column_int64(stmt, Int32(i)))
                case SQLITE_FLOAT:   row.append(sqlite3_column_double(stmt, Int32(i)))
                case SQLITE_TEXT:
                    if let p = sqlite3_column_text(stmt, Int32(i)) {
                        row.append(String(cString: p))
                    } else { row.append("") }
                case SQLITE_NULL: row.append(NSNull())
                default:          row.append("<blob>")
                }
            }
            currentRows.append(row)
        }
        rowsTable.reloadData()
    }

    // MARK: - EditorContent

    public var contentView: NSView { view }
    public var currentText: String { "" }
    public func replaceWholeBuffer(with text: String) { _ = text }
    public var activeLexer: String? { nil }
    public func setLexer(_ name: String?) {}
    public var caretInfo: EditorCaretInfo {
        EditorCaretInfo(line0Based: 0, column0Based: 0, byteOffset: 0,
                        lineCount: currentRows.count, bufferByteCount: 0,
                        selectionByteCount: 0)
    }
    public var supportsPreview: Bool { false }
    public func documentContentsDidLoad() {}
    public func markSavePoint() {}
    public func currentCaretByte() -> Int { 0 }
    public var onTextChanged: (() -> Void)?

    // MARK: - NSTableViewDataSource

    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === tablesList { return tableNames.count }
        return currentRows.count
    }

    public func tableView(_ tableView: NSTableView,
                          objectValueFor tableColumn: NSTableColumn?,
                          row: Int) -> Any? {
        if tableView === tablesList { return tableNames[row] }
        guard let col = tableColumn,
              let idx = Int(col.identifier.rawValue.dropFirst("c".count)),
              row < currentRows.count else { return "" }
        let v = currentRows[row][idx]
        if v is NSNull { return "" }
        return "\(v)"
    }
}
