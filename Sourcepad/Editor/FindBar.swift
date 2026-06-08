// SPDX-License-Identifier: MIT
// Sourcepad — find/replace bar that slides above the Scintilla view.
//
// Two-row stack: the find row is always visible, the replace row toggles via
// the disclosure triangle. All search work is delegated to the SciTextView
// bridge — this file just owns the UI and the search state machine.

import AppKit

public final class FindBar: NSView, NSTextFieldDelegate {

    // MARK: - Wiring

    /// The Scintilla view we operate on. Set by EditorPaneViewController.
    public weak var editorView: NSView?

    /// Closure to call after dismissing (so focus can return to the editor).
    public var onClose: (() -> Void)?

    // MARK: - UI

    private let findField  = NSTextField()
    private let replaceField = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private let caseToggle = NSButton(checkboxWithTitle: "Aa", target: nil, action: nil)
    private let regexToggle = NSButton(checkboxWithTitle: ".*", target: nil, action: nil)
    private let wordToggle  = NSButton(checkboxWithTitle: "W", target: nil, action: nil)
    private let prevButton  = NSButton(title: "‹", target: nil, action: nil)
    private let nextButton  = NSButton(title: "›", target: nil, action: nil)
    private let replaceDisclosure = NSButton(checkboxWithTitle: "Replace", target: nil, action: nil)
    private let replaceButton    = NSButton(title: "Replace", target: nil, action: nil)
    private let replaceAllButton = NSButton(title: "Replace All", target: nil, action: nil)
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)

    private var replaceRow: NSStackView!
    private var findRow: NSStackView!

    // MARK: - State

    private var lastMatchEnd: Int = 0      // byte position where the next forward search starts
    private var matchCount: Int = 0
    private var matchIndex: Int = 0        // 1-based index of the current match
    private var lastPattern: String = ""
    private var lastFlags: Int = 0

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let bottomBorder = NSView()
        bottomBorder.wantsLayer = true
        bottomBorder.layer?.backgroundColor = NSColor.separatorColor.cgColor
        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBorder)
        NSLayoutConstraint.activate([
            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),
        ])

        // Configure controls.
        findField.placeholderString = "Find"
        findField.bezelStyle = .roundedBezel
        findField.delegate = self
        findField.target = self
        findField.action = #selector(findFieldEnter(_:))
        findField.translatesAutoresizingMaskIntoConstraints = false
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        replaceField.placeholderString = "Replace with"
        replaceField.bezelStyle = .roundedBezel
        replaceField.target = self
        replaceField.action = #selector(performReplaceAndAdvance(_:))
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.stringValue = ""
        countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true

        for (btn, sel, tip) in [
            (caseToggle, #selector(toggleFlag(_:)),  "Case sensitive"),
            (regexToggle, #selector(toggleFlag(_:)), "Regular expression"),
            (wordToggle, #selector(toggleFlag(_:)),  "Whole word"),
        ] {
            btn.target = self
            btn.action = sel
            btn.toolTip = tip
            btn.controlSize = .small
            btn.font = NSFont.systemFont(ofSize: 11)
        }

        for (btn, sel, tip) in [
            (prevButton, #selector(findPrevious(_:)), "Previous match (⇧⌘G)"),
            (nextButton, #selector(findNext(_:)),     "Next match (⌘G)"),
            (replaceButton, #selector(performReplaceAndAdvance(_:)), "Replace current match"),
            (replaceAllButton, #selector(performReplaceAll(_:)),     "Replace all in document"),
            (closeButton, #selector(dismissBar(_:)),  "Hide find bar (Esc)"),
        ] {
            btn.target = self
            btn.action = sel
            btn.toolTip = tip
            btn.bezelStyle = .rounded
            btn.controlSize = .regular
        }

        closeButton.bezelStyle = .helpButton
        closeButton.title = "✕"

        replaceDisclosure.target = self
        replaceDisclosure.action = #selector(toggleReplaceRow(_:))
        replaceDisclosure.controlSize = .small
        replaceDisclosure.toolTip = "Show replace row"

        // Find row.
        let findStack = NSStackView(views: [
            closeButton, findField, caseToggle, regexToggle, wordToggle,
            prevButton, nextButton, countLabel, replaceDisclosure,
        ])
        findStack.orientation = .horizontal
        findStack.spacing = 6
        findStack.alignment = .centerY
        findStack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        findStack.translatesAutoresizingMaskIntoConstraints = false
        self.findRow = findStack

        // Replace row (hidden by default).
        let replaceLeadingSpacer = NSView()
        replaceLeadingSpacer.widthAnchor.constraint(equalToConstant: 30).isActive = true
        let replaceStack = NSStackView(views: [
            replaceLeadingSpacer, replaceField, replaceButton, replaceAllButton,
        ])
        replaceStack.orientation = .horizontal
        replaceStack.spacing = 6
        replaceStack.alignment = .centerY
        replaceStack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 6, right: 10)
        replaceStack.translatesAutoresizingMaskIntoConstraints = false
        replaceStack.isHidden = true
        self.replaceRow = replaceStack

        let outer = NSStackView(views: [findStack, replaceStack])
        outer.orientation = .vertical
        outer.spacing = 0
        outer.alignment = .leading
        outer.distribution = .fill
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            findStack.widthAnchor.constraint(equalTo: outer.widthAnchor),
            replaceStack.widthAnchor.constraint(equalTo: outer.widthAnchor),
        ])
    }

    public override var intrinsicContentSize: NSSize {
        // Height = find row (28) + 1px border, plus replace row (28) when visible.
        let rows: CGFloat = (replaceRow?.isHidden ?? true) ? 1 : 2
        return NSSize(width: NSView.noIntrinsicMetric, height: 32 * rows + 1)
    }

    // MARK: - Public API

    public func show(prefill: String? = nil, withReplace: Bool = false) {
        if let prefill, !prefill.isEmpty { findField.stringValue = prefill }
        if withReplace, replaceRow.isHidden {
            replaceRow.isHidden = false
            replaceDisclosure.state = .on
            invalidateIntrinsicContentSize()
        }
        window?.makeFirstResponder(findField)
        findField.selectText(nil)
        runSearch(initial: true)
    }

    public func dismiss() {
        onClose?()
    }

    // MARK: - Actions

    @objc private func dismissBar(_ sender: Any?) { dismiss() }

    @objc private func toggleReplaceRow(_ sender: Any?) {
        replaceRow.isHidden.toggle()
        replaceDisclosure.toolTip = replaceRow.isHidden ? "Show replace row" : "Hide replace row"
        invalidateIntrinsicContentSize()
    }

    @objc private func toggleFlag(_ sender: Any?) {
        runSearch(initial: true)
    }

    @objc private func findFieldEnter(_ sender: Any?) {
        // Cmd+Enter or Enter advances to next match.
        findNext(sender)
    }

    @objc public func findNext(_ sender: Any?) {
        guard let view = editorView else { return }
        let pattern = findField.stringValue
        guard !pattern.isEmpty else { NSSound.beep(); return }
        let flags = currentFlags()
        if pattern != lastPattern || flags != lastFlags {
            runSearch(initial: true); return
        }
        let next = SciFind(view, pattern, SciFindFlags(rawValue: Int32(flags)), lastMatchEnd, -1)
        if next.location == NSNotFound {
            // Wrap around to start.
            let wrap = SciFind(view, pattern, SciFindFlags(rawValue: Int32(flags)), 0, -1)
            if wrap.location == NSNotFound {
                showStatus("Not found")
                return
            }
            selectMatch(wrap, in: view)
            matchIndex = 1
        } else {
            selectMatch(next, in: view)
            matchIndex += 1
        }
        updateCount()
    }

    @objc public func findPrevious(_ sender: Any?) {
        guard let view = editorView else { return }
        let pattern = findField.stringValue
        guard !pattern.isEmpty else { NSSound.beep(); return }
        let flags = currentFlags()
        let currentSel = SciGetSelectionBytes(view)
        let upperBound = currentSel.location == NSNotFound ? SciTextLengthBytes(view) : Int(currentSel.location)
        // Walk forward from 0 to upperBound, keeping the last match found.
        var pos: Int = 0
        var last = NSRange(location: NSNotFound, length: 0)
        while true {
            let r = SciFind(view, pattern, SciFindFlags(rawValue: Int32(flags)), pos, upperBound)
            if r.location == NSNotFound { break }
            last = r
            pos = Int(r.location) + max(1, Int(r.length))
        }
        if last.location == NSNotFound {
            // Wrap: take the last match anywhere in the document.
            var p: Int = 0
            let docLen = SciTextLengthBytes(view)
            while true {
                let r = SciFind(view, pattern, SciFindFlags(rawValue: Int32(flags)), p, docLen)
                if r.location == NSNotFound { break }
                last = r
                p = Int(r.location) + max(1, Int(r.length))
            }
        }
        if last.location == NSNotFound { showStatus("Not found"); return }
        selectMatch(last, in: view)
        matchIndex = max(1, matchIndex - 1)
        updateCount()
    }

    @objc public func performReplaceAndAdvance(_ sender: Any?) {
        guard let view = editorView else { return }
        let sel = SciGetSelectionBytes(view)
        let pattern = findField.stringValue
        guard !pattern.isEmpty else { NSSound.beep(); return }
        let flags = currentFlags()
        // If current selection matches the pattern, replace it. Otherwise just advance.
        if sel.length > 0 {
            let probe = SciFind(view, pattern, SciFindFlags(rawValue: Int32(flags)),
                                Int(sel.location), Int(sel.location) + Int(sel.length))
            if probe.location == sel.location && probe.length == sel.length {
                SciBeginUndoAction(view)
                let newEnd = SciReplaceBytesRange(view, Int(sel.location), Int(sel.location) + Int(sel.length), replaceField.stringValue)
                SciEndUndoAction(view)
                lastMatchEnd = newEnd
            }
        }
        findNext(sender)
    }

    @objc public func performReplaceAll(_ sender: Any?) {
        guard let view = editorView else { return }
        let pattern = findField.stringValue
        guard !pattern.isEmpty else { NSSound.beep(); return }
        let replacement = replaceField.stringValue
        let flags = SciFindFlags(rawValue: Int32(currentFlags()))

        SciBeginUndoAction(view)
        var pos: Int = 0
        var count = 0
        let replacementBytes = (replacement as NSString).lengthOfBytes(using: String.Encoding.utf8.rawValue)
        while true {
            let docLen = SciTextLengthBytes(view)
            let r = SciFind(view, pattern, flags, pos, docLen)
            if r.location == NSNotFound { break }
            let newEnd = SciReplaceBytesRange(view, Int(r.location), Int(r.location) + Int(r.length), replacement)
            pos = max(newEnd, Int(r.location) + max(1, replacementBytes))  // avoid infinite loop on empty replace of empty match
            count += 1
        }
        SciEndUndoAction(view)
        showStatus("Replaced \(count)")
        matchCount = 0
        matchIndex = 0
        updateCount()
    }

    // MARK: - NSTextField delegate (live search as user types in find field)

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === findField else { return }
        runSearch(initial: true)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === findField || control === replaceField {
            if selector == #selector(cancelOperation(_:)) {
                dismiss(); return true
            }
        }
        return false
    }

    // MARK: - Helpers

    private func currentFlags() -> Int {
        var f = 0
        if caseToggle.state  == .on { f |= Int(SciFindFlags.matchCase.rawValue) }
        if regexToggle.state == .on { f |= Int(SciFindFlags.regex.rawValue) }
        if wordToggle.state  == .on { f |= Int(SciFindFlags.wholeWord.rawValue) }
        return f
    }

    private func runSearch(initial: Bool) {
        guard let view = editorView else { return }
        let pattern = findField.stringValue
        lastPattern = pattern
        lastFlags = currentFlags()
        guard !pattern.isEmpty else {
            matchCount = 0; matchIndex = 0; updateCount(); return
        }
        // Count all matches in document.
        countAllMatches(in: view, pattern: pattern, flags: SciFindFlags(rawValue: Int32(lastFlags)))
        // For initial search, find the first match from the current selection.
        let sel = SciGetSelectionBytes(view)
        let startPos = sel.location == NSNotFound ? 0 : Int(sel.location)
        let r = SciFind(view, pattern, SciFindFlags(rawValue: Int32(lastFlags)), startPos, -1)
        if r.location == NSNotFound {
            let wrap = SciFind(view, pattern, SciFindFlags(rawValue: Int32(lastFlags)), 0, -1)
            if wrap.location == NSNotFound { showStatus("Not found"); return }
            selectMatch(wrap, in: view)
            matchIndex = 1
        } else {
            selectMatch(r, in: view)
            // Compute matchIndex by counting matches before this position.
            matchIndex = countMatchesBefore(in: view, pattern: pattern, flags: SciFindFlags(rawValue: Int32(lastFlags)), endByte: Int(r.location)) + 1
        }
        updateCount()
    }

    private func countAllMatches(in view: NSView, pattern: String, flags: SciFindFlags) {
        var pos: Int = 0
        var count = 0
        let docLen = SciTextLengthBytes(view)
        while true {
            let r = SciFind(view, pattern, flags, pos, docLen)
            if r.location == NSNotFound { break }
            count += 1
            pos = Int(r.location) + max(1, Int(r.length))
        }
        matchCount = count
    }

    private func countMatchesBefore(in view: NSView, pattern: String, flags: SciFindFlags, endByte: Int) -> Int {
        var pos: Int = 0
        var count = 0
        while pos < endByte {
            let r = SciFind(view, pattern, flags, pos, endByte)
            if r.location == NSNotFound { break }
            count += 1
            pos = Int(r.location) + max(1, Int(r.length))
        }
        return count
    }

    private func selectMatch(_ r: NSRange, in view: NSView) {
        SciSetSelectionBytes(view, Int(r.location), Int(r.location) + Int(r.length))
        lastMatchEnd = Int(r.location) + Int(r.length)
    }

    private func updateCount() {
        if matchCount == 0 {
            countLabel.stringValue = "—"
        } else {
            countLabel.stringValue = "\(matchIndex) of \(matchCount)"
        }
    }

    private func showStatus(_ message: String) {
        countLabel.stringValue = message
        matchCount = 0
        matchIndex = 0
    }
}
