// SPDX-License-Identifier: MIT
// Sourcepad — Phase 14 JSON tree view.
//
// Parses JSON into a tree of nodes; renders via NSOutlineView. Each row
// shows "<key>: <value>" with the type as a faded suffix. Editing is
// out-of-scope for this phase — the view is read-only; saving the doc
// re-serializes the parsed tree (no edits = same bytes round-trip if
// the source was well-formatted).

import AppKit

public final class JSONTreeContent: NSViewController, EditorContent, NSOutlineViewDataSource, NSOutlineViewDelegate {

    private final class Node: NSObject {
        let key: String?
        var value: Any
        var children: [Node]
        init(key: String?, value: Any, children: [Node] = []) {
            self.key = key
            self.value = value
            self.children = children
        }
    }

    private var root: Node?
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private var storedText: String

    public init(initialText: String) {
        self.storedText = initialText
        super.init(nibName: nil, bundle: nil)
        parse()
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        v.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: v.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        col.title = "JSON"
        col.width = 560
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.style = .plain
        outline.dataSource = self
        outline.delegate = self
        outline.reloadData()
        if let root { outline.expandItem(root, expandChildren: true) }
        self.view = v
    }

    private func parse() {
        guard let data = storedText.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            root = nil
            return
        }
        root = JSONTreeContent.build(key: nil, value: obj)
    }

    private static func build(key: String?, value: Any) -> Node {
        if let dict = value as? [String: Any] {
            let kids = dict.keys.sorted().map { build(key: $0, value: dict[$0] as Any) }
            return Node(key: key, value: "{ … }", children: kids)
        }
        if let arr = value as? [Any] {
            let kids = arr.enumerated().map { (i, v) in build(key: "[\(i)]", value: v) }
            return Node(key: key, value: "[ … ]", children: kids)
        }
        return Node(key: key, value: value)
    }

    // MARK: - EditorContent

    public var contentView: NSView { view }
    public var currentText: String { storedText }
    public func replaceWholeBuffer(with text: String) {
        storedText = text
        parse()
        outline.reloadData()
        if let root { outline.expandItem(root, expandChildren: true) }
    }
    public var activeLexer: String? { nil }
    public func setLexer(_ name: String?) {}
    public var caretInfo: EditorCaretInfo {
        EditorCaretInfo(line0Based: 0, column0Based: 0, byteOffset: 0,
                        lineCount: storedText.split(separator: "\n").count,
                        bufferByteCount: storedText.lengthOfBytes(using: .utf8),
                        selectionByteCount: 0)
    }
    public var supportsPreview: Bool { false }
    public func documentContentsDidLoad() {}
    public func markSavePoint() {}
    public func currentCaretByte() -> Int { 0 }
    public var onTextChanged: (() -> Void)?

    // MARK: - NSOutlineViewDataSource / Delegate

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return root == nil ? 0 : 1 }
        guard let n = item as? Node else { return 0 }
        return n.children.count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return root! }
        guard let n = item as? Node else { return Node(key: "?", value: "?") }
        return n.children[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let n = item as? Node else { return false }
        return !n.children.isEmpty
    }

    public func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        guard let n = item as? Node else { return "" }
        let label = n.key.map { "\($0): " } ?? ""
        let v: String
        if n.value is NSNull { v = "null" }
        else if let b = n.value as? Bool { v = b ? "true" : "false" }
        else if let s = n.value as? String { v = "\"\(s)\"" }
        else { v = "\(n.value)" }
        return "\(label)\(v)"
    }
}
