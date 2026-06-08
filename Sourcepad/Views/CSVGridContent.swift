// SPDX-License-Identifier: MIT
// Sourcepad — Phase 14 CSV grid view.
//
// Opens .csv (or any text the user opted into "Open As → Grid") as an
// editable NSTableView. Parses RFC 4180 with header-row auto-detect.
// Serialises back to CSV on save (round-trips through `currentText`).

import AppKit

public final class CSVGridContent: NSViewController, EditorContent, NSTableViewDataSource, NSTableViewDelegate {

    private var rows: [[String]] = []
    private var headers: [String] = []
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var storedText: String

    public init(initialText: String) {
        self.storedText = initialText
        super.init(nibName: nil, bundle: nil)
        parseCSV()
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        table.style = .plain
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        rebuildColumns()
        self.view = root
    }

    private func rebuildColumns() {
        for col in table.tableColumns { table.removeTableColumn(col) }
        for (i, h) in headers.enumerated() {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(i)"))
            col.title = h
            col.minWidth = 60
            col.width = 120
            col.isEditable = true
            table.addTableColumn(col)
        }
        table.reloadData()
    }

    // MARK: - EditorContent

    public var contentView: NSView { view }
    public var currentText: String {
        // Re-serialise rows + headers as RFC 4180 CSV.
        let allRows = [headers] + rows
        return allRows.map { CSVGridContent.encodeRow($0) }.joined(separator: "\n")
    }
    public func replaceWholeBuffer(with text: String) {
        storedText = text
        parseCSV()
        rebuildColumns()
    }
    public var activeLexer: String? { nil }
    public func setLexer(_ name: String?) {}
    public var caretInfo: EditorCaretInfo {
        EditorCaretInfo(line0Based: max(0, table.selectedRow),
                        column0Based: 0, byteOffset: 0,
                        lineCount: rows.count + 1,
                        bufferByteCount: currentText.lengthOfBytes(using: .utf8),
                        selectionByteCount: 0)
    }
    public var supportsPreview: Bool { false }
    public func documentContentsDidLoad() {}
    public func markSavePoint() {}
    public func currentCaretByte() -> Int { 0 }
    public var onTextChanged: (() -> Void)?

    // MARK: - NSTableViewDataSource / Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView,
                          objectValueFor tableColumn: NSTableColumn?,
                          row: Int) -> Any? {
        guard let col = tableColumn,
              let idx = Int(col.identifier.rawValue.dropFirst("col".count)),
              row < rows.count, idx < rows[row].count else { return "" }
        return rows[row][idx]
    }

    public func tableView(_ tableView: NSTableView,
                          setObjectValue object: Any?,
                          for tableColumn: NSTableColumn?,
                          row: Int) {
        guard let col = tableColumn,
              let idx = Int(col.identifier.rawValue.dropFirst("col".count)),
              row < rows.count else { return }
        // Grow row if column index is past current width.
        while rows[row].count <= idx { rows[row].append("") }
        rows[row][idx] = (object as? String) ?? ""
        onTextChanged?()
    }

    // MARK: - CSV parsing + encoding

    private func parseCSV() {
        let parsed = CSVGridContent.parse(storedText)
        if parsed.isEmpty {
            headers = []
            rows = []
        } else {
            headers = parsed[0]
            rows = Array(parsed.dropFirst())
        }
    }

    /// RFC-4180-ish parse. Handles quoted fields with embedded newlines
    /// and escaped quotes (`""`).
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    current.append(field); field = ""
                } else if c == "\n" || c == "\r" {
                    current.append(field); field = ""
                    rows.append(current); current = []
                    if c == "\r" {
                        let next = text.index(after: i)
                        if next < text.endIndex, text[next] == "\n" {
                            i = text.index(after: next); continue
                        }
                    }
                } else {
                    field.append(c)
                }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }
        return rows
    }

    static func encodeRow(_ row: [String]) -> String {
        return row.map { field -> String in
            if field.contains(",") || field.contains("\n") || field.contains("\"") {
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return field
        }.joined(separator: ",")
    }
}
