// SPDX-License-Identifier: MIT
// Sourcepad — "Manage Agent CLIs" surface.
//
// Lists every agent CLI (built-in + user-added) with install status + model
// count, and lets the user ADD a new one by command name: it runs `<cmd> --help`
// via CLIProbe, auto-discovers the model list, shows the detected capabilities,
// and on confirm saves an editable spec — no hardcoding, no recompile.
//
// The functional surface lives in `AgentCLIManagerViewController`, hosted both by
// the standalone `AgentCLIManagerWindowController` and, as a pane, inside the
// unified Settings window. Sheets attach to `view.window`, so the same controller
// behaves correctly in either host.

import AppKit

public extension Notification.Name {
    /// Posted after the set of agent CLIs changes (add/remove), so open panels
    /// can refresh their pickers.
    static let sourcepadAgentCLIsChanged = Notification.Name("SourcepadAgentCLIsChanged")
}

public final class AgentCLIManagerViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate {

    private let table = NSTableView()
    private let removeButton = NSButton()
    private let sandboxCheck = NSButton()
    private var rows: [Row] = []

    private struct Row {
        let id: String, name: String, command: String, status: String, models: String, type: String
        let builtIn: Bool
        let installed: Bool
    }

    // MARK: - View

    public override func loadView() {
        let content = NSView()

        let cols: [(String, String, CGFloat)] = [
            ("name", "Name", 140), ("command", "Command", 90),
            ("status", "Status", 90), ("models", "Models", 60), ("type", "Type", 80),
        ]
        for (idf, title, w) in cols {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(idf))
            c.title = title
            c.width = w
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.allowsMultipleSelection = false

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        let add = NSButton(title: "Add CLI…", target: self, action: #selector(addCLI))
        add.bezelStyle = .rounded
        removeButton.title = "Remove"
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeCLI)
        removeButton.isEnabled = false
        let refresh = NSButton(title: "Refresh Models", target: self, action: #selector(refreshModels))
        refresh.bezelStyle = .rounded

        let buttons = NSStackView(views: [add, removeButton, refresh, NSView()])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "Add any agent CLI by command name — Sourcepad reads its --help to configure it.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        sandboxCheck.title = "Run agents sandboxed (confine file writes to the working folder)"
        sandboxCheck.setButtonType(.switch)
        sandboxCheck.target = self
        sandboxCheck.action = #selector(toggleSandbox(_:))
        sandboxCheck.state = Preferences.shared.agentSandboxEnabled ? .on : .off
        sandboxCheck.translatesAutoresizingMaskIntoConstraints = false

        let sandboxNote = NSTextField(labelWithString: "Off grants full disk access (more capable, unsandboxed). Applies to Auto runs; Ask / Read-only stay restricted.")
        sandboxNote.font = .systemFont(ofSize: 11)
        sandboxNote.textColor = .secondaryLabelColor
        sandboxNote.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(hint)
        content.addSubview(sandboxCheck)
        content.addSubview(sandboxNote)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            hint.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            sandboxCheck.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            sandboxCheck.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            sandboxNote.topAnchor.constraint(equalTo: sandboxCheck.bottomAnchor, constant: 2),
            sandboxNote.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            sandboxNote.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            buttons.topAnchor.constraint(equalTo: sandboxNote.bottomAnchor, constant: 10),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        self.view = content
    }

    @objc private func toggleSandbox(_ sender: NSButton) {
        Preferences.shared.agentSandboxEnabled = (sender.state == .on)
    }

    public override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    // MARK: - Data

    private func reload() {
        let reg = AgentRegistry.shared
        let customIDs = Set(CLISpecStore.shared.load().map { $0.id })
        rows = reg.allCLIs.map { cli in
            let installed = cli.isAvailable
            let models = reg.models(for: cli.id).count
            return Row(id: cli.id, name: cli.displayName, command: cli.id,
                       status: installed ? "Installed" : "Not found",
                       models: models > 0 ? "\(models)" : (installed ? "…" : "—"),
                       type: customIDs.contains(cli.id) ? "Custom" : "Built-in",
                       builtIn: !customIDs.contains(cli.id), installed: installed)
        }
        table.reloadData()
        removeButton.isEnabled = false
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let r = rows[row]
        let value: String
        switch id {
        case "name": value = r.name
        case "command": value = r.command
        case "status": value = r.status
        case "models": value = r.models
        case "type": value = r.type
        default: value = ""
        }
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: 12)
        if id == "status" { field.textColor = r.installed ? .systemGreen : .secondaryLabelColor }
        return field
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        removeButton.isEnabled = row >= 0 && row < rows.count && !rows[row].builtIn
    }

    // MARK: - Actions

    @objc private func addCLI() {
        let alert = NSAlert()
        alert.messageText = "Add an agent CLI"
        alert.informativeText = "Enter the command name. Sourcepad will run its --help to detect how to drive it and list its models."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        field.placeholderString = "e.g. aider, qwen, crush"
        alert.accessoryView = field
        alert.addButton(withTitle: "Probe")
        alert.addButton(withTitle: "Cancel")
        guard let win = view.window else { return }
        alert.beginSheetModal(for: win) { [weak self] resp in
            guard resp == .alertFirstButtonReturn else { return }
            let command = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else { return }
            self?.probeAndConfirm(command: command)
        }
    }

    private func probeAndConfirm(command: String) {
        guard let win = view.window else { return }
        // Probe off the main thread (spawns --help / models subprocesses).
        DispatchQueue.global(qos: .userInitiated).async {
            let draft = CLIProbe.probe(command: command)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let draft else {
                    self.warn(on: win, "“\(command)” not found", "No executable named “\(command)” is on your PATH or in the usual install locations.")
                    return
                }
                let confirm = NSAlert()
                confirm.messageText = draft.headlessSupported
                    ? "Add “\(command)”?"
                    : "“\(command)” may not support headless use"
                var info = draft.summary.joined(separator: "\n")
                info += "\n\nModels discovered: \(draft.spec.models.count)"
                if !draft.headlessSupported {
                    info += "\n\n⚠︎ No --prompt/--print flag was detected; this CLI may not run non-interactively."
                }
                confirm.informativeText = info
                confirm.addButton(withTitle: "Add")
                confirm.addButton(withTitle: "Cancel")
                confirm.beginSheetModal(for: win) { resp in
                    guard resp == .alertFirstButtonReturn else { return }
                    CLISpecStore.shared.upsert(draft.spec)
                    self.refreshRegistryAndTable()
                }
            }
        }
    }

    @objc private func removeCLI() {
        let row = table.selectedRow
        guard row >= 0, row < rows.count, !rows[row].builtIn else { return }
        CLISpecStore.shared.remove(id: rows[row].id)
        refreshRegistryAndTable()
    }

    @objc private func refreshModels() {
        refreshRegistryAndTable()
    }

    private func refreshRegistryAndTable() {
        AgentRegistry.shared.reloadCustomCLIs()
        AgentRegistry.shared.warmUp { [weak self] in
            self?.reload()
            NotificationCenter.default.post(name: .sourcepadAgentCLIsChanged, object: nil)
        }
    }

    private func warn(on win: NSWindow, _ text: String, _ info: String) {
        let a = NSAlert()
        a.messageText = text
        a.informativeText = info
        a.addButton(withTitle: "OK")
        a.beginSheetModal(for: win) { _ in }
    }
}

// MARK: - Standalone window

public final class AgentCLIManagerWindowController: NSWindowController {

    public static let shared = AgentCLIManagerWindowController()

    public init() {
        let pane = AgentCLIManagerViewController()
        let win = NSWindow(contentViewController: pane)
        win.styleMask = [.titled, .closable, .resizable]
        win.title = "Manage Agent CLIs"
        win.setContentSize(NSSize(width: 580, height: 400))
        win.minSize = NSSize(width: 520, height: 320)
        win.isReleasedWhenClosed = false
        super.init(window: win)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public func show() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
