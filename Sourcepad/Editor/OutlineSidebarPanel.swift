// SPDX-License-Identifier: MIT
// Sourcepad — sidebar "Outline" tab.
//
// Shows the document-symbol tree for the active editor. The active editor
// posts .sourcepadOutlineDidUpdate with its LSPDocumentSession.DocumentSymbol
// array whenever the document changes; this panel observes and rebuilds.

import AppKit

public extension Notification.Name {
    static let sourcepadOutlineDidUpdate = Notification.Name("SourcepadOutlineDidUpdate")
}

public final class OutlineSidebarPanel: NSView,
                                        NSOutlineViewDataSource,
                                        NSOutlineViewDelegate {

    public var onActivate: ((URL, Int) -> Void)?

    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private var symbols: [LSPDocumentSession.DocumentSymbol] = []
    private var documentURL: URL?

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
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        addSubview(scroll)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("symbol"))
        col.minWidth = 50
        col.width = 220
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.rowSizeStyle = .small
        outline.indentationPerLevel = 12
        outline.style = .sourceList
        outline.backgroundColor = .clear
        outline.target = self
        outline.doubleAction = #selector(rowDoubleClicked(_:))
        outline.dataSource = self
        outline.delegate = self

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(outlineDidUpdate(_:)),
            name: .sourcepadOutlineDidUpdate,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func outlineDidUpdate(_ note: Notification) {
        if let info = note.userInfo,
           let url = info["url"] as? URL,
           let syms = info["symbols"] as? [LSPDocumentSession.DocumentSymbol] {
            self.documentURL = url
            self.symbols = syms
            outline.reloadData()
            for s in symbols { outline.expandItem(SymbolBox(s)) }
        }
    }

    @objc private func rowDoubleClicked(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let box = outline.item(atRow: row) as? SymbolBox else { return }
        guard let url = documentURL else { return }
        onActivate?(url, box.symbol.line + 1)
    }

    // MARK: - NSOutlineViewDataSource

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return symbols.count }
        guard let box = item as? SymbolBox else { return 0 }
        return box.symbol.children.count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return SymbolBox(symbols[index]) }
        guard let box = item as? SymbolBox else { return SymbolBox(symbols[0]) }
        return SymbolBox(box.symbol.children[index])
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let box = item as? SymbolBox else { return false }
        return !box.symbol.children.isEmpty
    }

    public func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        guard let box = item as? SymbolBox else { return nil }
        let kind = box.symbol.kind ?? "?"
        return "\(box.symbol.name)    [\(kind)]"
    }
}

/// NSOutlineView requires items to be reference-type-compatible (Equatable
/// by identity). Wrap the value type in a class.
private final class SymbolBox: NSObject {
    let symbol: LSPDocumentSession.DocumentSymbol
    init(_ s: LSPDocumentSession.DocumentSymbol) { self.symbol = s }
}
