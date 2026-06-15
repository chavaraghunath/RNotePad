// SPDX-License-Identifier: MIT
// Sourcepad — one chat message bubble.
//
// A full-width row that holds an inner rounded bubble pinned leading
// (assistant / system) or trailing (user), capped at ~82% of the row width.
// The body is a selectable, wrapping label rendering markdown. The assistant
// bubble is mutated in place while a turn streams (appendDelta / setText).

import AppKit

public final class AgentMessageBubble: NSView {

    public enum Role { case user, assistant, system }

    private let role: Role
    private let label = NSTextField(labelWithString: "")
    private let bubble = NSView()
    private var rawText: String
    private var widthCap: NSLayoutConstraint!

    public init(role: Role, text: String) {
        self.role = role
        self.rawText = text
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func setup() {
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 10
        bubble.layer?.backgroundColor = backgroundColor.cgColor
        bubble.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubble)

        label.isSelectable = true
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)

        let pad: CGFloat = 10
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: pad),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -pad),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: pad - 2),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -(pad - 2)),

            bubble.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            bubble.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])

        widthCap = bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 600)
        widthCap.isActive = true

        switch role {
        case .user:
            bubble.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10).isActive = true
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 36).isActive = true
        case .assistant, .system:
            bubble.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10).isActive = true
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -36).isActive = true
        }
    }

    public override func layout() {
        super.layout()
        // Cap bubble width to ~82% of the row and tell the label how wide it may
        // wrap so its intrinsic height is correct.
        let cap = max(120, bounds.width * 0.82)
        widthCap.constant = cap
        label.preferredMaxLayoutWidth = cap - 20
    }

    // MARK: - Content

    public func setText(_ text: String) {
        rawText = text
        render()
    }

    public func appendDelta(_ delta: String) {
        rawText += delta
        render()
    }

    public var text: String { rawText }

    private func render() {
        // Resolve dynamic system colors (.labelColor etc.) under THIS view's
        // effective appearance so the baked attributed-string colors match the
        // appearance the bubble is actually drawn in. Without this, a string
        // rendered while dark would carry white text and vanish in light mode.
        var attributed = NSAttributedString()
        let resolvedTextColor = textColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            attributed = AgentMarkdown.render(rawText, baseFont: bodyFont,
                                              textColor: resolvedTextColor)
        }
        label.attributedStringValue = attributed
        needsLayout = true
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        render()   // re-bake colors for the new appearance
    }

    // MARK: - Styling

    private var bodyFont: NSFont {
        let size = max(11, min(15, Preferences.shared.fontSize - 1))
        return .systemFont(ofSize: size)
    }

    private var textColor: NSColor {
        switch role {
        case .user:           return .white
        case .assistant:      return .labelColor
        case .system:         return .systemRed
        }
    }

    private var backgroundColor: NSColor {
        switch role {
        case .user:           return .controlAccentColor
        case .assistant:      return NSColor.textColor.withAlphaComponent(0.06)
        case .system:         return NSColor.systemRed.withAlphaComponent(0.10)
        }
    }

    public override func updateLayer() {
        bubble.layer?.backgroundColor = backgroundColor.cgColor
    }
}
