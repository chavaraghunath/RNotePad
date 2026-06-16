// SPDX-License-Identifier: MIT
// Sourcepad — Settings panes: Agents (defaults), Keybindings, Privacy.

import AppKit

// MARK: - Agents (defaults & permissions)

final class SettingsAgentDefaultsPane: SettingsPaneViewController {

    private let permission = NSSegmentedControl(labels: ["Plan (read-only)", "Auto (edit / run)"],
                                                trackingMode: .selectOne, target: nil, action: nil)
    private lazy var clearButton = NSButton(title: "Clear Conversation History…",
                                            target: self, action: #selector(clearHistory))
    private let countLabel = NSTextField(labelWithString: "")

    override func rows() -> [(String, NSView)] {
        permission.target = self
        permission.action = #selector(permChanged(_:))

        clearButton.bezelStyle = .rounded
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        let clearRow = NSStackView(views: [clearButton, countLabel])
        clearRow.orientation = .horizontal
        clearRow.spacing = 10

        let note = NSTextField(wrappingLabelWithString: "Plan keeps the agent read-only; Auto lets it edit files and run commands. Whether Auto runs sandboxed is set in Settings ▸ Agent CLIs.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        return [
            ("New conversations start in", permission),
            ("", note),
            ("History", clearRow),
        ]
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        permission.selectedSegment = Preferences.shared.agentDefaultPermission == "auto" ? 1 : 0
        refreshCount()
    }

    private func refreshCount() {
        let n = AgentStore.shared?.recentConversations(limit: 1_000_000).count ?? 0
        countLabel.stringValue = n == 0 ? "No saved conversations." : "\(n) saved conversation\(n == 1 ? "" : "s")."
    }

    @objc private func permChanged(_ s: NSSegmentedControl) {
        Preferences.shared.agentDefaultPermission = s.selectedSegment == 1 ? "auto" : "readOnly"
    }

    @objc private func clearHistory() {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Clear all conversation history?"
        a.informativeText = "Deletes every saved agent conversation, its messages, and tool calls. This cannot be undone."
        a.addButton(withTitle: "Clear")
        a.addButton(withTitle: "Cancel")
        let perform: () -> Void = { [weak self] in
            if let store = AgentStore.shared {
                for row in store.recentConversations(limit: 1_000_000) { store.deleteConversation(row.id) }
            }
            self?.refreshCount()
        }
        if let win = view.window {
            a.beginSheetModal(for: win) { if $0 == .alertFirstButtonReturn { perform() } }
        } else if a.runModal() == .alertFirstButtonReturn {
            perform()
        }
    }
}

// MARK: - Keybindings (searchable reference)

/// A read-only, searchable reference of every menu keyboard shortcut, built by
/// walking the live main menu. (Rebinding has no runtime infrastructure yet; this
/// surfaces what exists rather than pretending to edit it.)
final class SettingsKeybindingsPane: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    private struct Binding { let command: String; let shortcut: String }
    private let search = NSSearchField()
    private let table = NSTableView()
    private var all: [Binding] = []
    private var shown: [Binding] = []

    override func loadView() {
        let root = NSView()

        let title = NSTextField(labelWithString: "Keyboard Shortcuts")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let sub = NSTextField(wrappingLabelWithString: "Every shortcut Sourcepad currently responds to. Search by command or keys.")
        sub.font = .systemFont(ofSize: 11); sub.textColor = .secondaryLabelColor
        sub.translatesAutoresizingMaskIntoConstraints = false

        search.placeholderString = "Filter shortcuts…"
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false

        for (idf, t, w) in [("command", "Command", 360), ("shortcut", "Shortcut", 140)] as [(String, String, CGFloat)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(idf))
            c.title = t; c.width = w
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        [title, sub, search, scroll].forEach { root.addSubview($0) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            sub.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            sub.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            search.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 10),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
        self.view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        all = SettingsKeybindingsPane.collect(menu: NSApp.mainMenu, prefix: "")
            .sorted { $0.command.localizedCaseInsensitiveCompare($1.command) == .orderedAscending }
        applyFilter()
    }

    private static func collect(menu: NSMenu?, prefix: String) -> [Binding] {
        guard let menu else { return [] }
        var out: [Binding] = []
        for item in menu.items where !item.isSeparatorItem {
            let path = prefix.isEmpty ? item.title : "\(prefix) › \(item.title)"
            if let sub = item.submenu {
                out += collect(menu: sub, prefix: path)
            } else if !item.keyEquivalent.isEmpty {
                out.append(Binding(command: path, shortcut: shortcutString(item)))
            }
        }
        return out
    }

    private static func shortcutString(_ item: NSMenuItem) -> String {
        var s = ""
        let m = item.keyEquivalentModifierMask
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option)  { s += "⌥" }
        if m.contains(.shift)   { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        s += prettyKey(item.keyEquivalent)
        return s
    }

    private static func prettyKey(_ key: String) -> String {
        let map: [Character: String] = [
            "\r": "↩", "\t": "⇥", " ": "Space", "\u{1b}": "⎋", "\u{7f}": "⌫",
            "\u{f700}": "↑", "\u{f701}": "↓", "\u{f702}": "←", "\u{f703}": "→",
            "\u{f704}": "F1", "\u{f705}": "F2", "\u{f706}": "F3", "\u{f707}": "F4",
            "\u{f708}": "F5", "\u{f709}": "F6", "\u{f70a}": "F7", "\u{f70b}": "F8",
            "\u{f70c}": "F9", "\u{f70d}": "F10", "\u{f70e}": "F11", "\u{f70f}": "F12",
            "\u{f729}": "Home", "\u{f72b}": "End", "\u{f72c}": "PgUp", "\u{f72d}": "PgDn",
        ]
        if let first = key.first, let mapped = map[first] { return mapped }
        return key.uppercased()
    }

    private func applyFilter() {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        shown = q.isEmpty ? all : all.filter {
            $0.command.lowercased().contains(q) || $0.shortcut.lowercased().contains(q)
        }
        table.reloadData()
    }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < shown.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let b = shown[row]
        let value = id == "shortcut" ? b.shortcut : b.command
        let field = NSTextField(labelWithString: value)
        field.font = id == "shortcut"
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}

// MARK: - Privacy

final class SettingsPrivacyPane: NSViewController {

    private let debugLog = NSButton(checkboxWithTitle: "Write a debug log to /tmp/sourcepad.log", target: nil, action: nil)

    override func loadView() {
        let root = NSView()

        let title = NSTextField(labelWithString: "Privacy")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let statement = NSTextField(wrappingLabelWithString:
            "Sourcepad collects no telemetry or analytics, and stores no accounts, API keys, or tokens.\n\n" +
            "The only network request Sourcepad itself makes is to the public Hugging Face Hub API when you browse MLX models. Agent CLIs, language servers, and MCP servers are separate processes that manage their own network access and credentials.")
        statement.font = .systemFont(ofSize: 12)

        debugLog.target = self
        debugLog.action = #selector(toggleDebugLog(_:))
        debugLog.state = Preferences.shared.debugLoggingEnabled ? .on : .off

        let dataTitle = NSTextField(labelWithString: "Local data")
        dataTitle.font = .systemFont(ofSize: 12, weight: .semibold)

        func button(_ t: String, _ sel: Selector) -> NSButton {
            let b = NSButton(title: t, target: self, action: sel)
            b.bezelStyle = .rounded
            return b
        }
        let clearRow1 = NSStackView(views: [
            button("Clear Conversation History…", #selector(clearAgentHistory)),
            button("Clear Session", #selector(clearSession)),
        ])
        let clearRow2 = NSStackView(views: [
            button("Clear SourceGraph Cache", #selector(clearSourceGraph)),
            button("Clear Debug Log", #selector(clearDebugLog)),
        ])
        let revealRow = NSStackView(views: [
            button("Reveal Data Folder in Finder", #selector(revealData)),
        ])
        for r in [clearRow1, clearRow2, revealRow] { r.orientation = .horizontal; r.spacing = 8; r.alignment = .leading }

        let stack = NSStackView(views: [title, statement, debugLog,
                                        spacer(), dataTitle, clearRow1, clearRow2, revealRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
        ])
        self.view = root
    }

    private func spacer() -> NSView {
        let v = NSView()
        v.heightAnchor.constraint(equalToConstant: 6).isActive = true
        return v
    }

    private var supportDir: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
         ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support"))
            .appendingPathComponent("Sourcepad", isDirectory: true)
    }

    @objc private func toggleDebugLog(_ s: NSButton) {
        Preferences.shared.debugLoggingEnabled = (s.state == .on)
    }

    @objc private func clearAgentHistory() {
        confirm("Clear all conversation history?",
                "Deletes every saved agent conversation. This cannot be undone.") {
            if let store = AgentStore.shared {
                for row in store.recentConversations(limit: 1_000_000) { store.deleteConversation(row.id) }
            }
        }
    }

    @objc private func clearSession() {
        SessionRestore.shared.clear()
        toast("Session cleared.")
    }

    @objc private func clearSourceGraph() {
        let dir = supportDir.appendingPathComponent("SourceGraph", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        toast("SourceGraph cache cleared.")
    }

    @objc private func clearDebugLog() {
        try? FileManager.default.removeItem(atPath: DebugLog.path)
        toast("Debug log cleared.")
    }

    @objc private func revealData() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([supportDir])
    }

    private func confirm(_ message: String, _ info: String, _ perform: @escaping () -> Void) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = message
        a.informativeText = info
        a.addButton(withTitle: "Clear")
        a.addButton(withTitle: "Cancel")
        if let win = view.window {
            a.beginSheetModal(for: win) { if $0 == .alertFirstButtonReturn { perform() } }
        } else if a.runModal() == .alertFirstButtonReturn {
            perform()
        }
    }

    private func toast(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.addButton(withTitle: "OK")
        if let win = view.window { a.beginSheetModal(for: win) { _ in } } else { a.runModal() }
    }
}
