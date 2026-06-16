// SPDX-License-Identifier: MIT
// Sourcepad — one harness's answer in a best-of-N comparison: a header (which
// CLI · model), the streamed answer (reusing the assistant bubble's markdown),
// a token/cost readout, and a "Use this answer" button that adopts it into the
// conversation. Comparison runs are read-only, so several run in parallel safely.

import AppKit

public final class AgentCompareCard: NSView {

    /// Invoked when the user picks this harness's answer.
    public var onUse: (() -> Void)?

    private let card = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusDot = NSTextField(labelWithString: "•")
    private let costLabel = NSTextField(labelWithString: "")
    private let bubble = AgentMessageBubble(role: .assistant, text: "")
    private let useButton = NSButton()
    private var finished = false

    public init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(title: title)
        applyColors()
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - Streaming updates

    public func appendDelta(_ delta: String) { bubble.appendDelta(delta) }

    public func setStatusWorking() { statusDot.stringValue = "•"; statusDot.textColor = .systemYellow }

    public func setUsage(input: Int, output: Int, costUSD: Double) {
        var s = "↑\(fmt(input)) ↓\(fmt(output))"
        if costUSD > 0 { s += String(format: " · $%.4f", costUSD) }
        costLabel.stringValue = s
    }

    public func finish(error: String?) {
        finished = true
        if let error {
            statusDot.stringValue = "✗"; statusDot.textColor = .systemRed
            if bubble.text.isEmpty { bubble.setText("⚠︎ \(error)") }
            useButton.isEnabled = false
        } else {
            statusDot.stringValue = "✓"; statusDot.textColor = .systemGreen
            if bubble.text.isEmpty { bubble.setText("_(no output)_") }
            useButton.isEnabled = true
        }
    }

    // MARK: - Build

    private func build(title: String) {
        card.wantsLayer = true
        card.layer?.cornerRadius = 7
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        titleLabel.stringValue = "⚖︎ \(title)"
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        statusDot.font = .systemFont(ofSize: 11)
        statusDot.textColor = .systemYellow
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.setContentHuggingPriority(.required, for: .horizontal)

        let header = NSStackView(views: [titleLabel, statusDot])
        header.orientation = .horizontal
        header.spacing = 6
        header.translatesAutoresizingMaskIntoConstraints = false

        bubble.translatesAutoresizingMaskIntoConstraints = false

        costLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        costLabel.textColor = .secondaryLabelColor
        costLabel.translatesAutoresizingMaskIntoConstraints = false

        useButton.title = "Use this answer"
        useButton.bezelStyle = .rounded
        useButton.controlSize = .small
        useButton.font = .systemFont(ofSize: 11)
        useButton.target = self
        useButton.action = #selector(useTapped)
        useButton.isEnabled = false
        useButton.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [costLabel, NSView(), useButton])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false

        let v = NSStackView(views: [header, bubble, footer])
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 5
        v.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(v)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            card.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            v.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            v.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            v.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            v.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
            header.widthAnchor.constraint(equalTo: v.widthAnchor),
            bubble.widthAnchor.constraint(equalTo: v.widthAnchor),
            footer.widthAnchor.constraint(equalTo: v.widthAnchor),
        ])
    }

    @objc private func useTapped() { onUse?() }

    private func fmt(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }

    private func applyColors() {
        card.layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.06).cgColor
        card.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }
}
