// SPDX-License-Identifier: MIT
// Sourcepad — "Manage Agent CLIs" surface.
//
// A catalog of mainstream agent CLIs (claude, codex, opencode, gemini, aider,
// amp, qwen, goose, crush, Amazon Q, cursor-agent) with one-click INSTALL /
// UPDATE / UNINSTALL (headless, streamed progress via CLIInstaller), SIGN-IN
// (deferred to each CLI's own login), and CONFIGURE (default model per CLI). A
// prerequisites strip shows which package managers are present, and only install
// methods whose manager exists are offered. The user can still ADD any other CLI
// by command name — Sourcepad reads its --help to drive it (CLIProbe).
//
// The functional surface lives in `AgentCLIManagerViewController`, hosted both by
// the standalone `AgentCLIManagerWindowController` and, as a pane, inside the
// unified Settings window. Sheets attach to `view.window`, so the same controller
// behaves correctly in either host.

import AppKit

public extension Notification.Name {
    /// Posted after the set of agent CLIs changes (add/remove/install), so open
    /// panels can refresh their pickers.
    static let sourcepadAgentCLIsChanged = Notification.Name("SourcepadAgentCLIsChanged")
}

// MARK: - Card model + delegate

/// Everything a card needs to render its state, computed by the controller.
struct CLICardModel {
    let entry: CLICatalogEntry
    let installed: Bool
    let auth: CLIAuthStatus.Status
    let installMethods: [CLIInstallMethod]   // only those whose manager is present
    let updateAvailable: Bool
    let uninstallAvailable: Bool
    let modelCount: Int
}

protocol CLICardDelegate: AnyObject {
    func cardInstall(_ entry: CLICatalogEntry, method: CLIInstallMethod)
    func cardUpdate(_ entry: CLICatalogEntry)
    func cardUninstall(_ entry: CLICatalogEntry)
    func cardSignIn(_ entry: CLICatalogEntry)
    func cardConfigure(_ entry: CLICatalogEntry)
    func cardOpenConfig(_ entry: CLICatalogEntry)
    func cardOpenDocs(_ entry: CLICatalogEntry)
}

public final class AgentCLIManagerViewController: NSViewController {

    private let prereqStack = NSStackView()
    private let cardsStack = NSStackView()
    private let sandboxCheck = NSButton()
    private var installJob: CLIInstaller.Job?

    // MARK: - View

    public override func loadView() {
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false

        // Prereq strip.
        prereqStack.orientation = .horizontal
        prereqStack.spacing = 14
        prereqStack.alignment = .centerY
        prereqStack.translatesAutoresizingMaskIntoConstraints = false

        // Scrollable card list.
        cardsStack.orientation = .vertical
        cardsStack.alignment = .leading
        cardsStack.spacing = 8
        cardsStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = cardsStack
        let clip = scroll.contentView

        // Bottom controls.
        let add = NSButton(title: "Add custom CLI…", target: self, action: #selector(addCLI))
        add.bezelStyle = .rounded
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshTapped))
        refresh.bezelStyle = .rounded
        let buttons = NSStackView(views: [add, refresh, NSView()])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

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

        content.addSubview(prereqStack)
        content.addSubview(scroll)
        content.addSubview(sandboxCheck)
        content.addSubview(sandboxNote)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            prereqStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            prereqStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            prereqStack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),

            scroll.topAnchor.constraint(equalTo: prereqStack.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            cardsStack.topAnchor.constraint(equalTo: clip.topAnchor),
            cardsStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            cardsStack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            cardsStack.widthAnchor.constraint(equalTo: clip.widthAnchor),

            sandboxCheck.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            sandboxCheck.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            sandboxNote.topAnchor.constraint(equalTo: sandboxCheck.bottomAnchor, constant: 2),
            sandboxNote.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            sandboxNote.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            buttons.topAnchor.constraint(equalTo: sandboxNote.bottomAnchor, constant: 10),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])

        // Give the pane a sensible default size when shown standalone.
        content.widthAnchor.constraint(greaterThanOrEqualToConstant: 560).isActive = true
        self.view = content
    }

    @objc private func toggleSandbox(_ sender: NSButton) {
        Preferences.shared.agentSandboxEnabled = (sender.state == .on)
    }

    public override func viewWillAppear() {
        super.viewWillAppear()
        reload()
        // Models may still be warming up; refresh counts once they land.
        AgentRegistry.shared.warmUp { [weak self] in self?.reload() }
    }

    // MARK: - Build cards

    private func reload() {
        rebuildPrereqStrip()

        cardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let reg = AgentRegistry.shared
        let catalogIDs = Set(CLICatalog.entries.map { $0.id })

        // Catalog cards.
        cardsStack.addArrangedSubview(sectionLabel("Available agent CLIs"))
        for entry in CLICatalog.entries {
            let installed = AgentExecutable.locate(entry.command) != nil
            let methods = entry.installMethods.filter {
                $0.requiresCommand == nil || PackageManagers.isAvailable($0.requiresCommand!)
            }
            let model = CLICardModel(
                entry: entry,
                installed: installed,
                auth: installed ? CLIAuthStatus.status(for: entry.id) : .unknown,
                installMethods: methods,
                updateAvailable: entry.preferredUpdate(available: PackageManagers.isAvailable) != nil,
                uninstallAvailable: entry.preferredUninstall(available: PackageManagers.isAvailable) != nil,
                modelCount: reg.models(for: entry.id).count)
            let card = CLICard(model: model, delegate: self)
            cardsStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: cardsStack.widthAnchor).isActive = true
        }

        // Custom (user-added) CLIs not in the catalog.
        let customSpecs = CLISpecStore.shared.load().filter { !catalogIDs.contains($0.id) }
        if !customSpecs.isEmpty {
            cardsStack.addArrangedSubview(sectionLabel("Custom CLIs"))
            for spec in customSpecs {
                let installed = AgentExecutable.locate(spec.command) != nil
                let card = CustomCLICard(spec: spec, installed: installed,
                                         modelCount: reg.models(for: spec.id).count) { [weak self] id in
                    self?.removeCustom(id: id)
                }
                cardsStack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: cardsStack.widthAnchor).isActive = true
            }
        }
    }

    private func sectionLabel(_ text: String) -> NSView {
        let l = NSTextField(labelWithString: text.uppercased())
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        return l
    }

    private func rebuildPrereqStrip() {
        prereqStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let title = NSTextField(labelWithString: "Package managers:")
        title.font = .systemFont(ofSize: 11)
        title.textColor = .secondaryLabelColor
        prereqStack.addArrangedSubview(title)
        for (tool, available) in PackageManagers.status() {
            let dot = NSTextField(labelWithString: available ? "●" : "○")
            dot.font = .systemFont(ofSize: 11)
            dot.textColor = available ? .systemGreen : .tertiaryLabelColor
            let name = NSTextField(labelWithString: tool.label)
            name.font = .systemFont(ofSize: 11)
            name.textColor = available ? .labelColor : .secondaryLabelColor
            let item = NSStackView(views: [dot, name])
            item.spacing = 3
            if !available {
                let get = NSButton(title: "Get", target: self, action: #selector(openPrereqLink(_:)))
                get.bezelStyle = .inline
                get.controlSize = .mini
                get.toolTip = tool.installHintURL
                get.identifier = NSUserInterfaceItemIdentifier(tool.installHintURL)
                item.addArrangedSubview(get)
            }
            prereqStack.addArrangedSubview(item)
        }
    }

    @objc private func openPrereqLink(_ sender: NSButton) {
        if let s = sender.identifier?.rawValue, let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Refresh / registry

    @objc private func refreshTapped() { refreshRegistry() }

    private func refreshRegistry() {
        AgentRegistry.shared.reloadCustomCLIs()
        AgentRegistry.shared.warmUp { [weak self] in
            self?.reload()
            NotificationCenter.default.post(name: .sourcepadAgentCLIsChanged, object: nil)
        }
    }

    // MARK: - Add / remove custom CLIs

    @objc private func addCLI() {
        let alert = NSAlert()
        alert.messageText = "Add an agent CLI"
        alert.informativeText = "Enter the command name. Sourcepad will run its --help to detect how to drive it and list its models."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        field.placeholderString = "e.g. forge, kode, mycli"
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
        DispatchQueue.global(qos: .userInitiated).async {
            let draft = CLIProbe.probe(command: command)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let draft else {
                    self.warn("“\(command)” not found", "No executable named “\(command)” is on your PATH or in the usual install locations.")
                    return
                }
                let confirm = NSAlert()
                confirm.messageText = draft.headlessSupported ? "Add “\(command)”?" : "“\(command)” may not support headless use"
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
                    self.refreshRegistry()
                }
            }
        }
    }

    private func removeCustom(id: String) {
        CLISpecStore.shared.remove(id: id)
        refreshRegistry()
    }

    // MARK: - Helpers

    private func warn(_ text: String, _ info: String) {
        let a = NSAlert()
        a.messageText = text
        a.informativeText = info
        a.addButton(withTitle: "OK")
        if let win = view.window { a.beginSheetModal(for: win) { _ in } } else { a.runModal() }
    }
}

// MARK: - Card delegate (install / update / uninstall / sign-in / configure)

extension AgentCLIManagerViewController: CLICardDelegate {

    func cardInstall(_ entry: CLICatalogEntry, method: CLIInstallMethod) {
        runManaged(title: "Installing \(entry.name)…", command: method.shellCommand) { [weak self] ok in
            guard let self else { return }
            if ok { self.autoRegisterIfNeeded(entry) }
            self.refreshRegistry()
        }
    }

    func cardUpdate(_ entry: CLICatalogEntry) {
        guard let m = entry.preferredUpdate(available: PackageManagers.isAvailable) else { return }
        runManaged(title: "Updating \(entry.name)…", command: m.shellCommand) { [weak self] _ in self?.refreshRegistry() }
    }

    func cardUninstall(_ entry: CLICatalogEntry) {
        guard let m = entry.preferredUninstall(available: PackageManagers.isAvailable) else { return }
        let a = NSAlert()
        a.messageText = "Uninstall \(entry.name)?"
        a.informativeText = "This runs:\n\n    \(m.shellCommand)\n\nYour \(entry.name) sign-in and config are not removed."
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        let go = { self.runManaged(title: "Uninstalling \(entry.name)…", command: m.shellCommand) { [weak self] _ in self?.refreshRegistry() } }
        if let win = view.window { a.beginSheetModal(for: win) { if $0 == .alertFirstButtonReturn { go() } } }
        else if a.runModal() == .alertFirstButtonReturn { go() }
    }

    func cardSignIn(_ entry: CLICatalogEntry) {
        let auth = entry.auth
        switch auth.kind {
        case .browserOAuth:
            guard let cmd = auth.command else { return }
            runManaged(title: "Signing in to \(entry.name)…", command: cmd,
                       subtitle: "A browser window will open to complete sign-in.") { [weak self] _ in self?.refreshRegistry() }
        case .manual:
            warn("Sign in to \(entry.name)",
                 (auth.note ?? "Run the CLI's login command in a terminal.")
                 + (auth.command != nil ? "\n\nCommand:\n    \(auth.command!)" : ""))
        case .envKey:
            let v = auth.envVar ?? "API key"
            warn("Sign in to \(entry.name)",
                 (auth.note ?? "Set the provider API key in your shell environment.")
                 + "\n\nFor example, add to your shell profile:\n    export \(v)=…\n\nThen restart Sourcepad so the key is inherited.")
        }
    }

    func cardConfigure(_ entry: CLICatalogEntry) {
        let vc = CLIConfigureSheetController(entry: entry)
        vc.onSignIn = { [weak self] in self?.cardSignIn(entry) }
        presentAsSheet(vc)
    }

    func cardOpenConfig(_ entry: CLICatalogEntry) {
        guard let dir = entry.configDir else { return }
        let path = (dir as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            warn("No config folder yet", "\(entry.name) hasn't created \(dir) yet. Sign in or run it once first.")
        }
    }

    func cardOpenDocs(_ entry: CLICatalogEntry) {
        if let url = URL(string: entry.docsURL) { NSWorkspace.shared.open(url) }
    }

    /// After installing a catalog CLI that has no built-in adapter, auto-probe it
    /// so it becomes a usable agent immediately (no manual "Add" step).
    private func autoRegisterIfNeeded(_ entry: CLICatalogEntry) {
        let builtInIDs: Set<String> = ["claude", "codex", "opencode", "gemini", "agy", "mlx"]
        guard !builtInIDs.contains(entry.id),
              CLISpecStore.shared.load().first(where: { $0.id == entry.id }) == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let draft = CLIProbe.probe(command: entry.command), draft.headlessSupported {
                var spec = draft.spec
                spec.id = entry.id
                spec.displayName = entry.name
                CLISpecStore.shared.upsert(spec)
                DispatchQueue.main.async { AgentRegistry.shared.reloadCustomCLIs() }
            }
        }
    }

    /// Run a managed command in a streaming progress sheet, then re-probe.
    private func runManaged(title: String, command: String, subtitle: String? = nil,
                            completion: @escaping (Bool) -> Void) {
        let sheet = CLIProgressSheetController(title: title, subtitle: subtitle)
        sheet.onCancel = { [weak self] in self?.installJob?.cancel() }
        presentAsSheet(sheet)
        installJob = CLIInstaller.run(shellCommand: command,
                                      progress: { sheet.append($0) },
                                      completion: { [weak self] ok in
            sheet.finish(success: ok)
            self?.installJob = nil
            completion(ok)
        })
    }
}

// MARK: - Catalog card

/// A single agent-CLI card: icon, name, blurb, install + auth badges, and the
/// action buttons appropriate to its current state.
final class CLICard: NSView {

    private let model: CLICardModel
    private weak var delegate: CLICardDelegate?

    init(model: CLICardModel, delegate: CLICardDelegate) {
        self.model = model
        self.delegate = delegate
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        if let note = model.entry.disabledNote, !model.entry.enabled { toolTip = note }
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 8
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }

    private func build() {
        let e = model.entry

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        icon.contentTintColor = e.enabled ? .controlAccentColor : .tertiaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: e.name)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        let blurb = NSTextField(labelWithString: e.blurb)
        blurb.font = .systemFont(ofSize: 11)
        blurb.textColor = .secondaryLabelColor
        blurb.lineBreakMode = .byTruncatingTail

        let status = NSStackView(views: badges())
        status.orientation = .horizontal
        status.spacing = 10
        status.alignment = .centerY

        let textCol = NSStackView(views: [name, blurb, status])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2
        textCol.translatesAutoresizingMaskIntoConstraints = false

        let actions = actionStack()
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(icon); addSubview(textCol); addSubview(actions)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            textCol.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            textCol.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textCol.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),

            actions.leadingAnchor.constraint(greaterThanOrEqualTo: textCol.trailingAnchor, constant: 10),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: textCol.bottomAnchor, constant: 10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
    }

    private func badges() -> [NSView] {
        var out: [NSView] = []
        out.append(badge(model.installed ? "● Installed" : "○ Not installed",
                         color: model.installed ? .systemGreen : .secondaryLabelColor))
        if model.installed {
            switch model.auth {
            case .ready:
                out.append(badge("Signed in", color: .systemGreen))
            case .unknown:
                if model.entry.auth.command != nil || model.entry.auth.envVar != nil {
                    out.append(badge("Sign-in needed", color: .systemOrange))
                }
            }
            if model.modelCount > 0 {
                out.append(badge("\(model.modelCount) models", color: .secondaryLabelColor))
            }
        }
        return out
    }

    private func badge(_ text: String, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = color
        return l
    }

    private func actionStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6

        guard model.entry.enabled else {
            let l = NSTextField(labelWithString: "Unavailable")
            l.font = .systemFont(ofSize: 11)
            l.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(l)
            return stack
        }

        if !model.installed {
            stack.addArrangedSubview(installControl())
            return stack
        }

        // Installed: sign-in (if needed) + Configure + More.
        if model.auth == .unknown, (model.entry.auth.command != nil || model.entry.auth.envVar != nil) {
            stack.addArrangedSubview(button("Sign In", #selector(signInTapped)))
        }
        stack.addArrangedSubview(button("Configure", #selector(configureTapped)))
        stack.addArrangedSubview(button("⋯", #selector(moreTapped)))
        return stack
    }

    private func installControl() -> NSView {
        if model.installMethods.isEmpty {
            let b = button("Install", #selector(noop))
            b.isEnabled = false
            b.toolTip = "Requires Homebrew, npm, or pipx — install one from the strip above."
            return b
        }
        if model.installMethods.count == 1 {
            let b = button("Install", #selector(installFirst))
            b.toolTip = "via \(model.installMethods[0].label)"
            return b
        }
        let pop = NSPopUpButton(frame: .zero, pullsDown: true)
        pop.addItem(withTitle: "Install")
        for m in model.installMethods { pop.addItem(withTitle: "via \(m.label)") }
        pop.target = self
        pop.action = #selector(installPicked(_:))
        pop.bezelStyle = .rounded
        pop.translatesAutoresizingMaskIntoConstraints = false
        return pop
    }

    private func button(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        b.controlSize = .small
        return b
    }

    // MARK: Card actions

    @objc private func noop() {}
    @objc private func installFirst() {
        guard let m = model.installMethods.first else { return }
        delegate?.cardInstall(model.entry, method: m)
    }
    @objc private func installPicked(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem - 1   // item 0 is the "Install" title
        guard idx >= 0, idx < model.installMethods.count else { return }
        delegate?.cardInstall(model.entry, method: model.installMethods[idx])
    }
    @objc private func signInTapped() { delegate?.cardSignIn(model.entry) }
    @objc private func configureTapped() { delegate?.cardConfigure(model.entry) }
    @objc private func moreTapped(_ sender: NSButton) {
        let menu = NSMenu()
        if model.updateAvailable { menu.addItem(item("Update", #selector(updateTapped))) }
        if model.uninstallAvailable { menu.addItem(item("Uninstall…", #selector(uninstallTapped))) }
        if model.entry.auth.command != nil || model.entry.auth.envVar != nil {
            menu.addItem(item("Sign In…", #selector(signInTapped)))
        }
        menu.addItem(.separator())
        if model.entry.configDir != nil { menu.addItem(item("Open Config Folder", #selector(openConfigTapped))) }
        menu.addItem(item("Documentation", #selector(openDocsTapped)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }
    private func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        NSMenuItem(title: title, action: sel, keyEquivalent: "").with { $0.target = self }
    }
    @objc private func updateTapped() { delegate?.cardUpdate(model.entry) }
    @objc private func uninstallTapped() { delegate?.cardUninstall(model.entry) }
    @objc private func openConfigTapped() { delegate?.cardOpenConfig(model.entry) }
    @objc private func openDocsTapped() { delegate?.cardOpenDocs(model.entry) }
}

private extension NSMenuItem {
    func with(_ body: (NSMenuItem) -> Void) -> NSMenuItem { body(self); return self }
}

// MARK: - Custom CLI card (user-added, not in the catalog)

final class CustomCLICard: NSView {
    private let id: String
    init(spec: CLISpec, installed: Bool, modelCount: Int, onRemove: @escaping (String) -> Void) {
        self.id = spec.id
        self.onRemove = onRemove
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: spec.displayName)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        let sub = NSTextField(labelWithString:
            (installed ? "● Installed" : "○ Not found") + "   ·   \(spec.command)"
            + (modelCount > 0 ? "   ·   \(modelCount) models" : ""))
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        let textCol = NSStackView(views: [name, sub])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2
        textCol.translatesAutoresizingMaskIntoConstraints = false

        let remove = NSButton(title: "Remove", target: self, action: #selector(removeTapped))
        remove.bezelStyle = .rounded
        remove.controlSize = .small
        remove.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textCol); addSubview(remove)
        NSLayoutConstraint.activate([
            textCol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textCol.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textCol.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            remove.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            remove.centerYAnchor.constraint(equalTo: centerYAnchor),
            remove.leadingAnchor.constraint(greaterThanOrEqualTo: textCol.trailingAnchor, constant: 10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    private let onRemove: (String) -> Void

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 8
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    @objc private func removeTapped() { onRemove(id) }
}

// MARK: - Streaming progress sheet

/// A modal sheet showing live output of a managed install/update/sign-in
/// command, with a spinner and a Cancel button that becomes Done on completion.
final class CLIProgressSheetController: NSViewController {

    private let titleText: String
    private let subtitleText: String?
    private let spinner = NSProgressIndicator()
    private let textView = NSTextView()
    private let actionButton = NSButton()
    var onCancel: (() -> Void)?
    private var running = true

    init(title: String, subtitle: String?) {
        self.titleText = title
        self.subtitleText = subtitle
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: titleText)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        let subtitle = NSTextField(labelWithString: subtitleText ?? "")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.isHidden = (subtitleText == nil)
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        scroll.documentView = textView

        actionButton.title = "Cancel"
        actionButton.bezelStyle = .rounded
        actionButton.keyEquivalent = "\u{1b}"   // Esc
        actionButton.target = self
        actionButton.action = #selector(actionTapped)
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(title); root.addSubview(spinner); root.addSubview(subtitle)
        root.addSubview(scroll); root.addSubview(actionButton)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 580),
            root.heightAnchor.constraint(equalToConstant: 380),

            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            spinner.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scroll.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -12),

            actionButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            actionButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        self.view = root
    }

    func append(_ line: String) {
        let attr = NSAttributedString(string: line + "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ])
        textView.textStorage?.append(attr)
        textView.scrollToEndOfDocument(nil)
    }

    func finish(success: Bool) {
        running = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        actionButton.title = "Done"
        actionButton.keyEquivalent = "\r"
    }

    @objc private func actionTapped() {
        if running { onCancel?(); append("Cancelling…") }
        else { dismiss(self) }
    }
}

// MARK: - Configure sheet (per-CLI default model + quick links)

final class CLIConfigureSheetController: NSViewController {

    private let entry: CLICatalogEntry
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var models: [AgentModel] = []
    var onSignIn: (() -> Void)?

    init(entry: CLICatalogEntry) {
        self.entry = entry
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Configure \(entry.name)")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        models = AgentRegistry.shared.models(for: entry.id)
        modelPopup.addItem(withTitle: "Automatic")
        modelPopup.lastItem?.representedObject = nil
        for m in models {
            modelPopup.addItem(withTitle: m.displayName)
            modelPopup.lastItem?.representedObject = m.id
        }
        if let saved = Preferences.shared.agentDefaultModel(forCLI: entry.id),
           let idx = (0..<modelPopup.numberOfItems).first(where: { (modelPopup.item(at: $0)?.representedObject as? String) == saved }) {
            modelPopup.selectItem(at: idx)
        }
        let modelLabel = NSTextField(labelWithString: "Default model:")
        modelLabel.font = .systemFont(ofSize: 12)
        let modelRow = NSStackView(views: [modelLabel, modelPopup])
        modelRow.orientation = .horizontal
        modelRow.spacing = 8

        let authState = AgentExecutable.locate(entry.command) == nil ? "Not installed"
            : (CLIAuthStatus.status(for: entry.id) == .ready ? "Signed in" : "Sign-in not detected")
        let authLine = NSTextField(labelWithString: "Status: \(authState)")
        authLine.font = .systemFont(ofSize: 11)
        authLine.textColor = .secondaryLabelColor

        let note = NSTextField(wrappingLabelWithString: entry.auth.note ?? "")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.isHidden = (entry.auth.note == nil)

        var linkButtons: [NSView] = []
        if entry.auth.command != nil || entry.auth.envVar != nil {
            linkButtons.append(link("Sign In", #selector(signIn)))
        }
        if entry.configDir != nil { linkButtons.append(link("Open Config Folder", #selector(openConfig))) }
        linkButtons.append(link("Documentation", #selector(openDocs)))
        let links = NSStackView(views: linkButtons)
        links.orientation = .horizontal
        links.spacing = 8

        let done = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.translatesAutoresizingMaskIntoConstraints = false

        let col = NSStackView(views: [title, modelRow, authLine, note, links])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 12
        col.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(col); root.addSubview(done)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 440),
            col.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            col.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            col.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            done.topAnchor.constraint(equalTo: col.bottomAnchor, constant: 18),
            done.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            done.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        self.view = root
    }

    private func link(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .inline
        b.controlSize = .small
        return b
    }

    @objc private func signIn() { dismiss(self); onSignIn?() }
    @objc private func openConfig() {
        guard let dir = entry.configDir else { return }
        let path = (dir as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: path) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }
    @objc private func openDocs() {
        if let url = URL(string: entry.docsURL) { NSWorkspace.shared.open(url) }
    }
    @objc private func doneTapped() {
        let chosen = modelPopup.selectedItem?.representedObject as? String
        Preferences.shared.setAgentDefaultModel(chosen, forCLI: entry.id)
        NotificationCenter.default.post(name: .sourcepadAgentCLIsChanged, object: nil)
        dismiss(self)
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
