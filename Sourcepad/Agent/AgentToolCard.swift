// SPDX-License-Identifier: MIT
// Sourcepad — a tool-call card in the agent transcript.
//
// Renders one tool the agent invoked (edit / create / read / shell / search /
// web): an SF Symbol by kind, a title ("Edit Foo.swift", "$ npm test"), a
// status dot (running → ok/failed), and an optional collapsible monospaced
// detail (command / diff / output). Updated in place when the matching
// tool-result arrives.

import AppKit

public final class AgentToolCard: NSView {

    public enum Status { case running, ok, failed }

    public let toolID: String
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let riskBadge = NSTextField(labelWithString: "")
    private let statusDot = NSTextField(labelWithString: "")
    private let disclosure = NSButton()
    private var riskTier: AgentPolicy.Risk = .allow
    private let detailLabel = NSTextField(labelWithString: "")
    private let card = NSView()
    private var detailText: String?
    private var detailShown = false
    private var detailHeight: NSLayoutConstraint!

    public init(toolCall: AgentToolCall) {
        self.toolID = toolCall.id
        self.detailText = toolCall.detail
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(toolCall)
        setStatus(.running, output: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build(_ tc: AgentToolCall) {
        card.wantsLayer = true
        card.layer?.cornerRadius = 7
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        icon.image = NSImage(systemSymbolName: Self.symbol(for: tc.kind), accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = tc.title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        riskBadge.font = .systemFont(ofSize: 9, weight: .semibold)
        riskBadge.translatesAutoresizingMaskIntoConstraints = false
        riskBadge.wantsLayer = true
        riskBadge.drawsBackground = false
        riskBadge.isHidden = true
        riskBadge.setContentHuggingPriority(.required, for: .horizontal)
        riskBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        statusDot.font = .systemFont(ofSize: 11)
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        disclosure.title = ""
        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.onOff)
        disclosure.translatesAutoresizingMaskIntoConstraints = false
        disclosure.target = self
        disclosure.action = #selector(toggleDetail)
        disclosure.isHidden = (detailText?.isEmpty ?? true)

        detailLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 12
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.stringValue = detailText ?? ""
        detailLabel.isHidden = true

        let head = NSStackView(views: [icon, titleLabel, riskBadge, statusDot, disclosure])
        head.orientation = .horizontal
        head.spacing = 6
        head.alignment = .centerY
        head.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(head)
        card.addSubview(detailLabel)

        detailHeight = detailLabel.heightAnchor.constraint(equalToConstant: 0)
        detailHeight.isActive = true

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            card.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),

            head.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            head.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            head.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            icon.widthAnchor.constraint(equalToConstant: 14),

            detailLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            detailLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            detailLabel.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 4),
            detailLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
        ])
        applyColors()
    }

    @objc private func toggleDetail() {
        detailShown.toggle()
        detailLabel.isHidden = !detailShown
        detailHeight.isActive = !detailShown
        needsLayout = true
    }

    public func setStatus(_ status: Status, output: String?) {
        switch status {
        case .running: statusDot.stringValue = "•"; statusDot.textColor = .systemYellow
        case .ok:      statusDot.stringValue = "✓"; statusDot.textColor = .systemGreen
        case .failed:  statusDot.stringValue = "✗"; statusDot.textColor = .systemRed
        }
        if let output, !output.isEmpty {
            // Append tool output below any command/diff detail.
            let combined = [detailText, output].compactMap { $0 }.joined(separator: "\n")
            detailText = combined
            detailLabel.stringValue = combined
            disclosure.isHidden = false
        }
    }

    /// Annotate the card with a governance risk verdict. `.allow` hides the
    /// badge; `.caution`/`.high` show a coloured pill with the reason as tooltip.
    public func setRisk(_ verdict: AgentPolicy.Verdict) {
        riskTier = verdict.risk
        switch verdict.risk {
        case .allow:
            riskBadge.isHidden = true
        case .caution:
            riskBadge.isHidden = false
            riskBadge.stringValue = "  CAUTION  "
            riskBadge.toolTip = verdict.reason
        case .high:
            riskBadge.isHidden = false
            riskBadge.stringValue = "  HIGH RISK  "
            riskBadge.toolTip = verdict.reason
        }
        applyColors()
    }

    private func applyColors() {
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        riskBadge.layer?.cornerRadius = 4
        // Tint the whole card by risk so high-risk actions are noticeable at a glance.
        switch riskTier {
        case .allow:
            card.layer?.backgroundColor = NSColor.textColor.withAlphaComponent(0.04).cgColor
        case .caution:
            card.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
            riskBadge.textColor = .systemOrange
            riskBadge.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.16).cgColor
        case .high:
            card.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.10).cgColor
            card.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.5).cgColor
            riskBadge.textColor = .systemRed
            riskBadge.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.18).cgColor
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private static func symbol(for kind: AgentToolCall.Kind) -> String {
        switch kind {
        case .fileEdit:   return "pencil"
        case .fileCreate: return "doc.badge.plus"
        case .fileRead:   return "doc.text"
        case .shell:      return "terminal"
        case .search:     return "magnifyingglass"
        case .web:        return "globe"
        case .other:      return "wrench.and.screwdriver"
        }
    }
}
