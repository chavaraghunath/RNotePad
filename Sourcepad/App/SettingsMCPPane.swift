// SPDX-License-Identifier: MIT
// Sourcepad — Settings ▸ MCP pane.
//
// Shows the canonical MCP registry Sourcepad manages (the built-in SourceGraph
// server plus user-defined custom servers) and the live sync status for each
// detected agent CLI. Adding/removing a custom server, or toggling auto-sync,
// mirrors the change into every CLI's own config (managed-only, backed up).

import AppKit

final class SettingsMCPPane: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let autoSync = NSButton(checkboxWithTitle: "Keep agent CLIs in sync automatically", target: nil, action: nil)
    private let table = NSTableView()
    private let removeButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")

    private var servers: [MCPServerSpec] = []

    private var workspaceRoot: String {
        WorkspaceManager.shared.activeWorkspace.roots.first?.path ?? NSHomeDirectory()
    }

    override func loadView() {
        let root = NSView()

        let title = NSTextField(labelWithString: "Managed MCP servers")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let sub = NSTextField(wrappingLabelWithString: "These servers are mirrored into every detected agent CLI (Codex, Claude, opencode, gemini) in its own format. Each CLI keeps its own config; Sourcepad only touches the entries it manages.")
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        sub.translatesAutoresizingMaskIntoConstraints = false

        autoSync.target = self
        autoSync.action = #selector(toggleAutoSync(_:))
        autoSync.state = Preferences.shared.mcpAutoSyncEnabled ? .on : .off
        autoSync.translatesAutoresizingMaskIntoConstraints = false

        for (idf, t, w) in [("name", "Name", 150), ("command", "Command", 320), ("kind", "Kind", 80)] as [(String, String, CGFloat)] {
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

        let addButton = NSButton(title: "Add Server…", target: self, action: #selector(addServer))
        addButton.bezelStyle = .rounded
        removeButton.title = "Remove"
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeServer)
        removeButton.isEnabled = false
        let syncButton = NSButton(title: "Sync Now", target: self, action: #selector(syncNow))
        syncButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [addButton, removeButton, NSView(), syncButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        [title, sub, autoSync, scroll, buttons, statusLabel].forEach { root.addSubview($0) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            sub.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            sub.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            autoSync.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 10),
            autoSync.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            scroll.topAnchor.constraint(equalTo: autoSync.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            statusLabel.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -8),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        self.view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
        refreshStatus()
    }

    // MARK: - Data

    private func reload() {
        servers = MCPRegistry.shared.allManaged(workspaceRoot: workspaceRoot)
        table.reloadData()
        removeButton.isEnabled = false
    }

    private func refreshStatus() {
        let root = workspaceRoot
        DispatchQueue.global(qos: .userInitiated).async {
            let drift = MCPSyncEngine.drift(workspaceRoot: root)
            let text = drift.map { d -> String in
                let state = !d.present ? "not found" : (d.inSync ? "in sync" : "needs sync")
                return "\(d.cli): \(state)"
            }.joined(separator: "    ")
            DispatchQueue.main.async { self.statusLabel.stringValue = text }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { servers.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < servers.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let s = servers[row]
        let value: String
        switch id {
        case "name":    value = s.name
        case "command": value = ([s.command] + s.args).joined(separator: " ")
        case "kind":    value = s.builtIn ? "Built-in" : "Custom"
        default:        value = ""
        }
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingMiddle
        if id == "kind" { field.textColor = s.builtIn ? .secondaryLabelColor : .labelColor }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        removeButton.isEnabled = row >= 0 && row < servers.count && !servers[row].builtIn
    }

    // MARK: - Actions

    @objc private func toggleAutoSync(_ sender: NSButton) {
        Preferences.shared.mcpAutoSyncEnabled = (sender.state == .on)
        if sender.state == .on { syncNow() }
    }

    @objc private func syncNow() {
        let root = workspaceRoot
        statusLabel.stringValue = "Syncing…"
        DispatchQueue.global(qos: .userInitiated).async {
            _ = MCPSyncEngine.syncAll(workspaceRoot: root)
            DispatchQueue.main.async { self.refreshStatus() }
        }
    }

    @objc private func removeServer() {
        let row = table.selectedRow
        guard row >= 0, row < servers.count, !servers[row].builtIn else { return }
        MCPRegistry.shared.removeCustom(name: servers[row].name)
        reload()
        refreshStatus()   // didChange triggers auto-sync; reflect new status
    }

    @objc private func addServer() {
        let alert = NSAlert()
        alert.messageText = "Add MCP server"
        alert.informativeText = "Name must be letters/numbers/-/_. Args are space-separated; env is KEY=VALUE per line."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 22))
        nameField.placeholderString = "name (e.g. my-server)"
        let cmdField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 22))
        cmdField.placeholderString = "command (executable path or name)"
        let argsField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 22))
        argsField.placeholderString = "args (space-separated, optional)"
        let envView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 60))
        envView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let envScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 60))
        envScroll.documentView = envView
        envScroll.borderType = .bezelBorder
        envScroll.hasVerticalScroller = true

        let stack = NSStackView(views: [nameField, cmdField, argsField,
                                        NSTextField(labelWithString: "env (KEY=VALUE per line):"), envScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 200)
        alert.accessoryView = stack

        guard let win = view.window else { return }
        alert.beginSheetModal(for: win) { [weak self] resp in
            guard resp == .alertFirstButtonReturn, let self else { return }
            let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            let command = cmdField.stringValue.trimmingCharacters(in: .whitespaces)
            let args = argsField.stringValue.split(separator: " ").map(String.init)
            var env: [String: String] = [:]
            for line in envView.string.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    env[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            guard MCPServerSpec.isValidName(name), name != "sourcegraph" else {
                self.warn("Invalid name", "Use letters, numbers, “-” or “_”, and not the reserved name “sourcegraph”.")
                return
            }
            guard !command.isEmpty else {
                self.warn("Missing command", "Enter the server's executable.")
                return
            }
            MCPRegistry.shared.upsertCustom(MCPServerSpec(name: name, command: command, args: args, env: env))
            self.reload()
            self.refreshStatus()
        }
    }

    private func warn(_ text: String, _ info: String) {
        let a = NSAlert()
        a.messageText = text
        a.informativeText = info
        a.addButton(withTitle: "OK")
        if let win = view.window { a.beginSheetModal(for: win) { _ in } } else { a.runModal() }
    }
}
