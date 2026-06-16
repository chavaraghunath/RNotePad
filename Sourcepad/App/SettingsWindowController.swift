// SPDX-License-Identifier: MIT
// Sourcepad — the unified Settings window.
//
// A single sidebar-style home (System-Settings / VSCode style) that replaces
// the formerly scattered preference surfaces. Each row in the sidebar maps to a
// `SettingsSection` whose `make` closure vends the pane's view controller; the
// split view swaps the detail pane on selection. Adding a future pane is one
// entry in `sections` — no other wiring.

import AppKit

/// One sidebar row + the pane it shows.
public struct SettingsSection {
    public let id: String
    public let title: String
    public let symbol: String              // SF Symbol name
    public let make: () -> NSViewController
    public init(id: String, title: String, symbol: String, make: @escaping () -> NSViewController) {
        self.id = id; self.title = title; self.symbol = symbol; self.make = make
    }
}

public final class SettingsWindowController: NSWindowController {

    public static let shared: SettingsWindowController = {
        let split = SettingsSplitViewController()
        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Settings"
        window.titlebarAppearsTransparent = false
        window.setContentSize(NSSize(width: 760, height: 520))
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SourcepadSettingsWindow")
        window.center()
        return SettingsWindowController(window: window)
    }()

    private var split: SettingsSplitViewController? { contentViewController as? SettingsSplitViewController }

    public func showSettings(selecting id: String? = nil) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let id { split?.select(id: id) }
    }

    @objc public func showFromMenu(_ sender: Any?) { showSettings() }
}

// MARK: - Split (sidebar + detail)

final class SettingsSplitViewController: NSSplitViewController {

    /// The catalogue of panes. Later phases append rows here.
    private let sections: [SettingsSection] = [
        SettingsSection(id: "general",    title: "General",    symbol: "gearshape")        { SettingsGeneralPane() },
        SettingsSection(id: "editor",     title: "Editor",     symbol: "textformat")       { SettingsEditorPane() },
        SettingsSection(id: "appearance", title: "Appearance", symbol: "paintpalette")     { SettingsAppearancePane() },
        SettingsSection(id: "agents",     title: "Agent CLIs", symbol: "terminal")         { AgentCLIManagerViewController() },
        SettingsSection(id: "mlx",        title: "MLX Models", symbol: "cpu")               { MLXModelsViewController() },
        SettingsSection(id: "mcp",        title: "MCP",        symbol: "point.3.connected.trianglepath.dotted") { SettingsMCPPane() },
    ]

    private lazy var sidebar = SettingsSidebarViewController(sections: sections)
    private let detail = SettingsDetailViewController()
    private var paneCache: [String: NSViewController] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 240
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)

        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 420
        addSplitViewItem(detailItem)

        sidebar.onSelect = { [weak self] index in self?.show(index: index) }
        // Open on the first section.
        sidebar.selectRow(0)
        show(index: 0)
    }

    func select(id: String) {
        guard let idx = sections.firstIndex(where: { $0.id == id }) else { return }
        sidebar.selectRow(idx)
        show(index: idx)
    }

    private func show(index: Int) {
        guard index >= 0, index < sections.count else { return }
        let section = sections[index]
        let pane = paneCache[section.id] ?? {
            let vc = section.make()
            paneCache[section.id] = vc
            return vc
        }()
        detail.embed(pane, title: section.title)
        view.window?.title = "Settings — \(section.title)"
    }
}

// MARK: - Sidebar

final class SettingsSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let sections: [SettingsSection]
    private let table = NSTableView()
    var onSelect: ((Int) -> Void)?

    init(sections: [SettingsSection]) {
        self.sections = sections
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func loadView() {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.backgroundColor = .clear
        if #available(macOS 11.0, *) {
            table.style = .sourceList
        } else {
            table.selectionHighlightStyle = .sourceList
        }
        table.rowSizeStyle = .medium
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = false
        table.intercellSpacing = NSSize(width: 0, height: 4)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        self.view = scroll
    }

    func selectRow(_ index: Int) {
        guard index >= 0, index < sections.count else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let s = sections[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: s.symbol, accessibilityDescription: s.title)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextField(labelWithString: s.title)
        text.font = .systemFont(ofSize: 13)
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        if row >= 0 { onSelect?(row) }
    }
}

// MARK: - Detail container

final class SettingsDetailViewController: NSViewController {

    private let titleLabel = NSTextField(labelWithString: "")
    private let container = NSView()
    private weak var current: NSViewController?

    override func loadView() {
        let root = NSView()
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleLabel)
        root.addSubview(container)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -22),
            container.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        self.view = root
    }

    func embed(_ vc: NSViewController, title: String) {
        titleLabel.stringValue = title
        if let current {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: container.topAnchor),
            vc.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            vc.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        current = vc
    }
}

// MARK: - Shared pane scaffolding

/// Base class giving panes a left-aligned vertical form with a trailing-aligned
/// label grid, matching macOS Settings conventions.
public class SettingsPaneViewController: NSViewController {

    /// Subclasses return their rows as (label, control) pairs. An empty label
    /// makes a full-width row (used for standalone checkboxes / notes).
    public func rows() -> [(String, NSView)] { [] }

    public override func loadView() {
        let root = NSView()
        var gridRows: [[NSView]] = []
        for (label, control) in rows() {
            let l = NSTextField(labelWithString: label)
            l.font = .systemFont(ofSize: 13)
            l.textColor = label.isEmpty ? .clear : .labelColor
            gridRows.append([l, control])
        }
        let grid = NSGridView(views: gridRows)
        grid.columnSpacing = 14
        grid.rowSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -22),
        ])
        self.view = root
    }

    // Helpers shared by panes.
    func checkbox(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: action)
        return b
    }
}

// MARK: - General pane

final class SettingsGeneralPane: SettingsPaneViewController {

    private let externalChange = NSSegmentedControl(labels: ["Prompt", "Auto-reload", "Ignore"],
                                                    trackingMode: .selectOne, target: nil, action: nil)
    private lazy var gitGutter   = checkbox("Show git change markers in the gutter", action: #selector(toggleGitGutter(_:)))
    private lazy var hiddenFiles = checkbox("Show hidden files in the sidebar", action: #selector(toggleHidden(_:)))
    private lazy var indexer     = checkbox("Run the background project indexer", action: #selector(toggleIndexer(_:)))

    override func rows() -> [(String, NSView)] {
        externalChange.target = self
        externalChange.action = #selector(externalChanged(_:))
        return [
            ("When a file changes on disk", externalChange),
            ("", gitGutter),
            ("", hiddenFiles),
            ("", indexer),
        ]
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let p = Preferences.shared
        switch p.externalChangeBehavior {
        case .prompt:     externalChange.selectedSegment = 0
        case .autoReload: externalChange.selectedSegment = 1
        case .ignore:     externalChange.selectedSegment = 2
        }
        gitGutter.state   = p.gitGutterEnabled ? .on : .off
        hiddenFiles.state = p.showHiddenFilesInSidebar ? .on : .off
        indexer.state     = p.indexerEnabled ? .on : .off
    }

    @objc private func externalChanged(_ s: NSSegmentedControl) {
        Preferences.shared.externalChangeBehavior =
            [.prompt, .autoReload, .ignore][s.selectedSegment]
    }
    @objc private func toggleGitGutter(_ s: NSButton) { Preferences.shared.gitGutterEnabled = (s.state == .on) }
    @objc private func toggleHidden(_ s: NSButton)    { Preferences.shared.showHiddenFilesInSidebar = (s.state == .on) }
    @objc private func toggleIndexer(_ s: NSButton)   { Preferences.shared.indexerEnabled = (s.state == .on) }
}

// MARK: - Editor pane

final class SettingsEditorPane: SettingsPaneViewController, NSFontChanging {

    private let fontDisplay = NSTextField(labelWithString: "")
    private let tabWidthStepper = NSStepper()
    private let tabWidthValue = NSTextField()
    private lazy var lineNumbers = checkbox("Show line numbers in the margin", action: #selector(toggleLineNumbers(_:)))
    private lazy var useSpaces   = checkbox("Insert spaces when pressing Tab", action: #selector(toggleUseSpaces(_:)))
    private lazy var wordWrap    = checkbox("Wrap long lines", action: #selector(toggleWordWrap(_:)))
    private lazy var indentGuides = checkbox("Show indent guides", action: #selector(toggleIndentGuides(_:)))
    private lazy var invisibles  = checkbox("Show invisible characters", action: #selector(toggleInvisibles(_:)))
    private lazy var trimOnSave  = checkbox("Trim trailing whitespace on save", action: #selector(toggleTrim(_:)))
    private lazy var autocomplete = checkbox("Enable autocomplete suggestions", action: #selector(toggleAutocomplete(_:)))

    override func rows() -> [(String, NSView)] {
        fontDisplay.font = .systemFont(ofSize: 12)
        fontDisplay.textColor = .secondaryLabelColor
        let pickFont = NSButton(title: "Choose…", target: self, action: #selector(pickFont(_:)))
        pickFont.bezelStyle = .rounded
        let fontRow = NSStackView(views: [fontDisplay, pickFont])
        fontRow.orientation = .horizontal
        fontRow.spacing = 8

        tabWidthStepper.minValue = 1; tabWidthStepper.maxValue = 16
        tabWidthStepper.target = self; tabWidthStepper.action = #selector(tabStepperChanged(_:))
        tabWidthValue.isEditable = true; tabWidthValue.isBezeled = true
        tabWidthValue.alignment = .right
        tabWidthValue.target = self; tabWidthValue.action = #selector(tabValueChanged(_:))
        tabWidthValue.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let tabRow = NSStackView(views: [tabWidthValue, tabWidthStepper])
        tabRow.orientation = .horizontal; tabRow.spacing = 4

        return [
            ("Font", fontRow),
            ("Tab width", tabRow),
            ("", lineNumbers),
            ("", useSpaces),
            ("", wordWrap),
            ("", indentGuides),
            ("", invisibles),
            ("", trimOnSave),
            ("", autocomplete),
        ]
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let p = Preferences.shared
        fontDisplay.stringValue = "\(p.fontName) — \(Int(p.fontSize)) pt"
        tabWidthValue.integerValue = p.tabWidth
        tabWidthStepper.integerValue = p.tabWidth
        lineNumbers.state = p.showLineNumbers ? .on : .off
        useSpaces.state = p.useSpacesForTabs ? .on : .off
        wordWrap.state = p.wordWrap ? .on : .off
        indentGuides.state = p.indentGuides ? .on : .off
        invisibles.state = p.showInvisibles ? .on : .off
        trimOnSave.state = p.trimTrailingWhitespaceOnSave ? .on : .off
        autocomplete.state = p.autocompleteEnabled ? .on : .off
    }

    @objc private func pickFont(_ sender: Any?) {
        view.window?.makeFirstResponder(self)
        let panel = NSFontPanel.shared
        panel.setPanelFont(NSFont(name: Preferences.shared.fontName, size: Preferences.shared.fontSize)
                           ?? NSFont.systemFont(ofSize: 13), isMultiple: false)
        panel.makeKeyAndOrderFront(nil)
    }
    func changeFont(_ sender: NSFontManager?) {
        guard let sender else { return }
        let current = NSFont(name: Preferences.shared.fontName, size: Preferences.shared.fontSize)
            ?? NSFont.userFixedPitchFont(ofSize: 13)!
        let newFont = sender.convert(current)
        Preferences.shared.fontName = newFont.fontName
        Preferences.shared.fontSize = newFont.pointSize
        fontDisplay.stringValue = "\(newFont.fontName) — \(Int(newFont.pointSize)) pt"
    }
    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask { [.face, .collection, .size] }

    @objc private func tabStepperChanged(_ s: NSStepper) {
        Preferences.shared.tabWidth = s.integerValue
        tabWidthValue.integerValue = s.integerValue
    }
    @objc private func tabValueChanged(_ s: NSTextField) {
        let v = max(1, min(16, s.integerValue))
        Preferences.shared.tabWidth = v
        tabWidthStepper.integerValue = v
        s.integerValue = v
    }
    @objc private func toggleLineNumbers(_ s: NSButton)  { Preferences.shared.showLineNumbers = (s.state == .on) }
    @objc private func toggleUseSpaces(_ s: NSButton)    { Preferences.shared.useSpacesForTabs = (s.state == .on) }
    @objc private func toggleWordWrap(_ s: NSButton)     { Preferences.shared.wordWrap = (s.state == .on) }
    @objc private func toggleIndentGuides(_ s: NSButton) { Preferences.shared.indentGuides = (s.state == .on) }
    @objc private func toggleInvisibles(_ s: NSButton)   { Preferences.shared.showInvisibles = (s.state == .on) }
    @objc private func toggleTrim(_ s: NSButton)         { Preferences.shared.trimTrailingWhitespaceOnSave = (s.state == .on) }
    @objc private func toggleAutocomplete(_ s: NSButton) { Preferences.shared.autocompleteEnabled = (s.state == .on) }
}

// MARK: - Appearance pane

final class SettingsAppearancePane: SettingsPaneViewController {

    private let theme = NSSegmentedControl(labels: ["System", "Light", "Dark"],
                                           trackingMode: .selectOne, target: nil, action: nil)

    override func rows() -> [(String, NSView)] {
        theme.target = self
        theme.action = #selector(themeChanged(_:))
        return [("Theme", theme)]
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        switch UserDefaults.standard.string(forKey: "Sourcepad.themeOverride") {
        case NSAppearance.Name.aqua.rawValue:     theme.selectedSegment = 1
        case NSAppearance.Name.darkAqua.rawValue: theme.selectedSegment = 2
        default:                                  theme.selectedSegment = 0
        }
    }

    @objc private func themeChanged(_ s: NSSegmentedControl) {
        let value: String?
        switch s.selectedSegment {
        case 1: value = NSAppearance.Name.aqua.rawValue
        case 2: value = NSAppearance.Name.darkAqua.rawValue
        default: value = nil
        }
        UserDefaults.standard.set(value, forKey: "Sourcepad.themeOverride")
        if let value, let name = NSAppearance(named: NSAppearance.Name(rawValue: value)) {
            NSApp.appearance = name
        } else {
            NSApp.appearance = nil
        }
    }
}
