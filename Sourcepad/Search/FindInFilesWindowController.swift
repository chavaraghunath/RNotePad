// SPDX-License-Identifier: MIT
// Sourcepad — Find in Files (⌘⇧F) window. Single window per app session.

import AppKit

public final class FindInFilesWindowController: NSWindowController,
                                                NSOutlineViewDataSource,
                                                NSOutlineViewDelegate,
                                                NSTextFieldDelegate {

    public static let shared: FindInFilesWindowController = {
        let wc = FindInFilesWindowController()
        return wc
    }()

    private let engine = FindInFilesEngine()
    private var results: [FIFResult] = []
    private var rootURL: URL?

    private let queryField    = NSTextField()
    private let folderLabel   = NSTextField(labelWithString: "—")
    private let folderButton  = NSButton(title: "Choose…", target: nil, action: nil)
    private let caseToggle    = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    private let wordToggle    = NSButton(checkboxWithTitle: "Whole word", target: nil, action: nil)
    private let searchButton  = NSButton(title: "Search", target: nil, action: nil)
    private let cancelButton  = NSButton(title: "Cancel", target: nil, action: nil)
    private let progressLabel = NSTextField(labelWithString: "")
    private let countLabel    = NSTextField(labelWithString: "")
    private let outlineView   = NSOutlineView()
    private let scroll        = NSScrollView()

    public convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Find in Files"
        window.setFrameAutosaveName("SourcepadFindInFiles")
        window.center()
        self.init(window: window)
        buildUI()
    }

    // MARK: - Public entry

    public func show(searchingIn root: URL?) {
        self.rootURL = root
        folderLabel.stringValue = root?.path ?? "No folder selected"
        window?.makeKeyAndOrderFront(nil)
        queryField.becomeFirstResponder()
    }

    // MARK: - UI

    private func buildUI() {
        guard let window else { return }
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = content

        queryField.placeholderString = "Search for…"
        queryField.bezelStyle = .roundedBezel
        queryField.delegate = self
        queryField.target = self
        queryField.action = #selector(searchTapped(_:))
        queryField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(queryField)

        folderLabel.font = NSFont.systemFont(ofSize: 11)
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(folderLabel)

        folderButton.target = self
        folderButton.action = #selector(chooseFolder(_:))
        folderButton.bezelStyle = .rounded
        folderButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(folderButton)

        caseToggle.translatesAutoresizingMaskIntoConstraints = false
        wordToggle.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(caseToggle)
        content.addSubview(wordToggle)

        searchButton.target = self
        searchButton.action = #selector(searchTapped(_:))
        searchButton.bezelStyle = .rounded
        searchButton.keyEquivalent = "\r"
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(searchButton)

        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped(_:))
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(cancelButton)

        progressLabel.font = NSFont.systemFont(ofSize: 11)
        progressLabel.textColor = .tertiaryLabelColor
        progressLabel.lineBreakMode = .byTruncatingMiddle
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(progressLabel)

        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(countLabel)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        col.title = "Matches"
        col.width = 680
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.rowSizeStyle = .small
        outlineView.target = self
        outlineView.doubleAction = #selector(rowDoubleClicked(_:))

        scroll.documentView = outlineView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            queryField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            queryField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            queryField.trailingAnchor.constraint(equalTo: searchButton.leadingAnchor, constant: -8),

            searchButton.centerYAnchor.constraint(equalTo: queryField.centerYAnchor),
            searchButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),

            cancelButton.centerYAnchor.constraint(equalTo: queryField.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            folderLabel.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 8),
            folderLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            folderLabel.trailingAnchor.constraint(equalTo: folderButton.leadingAnchor, constant: -8),

            folderButton.centerYAnchor.constraint(equalTo: folderLabel.centerYAnchor),
            folderButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            caseToggle.topAnchor.constraint(equalTo: folderLabel.bottomAnchor, constant: 8),
            caseToggle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),

            wordToggle.centerYAnchor.constraint(equalTo: caseToggle.centerYAnchor),
            wordToggle.leadingAnchor.constraint(equalTo: caseToggle.trailingAnchor, constant: 16),

            scroll.topAnchor.constraint(equalTo: caseToggle.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: progressLabel.topAnchor, constant: -8),

            progressLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            progressLabel.trailingAnchor.constraint(equalTo: countLabel.leadingAnchor, constant: -8),
            progressLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),

            countLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            countLabel.centerYAnchor.constraint(equalTo: progressLabel.centerYAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func chooseFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.rootURL = url
            self?.folderLabel.stringValue = url.path
        }
    }

    @objc private func searchTapped(_ sender: Any?) {
        guard let root = rootURL else {
            chooseFolder(nil)
            return
        }
        let query = queryField.stringValue
        guard !query.isEmpty else { NSSound.beep(); return }
        engine.cancel()
        results.removeAll()
        outlineView.reloadData()
        progressLabel.stringValue = "Searching…"
        countLabel.stringValue = ""
        let options = FIFOptions(caseSensitive: caseToggle.state == .on,
                                 wholeWord:    wordToggle.state == .on)
        engine.search(query: query, in: root, options: options,
                      onResult: { [weak self] result in
                          self?.results.append(result)
                          self?.outlineView.insertItems(at: IndexSet(integer: (self?.results.count ?? 1) - 1),
                                                        inParent: nil, withAnimation: [])
                          let totalMatches = self?.results.reduce(0) { $0 + $1.matches.count } ?? 0
                          self?.countLabel.stringValue = "\(self?.results.count ?? 0) files · \(totalMatches) matches"
                      },
                      onProgress: { [weak self] path in
                          self?.progressLabel.stringValue = (path as NSString).lastPathComponent
                      },
                      onComplete: { [weak self] _ in
                          self?.progressLabel.stringValue = "Done."
                      })
    }

    @objc private func cancelTapped(_ sender: Any?) {
        engine.cancel()
        progressLabel.stringValue = "Cancelled."
    }

    @objc private func rowDoubleClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0 else { return }
        let item = outlineView.item(atRow: row)
        if let result = item as? FIFResult {
            openResult(result, line: result.matches.first?.lineNumber ?? 1)
        } else if let pair = item as? FIFMatchRow {
            openResult(pair.result, line: pair.match.lineNumber)
        }
    }

    private func openResult(_ result: FIFResult, line: Int) {
        NSDocumentController.shared.openDocument(withContentsOf: result.url, display: true) { doc, _, _ in
            guard let wc = (doc as? TextDocument)?.windowControllers.first as? EditorWindowController else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                wc.editorViewController.editorPane.goToLine(line)
            }
        }
    }

    // MARK: - NSOutlineViewDataSource / Delegate

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return results.count }
        if let result = item as? FIFResult { return result.matches.count }
        return 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return results[index] }
        if let result = item as? FIFResult {
            return FIFMatchRow(result: result, match: result.matches[index])
        }
        return ""
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is FIFResult
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = NSTableCellView()
        let tf = NSTextField(labelWithString: "")
        tf.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.textField = tf

        if let result = item as? FIFResult {
            let rel = relativePath(of: result.url)
            let str = NSMutableAttributedString(string: "\(rel)  (\(result.matches.count))")
            str.addAttribute(.foregroundColor, value: NSColor.labelColor,
                             range: NSRange(location: 0, length: rel.count))
            tf.attributedStringValue = str
            tf.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        } else if let row = item as? FIFMatchRow {
            let s = "\(row.match.lineNumber): \(row.match.lineText.trimmingCharacters(in: .whitespaces))"
            let attrs = NSMutableAttributedString(string: s)
            attrs.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                               range: NSRange(location: 0, length: s.count))
            // Highlight match. Adjust offset by the "N: " prefix + leading whitespace stripped.
            let prefix = "\(row.match.lineNumber): "
            let strippedPrefixLen = row.match.lineText.prefix { $0 == " " || $0 == "\t" }.count
            let highlightStart = prefix.count + (row.match.matchRange.location - strippedPrefixLen)
            let highlightLen = row.match.matchRange.length
            if highlightStart >= 0, highlightStart + highlightLen <= s.count {
                attrs.addAttribute(.foregroundColor, value: NSColor.labelColor,
                                   range: NSRange(location: highlightStart, length: highlightLen))
                attrs.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.4),
                                   range: NSRange(location: highlightStart, length: highlightLen))
            }
            tf.attributedStringValue = attrs
        }
        return cell
    }

    private func relativePath(of url: URL) -> String {
        guard let root = rootURL else { return url.path }
        if url.path.hasPrefix(root.path) {
            return String(url.path.dropFirst(root.path.count).dropFirst())  // drop leading "/"
        }
        return url.path
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            window?.performClose(nil)
            return true
        }
        return false
    }
}

/// Wrapper so the outline view can distinguish a top-level result row from a
/// child match row. NSOutlineView's `item` is Any, and we need different
/// display + behaviour per row class.
private final class FIFMatchRow {
    let result: FIFResult
    let match: FIFMatch
    init(result: FIFResult, match: FIFMatch) { self.result = result; self.match = match }
}
