// SPDX-License-Identifier: MIT
// Sourcepad — tab strip atop the sidebar.
//
// Phase 2 ships the strip with a single "Files" tab so the visible behavior
// stays identical to today. Later phases append Outline, Tasks, Tags, and
// Backlinks tabs as they come online — each is just a new SidebarTab case
// + a hosted NSView.

import AppKit

public enum SidebarTab: String, CaseIterable {
    case files = "Files"
    // Reserved for upcoming phases — listed here so resource conflicts
    // surface immediately if two phases pick the same name.
    case outline   = "Outline"
    case tasks     = "Tasks"
    case tags      = "Tags"
    case backlinks = "Backlinks"

    public var symbol: String {
        switch self {
        case .files:     return "folder"
        case .outline:   return "list.bullet.indent"
        case .tasks:     return "checkmark.circle"
        case .tags:      return "tag"
        case .backlinks: return "link"
        }
    }
}

public final class SidebarTabBar: NSView {

    /// Tabs to display. Setting this rebuilds the strip.
    public var tabs: [SidebarTab] = [.files] {
        didSet { rebuild() }
    }

    /// Currently-selected tab.
    public private(set) var selected: SidebarTab = .files

    /// Notification when the user clicks a tab.
    public var onSelect: ((SidebarTab) -> Void)?

    private let stack = NSStackView()
    private var buttons: [SidebarTab: NSButton] = [:]

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        rebuild()
    }

    public func select(_ tab: SidebarTab, notify: Bool = false) {
        guard tabs.contains(tab) else { return }
        selected = tab
        refreshSelection()
        if notify { onSelect?(tab) }
    }

    // MARK: - Rebuild

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        for t in tabs {
            let b = makeButton(for: t)
            buttons[t] = b
            stack.addArrangedSubview(b)
        }
        if !tabs.contains(selected), let first = tabs.first {
            selected = first
        }
        refreshSelection()
        isHidden = tabs.count < 2  // hide when there's only one tab
    }

    private func makeButton(for tab: SidebarTab) -> NSButton {
        let image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.rawValue) ?? NSImage()
        let button = NSButton(image: image, target: self, action: #selector(tabClicked(_:)))
        button.isBordered = false
        button.bezelStyle = .recessed
        button.imagePosition = .imageOnly
        button.toolTip = tab.rawValue
        button.identifier = NSUserInterfaceItemIdentifier(tab.rawValue)
        button.setButtonType(.momentaryChange)
        return button
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let tab = SidebarTab(rawValue: id) else { return }
        select(tab, notify: true)
    }

    private func refreshSelection() {
        for (tab, button) in buttons {
            button.contentTintColor = (tab == selected) ? .controlAccentColor : .secondaryLabelColor
        }
    }
}
