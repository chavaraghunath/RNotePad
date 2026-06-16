// SPDX-License-Identifier: MIT
// Sourcepad — the "MLX Models" pane (Docker-Models style).
//
// Browse the live mlx-community registry (Hugging Face Hub API), see download
// size + popularity, and Pull / Remove models. If the MLX runtime isn't present,
// a one-time "Install MLX runtime" step creates the managed venv. Pulled models
// then appear under the "MLX (local)" agent in the panel's picker.

import AppKit

public final class MLXModelsWindowController: NSWindowController,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    public static let shared = MLXModelsWindowController()

    private let statusLabel = NSTextField(labelWithString: "")
    private let installButton = NSButton()
    private let search = NSSearchField()
    private let table = NSTableView()
    private let progress = NSTextField(labelWithString: "")

    private var models: [MLXModelInfo] = []
    private var installed = Set<String>()
    private var sizes: [String: Int64] = [:]
    private var pulling = Set<String>()
    private var pullProgress: [String: String] = [:]   // modelID -> latest progress line

    public init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                           styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.title = "MLX Models"
        win.minSize = NSSize(width: 520, height: 360)
        super.init(window: win)
        build()
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public func show() {
        refreshInstalledState()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if MLXEnvironment.isInstalled { loadRegistry(query: nil) }
    }

    // MARK: - Build

    private func build() {
        guard let content = window?.contentView else { return }

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        installButton.title = "Install MLX runtime"
        installButton.bezelStyle = .rounded
        installButton.target = self
        installButton.action = #selector(installRuntime)
        installButton.translatesAutoresizingMaskIntoConstraints = false

        search.placeholderString = "Search mlx-community models…"
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false

        for (idf, title, w) in [("name", "Model", 280), ("size", "Size", 80),
                                ("downloads", "Downloads", 90), ("action", "", 90)] as [(String, String, CGFloat)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(idf))
            c.title = title; c.width = w
            // Make the data columns sortable by clicking the header.
            if idf != "action" {
                c.sortDescriptorPrototype = NSSortDescriptor(key: idf, ascending: idf == "name")
            }
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        progress.font = .systemFont(ofSize: 10)
        progress.textColor = .secondaryLabelColor
        progress.lineBreakMode = .byTruncatingTail
        progress.maximumNumberOfLines = 4   // show several concurrent downloads at once
        progress.usesSingleLineMode = false
        progress.translatesAutoresizingMaskIntoConstraints = false

        let done = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.translatesAutoresizingMaskIntoConstraints = false
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshTapped))
        refresh.bezelStyle = .rounded
        refresh.translatesAutoresizingMaskIntoConstraints = false

        [statusLabel, installButton, search, scroll, progress, done, refresh].forEach { content.addSubview($0) }

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            installButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            installButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            search.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            progress.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            progress.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            progress.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            refresh.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            refresh.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 8),
            refresh.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            done.centerYAnchor.constraint(equalTo: refresh.centerYAnchor),
        ])
    }

    // MARK: - State

    private func refreshInstalledState() {
        installed = Set(MLXModelManager.installedModelIDs())
        let ready = MLXEnvironment.isInstalled
        installButton.isHidden = ready
        statusLabel.stringValue = ready
            ? "MLX runtime ready · \(installed.count) model\(installed.count == 1 ? "" : "s") installed"
            : (MLXEnvironment.isAppleSilicon ? "MLX runtime not installed."
                                             : "MLX requires Apple Silicon.")
        table.reloadData()
    }

    private func loadRegistry(query: String?) {
        if pulling.isEmpty { progress.stringValue = "Loading models…" }
        MLXModelRegistry.search(query: query) { [weak self] list in
            guard let self else { return }
            self.models = list
            if self.pulling.isEmpty {
                self.progress.stringValue = list.isEmpty ? "No models found." : ""
            } else {
                self.renderProgress()      // keep in-flight downloads visible across Refresh
            }
            self.applySort()               // keep the active column sort sticky
            self.table.reloadData()
            // Lazily fetch sizes and fill them in as they arrive.
            for m in list where self.sizes[m.id] == nil {
                MLXModelRegistry.fetchSize(modelID: m.id) { [weak self] size in
                    guard let self, let size else { return }
                    self.sizes[m.id] = size
                    if self.table.sortDescriptors.first?.key == "size" {
                        self.applySort(); self.table.reloadData()   // re-sort as sizes arrive
                    } else if let row = self.models.firstIndex(where: { $0.id == m.id }) {
                        self.table.reloadData(forRowIndexes: [row], columnIndexes: IndexSet(integer: 1))
                    }
                }
            }
        }
    }

    // MARK: - Sorting

    public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        applySort()
        table.reloadData()
    }

    /// Sort `models` by the active column header (Model / Size / Downloads).
    private func applySort() {
        guard let sd = table.sortDescriptors.first, let key = sd.key else { return }
        let asc = sd.ascending
        switch key {
        case "name":
            models.sort {
                let r = $0.name.localizedCaseInsensitiveCompare($1.name)
                return asc ? r == .orderedAscending : r == .orderedDescending
            }
        case "downloads":
            models.sort { asc ? $0.downloads < $1.downloads : $0.downloads > $1.downloads }
        case "size":
            // Unknown sizes sort last in either direction.
            models.sort {
                let a = sizes[$0.id] ?? (asc ? Int64.max : -1)
                let b = sizes[$1.id] ?? (asc ? Int64.max : -1)
                return asc ? a < b : a > b
            }
        default:
            break
        }
    }

    // MARK: - Download status

    /// Render every in-flight download (not just the last one to report a line),
    /// so two or more concurrent pulls are all visible. Driven off
    /// `pulling`/`pullProgress`, which persist across registry reloads — so the
    /// status survives a Refresh and stays put until each download completes.
    private func renderProgress() {
        guard !pulling.isEmpty else { return }
        progress.stringValue = pulling.sorted().map { id in
            "\((id as NSString).lastPathComponent) — \(pullProgress[id] ?? "starting…")"
        }.joined(separator: "\n")
    }

    // MARK: - Table

    public func numberOfRows(in tableView: NSTableView) -> Int { models.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < models.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let m = models[row]
        switch id {
        case "name":
            return label(m.name)
        case "size":
            return label(sizes[m.id].map(MLXModelRegistry.formatSize) ?? "…")
        case "downloads":
            return label(m.downloads >= 1000 ? String(format: "%.0fk", Double(m.downloads) / 1000) : "\(m.downloads)")
        case "action":
            let b = NSButton()
            b.controlSize = .small
            b.bezelStyle = .rounded
            b.font = .systemFont(ofSize: 11)
            b.target = self
            if pulling.contains(m.id) {
                b.title = "Pulling…"; b.isEnabled = false
            } else if installed.contains(m.id) {
                b.title = "Remove"; b.action = #selector(removeRow(_:))
            } else {
                b.title = "Pull"; b.action = #selector(pullRow(_:))
            }
            return b
        default: return nil
        }
    }

    private func label(_ s: String) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = .systemFont(ofSize: 12)
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    private func modelID(forButton b: NSButton) -> String? {
        let row = table.row(for: b)
        return (row >= 0 && row < models.count) ? models[row].id : nil
    }

    // MARK: - Actions

    @objc private func pullRow(_ sender: NSButton) {
        guard let id = modelID(forButton: sender) else { return }
        let sizeText = sizes[id].map { " (~\(MLXModelRegistry.formatSize($0)))" } ?? ""
        let alert = NSAlert()
        alert.messageText = "Download \((id as NSString).lastPathComponent)?"
        alert.informativeText = "This downloads the model\(sizeText) to your local cache."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        guard let win = window else { return }
        alert.beginSheetModal(for: win) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self else { return }
            self.pulling.insert(id)
            self.pullProgress[id] = "starting…"
            self.renderProgress()
            self.table.reloadData()
            MLXModelManager.pull(modelID: id, progress: { [weak self] line in
                guard let self else { return }
                self.pullProgress[id] = line
                self.renderProgress()
            }, completion: { [weak self] ok in
                guard let self else { return }
                self.pulling.remove(id)
                self.pullProgress[id] = nil
                if self.pulling.isEmpty {
                    self.progress.stringValue = ok ? "Installed \((id as NSString).lastPathComponent)." : "Download failed."
                } else {
                    self.renderProgress()   // other downloads are still running
                }
                self.refreshInstalledState()
                self.notifyChanged()
            })
        }
    }

    @objc private func removeRow(_ sender: NSButton) {
        guard let id = modelID(forButton: sender) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \((id as NSString).lastPathComponent)?"
        alert.informativeText = "Deletes the downloaded model from your local cache."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard let win = window else { return }
        alert.beginSheetModal(for: win) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self else { return }
            MLXModelManager.remove(modelID: id)
            self.progress.stringValue = "Removed \((id as NSString).lastPathComponent)."
            self.refreshInstalledState()
            self.notifyChanged()
        }
    }

    @objc private func installRuntime() {
        guard MLXEnvironment.isAppleSilicon else { return }
        installButton.isEnabled = false
        progress.stringValue = "Setting up MLX runtime…"
        MLXEnvironment.install(progress: { [weak self] line in
            self?.progress.stringValue = line
        }, completion: { [weak self] ok in
            guard let self else { return }
            self.installButton.isEnabled = true
            self.refreshInstalledState()
            if ok { self.loadRegistry(query: self.search.stringValue); self.notifyChanged() }
        })
    }

    @objc private func refreshTapped() {
        refreshInstalledState()
        if MLXEnvironment.isInstalled { loadRegistry(query: search.stringValue) }
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard MLXEnvironment.isInstalled else { return }
        loadRegistry(query: search.stringValue)
    }

    @objc private func closeWindow() { window?.close() }

    private func notifyChanged() {
        AgentRegistry.shared.reloadCustomCLIs()
        AgentRegistry.shared.warmUp {
            NotificationCenter.default.post(name: .sourcepadAgentCLIsChanged, object: nil)
        }
    }
}
