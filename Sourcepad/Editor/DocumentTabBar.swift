// SPDX-License-Identifier: MIT
// Sourcepad — a slim VS Code–style document tab strip above the editor.
//
// Each editor window hosts one document, so this bar shows a single tab with
// the file's icon, name, a "modified" dot, and an always-visible close (×).
// It is shown ONLY when macOS isn't already drawing its native tab bar (i.e.
// when this window stands alone). As soon as two or more documents are grouped
// into native window tabs, those native tabs provide their own per-tab close
// button, so we hide this bar to avoid a redundant double strip.

import AppKit

public final class DocumentTabBar: NSView {

    public weak var document: TextDocument?
    /// Invoked when the user clicks the × (or middle-clicks the tab).
    public var onClose: (() -> Void)?

    private let tab = TabHitView()
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let modifiedDot = NSView()
    private let closeButton = NSButton()
    private let bottomBorder = NSView()

    private static let barHeight: CGFloat = 34

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.barHeight)
    }

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: Self.barHeight))
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - Build

    private func build() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        bottomBorder.wantsLayer = true
        bottomBorder.layer?.backgroundColor = NSColor.separatorColor.cgColor
        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBorder)

        // The tab "pill" sits flush to the bottom so it reads as connected to
        // the editor surface below it (VS Code's active-tab look).
        tab.wantsLayer = true
        tab.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        tab.translatesAutoresizingMaskIntoConstraints = false
        tab.onClick = { [weak self] in self?.focusEditor() }
        tab.onMiddleClick = { [weak self] in self?.onClose?() }
        addSubview(tab)

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        modifiedDot.wantsLayer = true
        modifiedDot.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
        modifiedDot.layer?.cornerRadius = 3
        modifiedDot.translatesAutoresizingMaskIntoConstraints = false

        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        if #available(macOS 11.0, *) {
            closeButton.image = NSImage(systemSymbolName: "xmark",
                                        accessibilityDescription: "Close")?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        }
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Close (⌘W)"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 4

        [icon, titleLabel, modifiedDot, closeButton].forEach { tab.addSubview($0) }

        NSLayoutConstraint.activate([
            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),

            tab.leadingAnchor.constraint(equalTo: leadingAnchor),
            tab.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            tab.bottomAnchor.constraint(equalTo: bottomAnchor),
            tab.widthAnchor.constraint(lessThanOrEqualToConstant: 280),

            icon.leadingAnchor.constraint(equalTo: tab.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: tab.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            titleLabel.centerYAnchor.constraint(equalTo: tab.centerYAnchor),

            modifiedDot.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            modifiedDot.centerYAnchor.constraint(equalTo: tab.centerYAnchor),
            modifiedDot.widthAnchor.constraint(equalToConstant: 6),
            modifiedDot.heightAnchor.constraint(equalToConstant: 6),

            closeButton.leadingAnchor.constraint(equalTo: modifiedDot.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: tab.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: tab.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: .sourcepadEditorUIDidUpdate, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Refresh

    /// Sync the tab's title, icon and modified indicator from the document.
    @objc public func refresh() {
        let name = document?.displayName ?? document?.fileURL?.lastPathComponent ?? "Untitled"
        titleLabel.stringValue = name

        if let url = document?.fileURL {
            icon.image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        }

        let edited = document?.isDocumentEdited ?? false
        modifiedDot.isHidden = !edited
        toolTipForTab()
    }

    private func toolTipForTab() {
        tab.toolTip = document?.fileURL?.path ?? document?.displayName
    }

    private func focusEditor() {
        guard let win = window else { return }
        if let editorVC = (win.windowController as? EditorWindowController)?.editorViewController,
           let paneView = editorVC.editorPane?.view {
            win.makeFirstResponder(paneView)
        }
    }

    @objc private func closeClicked() { onClose?() }

    // MARK: - Hover feedback on the close button

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let inSelf = convert(closeButton.bounds, from: closeButton)
        addTrackingArea(NSTrackingArea(rect: inSelf,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp],
                                       owner: self, userInfo: nil))
    }

    public override func mouseEntered(with event: NSEvent) {
        closeButton.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.20).cgColor
        closeButton.contentTintColor = .labelColor
    }

    public override func mouseExited(with event: NSEvent) {
        closeButton.layer?.backgroundColor = NSColor.clear.cgColor
        closeButton.contentTintColor = .secondaryLabelColor
    }
}

// MARK: - Click-catching tab body

/// A small NSView that reports left-clicks (focus) and middle-clicks (close)
/// without swallowing clicks meant for the close button.
private final class TabHitView: NSView {
    var onClick: (() -> Void)?
    var onMiddleClick: (() -> Void)?

    // The close button is an NSButton, so AppKit hit-tests and delivers its
    // clicks directly to it — this only fires for the tab body / label / icon.
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onMiddleClick?() }
    }
}
