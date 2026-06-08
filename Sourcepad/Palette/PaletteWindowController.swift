// SPDX-License-Identifier: MIT
// Sourcepad — palette window (⌘P / ⌘⇧P / ⌘T).
//
// A borderless floating NSPanel. One instance is shared across all three
// palette types; calling `present(provider:)` swaps in the right provider.
//
// Design notes:
//   - Panel becomes key but not main, so background editor windows stay
//     visually active (the palette feels like an overlay, not a window swap).
//   - The text field handles arrow keys / Enter / Escape via field editor
//     hooks; the table is informational only.
//   - All results computation runs synchronously on the main thread because
//     PaletteFuzzy is fast enough; if a future provider needs async work it
//     can return [] and refresh via the public reload() entry point.

import AppKit

public final class PaletteWindowController: NSWindowController,
                                            NSTextFieldDelegate,
                                            NSTableViewDataSource,
                                            NSTableViewDelegate {

    public static let shared = PaletteWindowController()

    private var provider: PaletteProvider?
    private var items: [PaletteItem] = []
    private var selectedRow: Int = 0

    private let field = NSTextField()
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private let titleLabel = NSTextField(labelWithString: "")

    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                            styleMask: [.titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: panel)

        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func buildLayout() {
        guard let window else { return }
        let content = NSView()
        content.wantsLayer = true
        window.contentView = content

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        field.font = NSFont.systemFont(ofSize: 16)
        field.placeholderString = ""
        field.delegate = self
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(field)

        table.headerView = nil
        table.rowSizeStyle = .small
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.allowsEmptySelection = false
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked(_:))
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PaletteCol"))
        col.width = 600
        table.addTableColumn(col)
        table.style = .plain

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            titleLabel.heightAnchor.constraint(equalToConstant: 16),

            field.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            field.heightAnchor.constraint(equalToConstant: 28),

            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Presentation

    /// Show the palette using the given provider. Any prior provider is
    /// discarded (the palette is single-instance).
    public func present(provider: PaletteProvider) {
        self.provider = provider
        self.items = []
        self.selectedRow = 0

        titleLabel.stringValue = provider.displayName
        field.placeholderString = provider.placeholder
        field.stringValue = ""

        reload()

        guard let window else { return }
        // Center over the active window.
        if let host = NSApp.keyWindow {
            let hf = host.frame
            let pw = window.frame.width
            let ph = window.frame.height
            let origin = NSPoint(
                x: hf.midX - pw / 2,
                y: hf.midY - ph / 2 + ph / 4)
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.field.becomeFirstResponder() }
    }

    public func dismiss() {
        window?.orderOut(nil)
    }

    /// Re-run the active provider's query with the current field text.
    public func reload() {
        guard let provider else { return }
        let q = field.stringValue
        let raw = provider.items(for: q)
        let capped = Array(raw.prefix(provider.maxResults))
        self.items = capped
        self.selectedRow = capped.isEmpty ? -1 : 0
        table.reloadData()
        if selectedRow >= 0 {
            table.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
            table.scrollRowToVisible(selectedRow)
        }
    }

    // MARK: - NSTextFieldDelegate

    public func controlTextDidChange(_ obj: Notification) {
        reload()
    }

    public func control(_ control: NSControl,
                        textView: NSTextView,
                        doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            move(by: 1); return true
        case #selector(NSResponder.moveUp(_:)):
            move(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)):
            activateSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(); return true
        case #selector(NSResponder.scrollPageDown(_:)):
            move(by: 10); return true
        case #selector(NSResponder.scrollPageUp(_:)):
            move(by: -10); return true
        default:
            return false
        }
    }

    private func move(by delta: Int) {
        guard !items.isEmpty else { return }
        let newRow = max(0, min(items.count - 1, selectedRow + delta))
        if newRow == selectedRow { return }
        selectedRow = newRow
        table.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        table.scrollRowToVisible(newRow)
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = table.clickedRow
        guard row >= 0, row < items.count else { return }
        selectedRow = row
        activateSelected()
    }

    private func activateSelected() {
        guard let provider, selectedRow >= 0, selectedRow < items.count else { return }
        let item = items[selectedRow]
        dismiss()
        // Dispatch on next runloop so the panel ordering settles before the
        // action (e.g. opening a document) makes its own window key.
        DispatchQueue.main.async { provider.activate(item) }
    }

    // MARK: - NSTableViewDataSource / Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }

    public func tableView(_ tableView: NSTableView,
                          viewFor tableColumn: NSTableColumn?,
                          row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]
        let identifier = NSUserInterfaceItemIdentifier("PaletteCell")
        let cell: PaletteCell
        if let recycled = tableView.makeView(withIdentifier: identifier, owner: self) as? PaletteCell {
            cell = recycled
        } else {
            cell = PaletteCell()
            cell.identifier = identifier
        }
        cell.configure(with: item)
        return cell
    }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 36
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        selectedRow = table.selectedRow
    }
}

// MARK: - Row view

private final class PaletteCell: NSTableCellView {

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .secondaryLabelColor
        addSubview(iconView)

        titleField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        subtitleField.font = NSFont.systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingMiddle
        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
        ])
    }

    func configure(with item: PaletteItem) {
        if let sym = item.symbol {
            iconView.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)
        } else {
            iconView.image = nil
        }
        titleField.attributedStringValue = highlight(title: item.title, indices: item.matchedIndices)
        subtitleField.stringValue = item.subtitle ?? ""
        subtitleField.isHidden = (item.subtitle ?? "").isEmpty
    }

    private func highlight(title: String, indices: [Int]) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: title)
        let full = NSRange(location: 0, length: (title as NSString).length)
        attr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        let set = Set(indices)
        // Walk Unicode scalars so our index space matches PaletteFuzzy's.
        var charIdx = 0
        for s in title.unicodeScalars {
            if set.contains(charIdx) {
                let scalarChar = String(s)
                let range = (title as NSString).range(of: scalarChar, options: [], range: NSRange(location: scalarRangeStart(in: title, scalarIndex: charIdx), length: scalarLength(in: title, scalarIndex: charIdx)))
                if range.location != NSNotFound {
                    attr.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
                    attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
            }
            charIdx += 1
        }
        return attr
    }

    /// Byte (UTF-16) offset corresponding to scalar index `i` in `s`.
    private func scalarRangeStart(in s: String, scalarIndex i: Int) -> Int {
        var loc = 0
        var idx = 0
        for scalar in s.unicodeScalars {
            if idx == i { return loc }
            loc += scalar.utf16.count
            idx += 1
        }
        return loc
    }

    private func scalarLength(in s: String, scalarIndex i: Int) -> Int {
        var idx = 0
        for scalar in s.unicodeScalars {
            if idx == i { return scalar.utf16.count }
            idx += 1
        }
        return 0
    }
}
