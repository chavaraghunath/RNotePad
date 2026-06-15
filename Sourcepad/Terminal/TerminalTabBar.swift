// SPDX-License-Identifier: MIT
// Sourcepad — tab strip for the bottom terminal panel.
//
// Data-driven (unlike SidebarTabBar's fixed enum) because terminal tabs come
// and go at runtime. Renders one button per session plus a trailing "+" to
// spawn a new shell. Each tab shows the session title and a small close (×)
// control that appears for the selected tab.

import AppKit

public struct TerminalTabModel {
    public let id: Int
    public let title: String
    public init(id: Int, title: String) { self.id = id; self.title = title }
}

public final class TerminalTabBar: NSView {

    public var onSelect: ((Int) -> Void)?
    public var onClose: ((Int) -> Void)?
    public var onNew: (() -> Void)?

    public static let barHeight: CGFloat = 28

    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let newButton = NSButton()
    private var tabs: [TerminalTabModel] = []
    private var selectedID: Int = -1

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
        stack.alignment = .centerY
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.documentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        newButton.bezelStyle = .regularSquare
        newButton.isBordered = false
        newButton.image = NSImage(systemSymbolName: "plus",
                                  accessibilityDescription: "New Terminal")
        newButton.imagePosition = .imageOnly
        newButton.target = self
        newButton.action = #selector(newTapped)
        newButton.toolTip = "New Terminal (⌃⇧`)"
        newButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newButton)

        // Bottom hairline separates the strip from the terminal content.
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        NSLayoutConstraint.activate([
            newButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            newButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newButton.widthAnchor.constraint(equalToConstant: 22),

            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: newButton.leadingAnchor, constant: -4),
            stack.heightAnchor.constraint(equalTo: scroll.heightAnchor),

            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Replace the tab set and selection, rebuilding the strip.
    public func update(tabs: [TerminalTabModel], selectedID: Int) {
        self.tabs = tabs
        self.selectedID = selectedID
        rebuild()
    }

    private func rebuild() {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        for tab in tabs {
            stack.addArrangedSubview(makeTab(tab))
        }
    }

    private func makeTab(_ tab: TerminalTabModel) -> NSView {
        let isSel = tab.id == selectedID
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.backgroundColor = isSel
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor
            : NSColor.clear.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: tab.title)
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = isSel ? .labelColor : .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let close = NSButton()
        close.isBordered = false
        close.bezelStyle = .regularSquare
        close.image = NSImage(systemSymbolName: "xmark",
                              accessibilityDescription: "Close Terminal")
        close.imagePosition = .imageOnly
        close.target = self
        close.action = #selector(closeTapped(_:))
        close.tag = tab.id
        close.translatesAutoresizingMaskIntoConstraints = false
        (close.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyDown

        let click = NSClickGestureRecognizer(target: self, action: #selector(tabClicked(_:)))
        container.addGestureRecognizer(click)
        container.identifier = NSUserInterfaceItemIdentifier("\(tab.id)")

        container.addSubview(label)
        container.addSubview(close)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            close.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            close.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            close.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 14),
            close.heightAnchor.constraint(equalToConstant: 14),
        ])
        return container
    }

    @objc private func tabClicked(_ g: NSClickGestureRecognizer) {
        guard let idStr = g.view?.identifier?.rawValue, let id = Int(idStr) else { return }
        onSelect?(id)
    }

    @objc private func closeTapped(_ sender: NSButton) {
        onClose?(sender.tag)
    }

    @objc private func newTapped() {
        onNew?()
    }
}
