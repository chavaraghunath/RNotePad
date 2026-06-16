// SPDX-License-Identifier: MIT
// Sourcepad — a transcript card showing a Plan→Act→Verify run: each build/test/
// lint step with a live pass/fail status, the failing step's output, and an
// "Ask agent to fix" button that feeds the failure back to the agent.

import AppKit

public final class AgentVerifyCard: NSView {

    /// Called when the user asks the agent to fix the failing step.
    public var onFix: ((VerifyRunner.StepResult) -> Void)?

    private enum StepStatus { case pending, running, passed, failed }

    private let plan: VerifyPlan
    private var statuses: [StepStatus]
    private var results: [VerifyRunner.StepResult?]
    private var finished = false
    private var allPassed = false

    private let card = NSView()
    private let stack = NSStackView()

    public init(plan: VerifyPlan) {
        self.plan = plan
        self.statuses = Array(repeating: .pending, count: plan.steps.count)
        self.results = Array(repeating: nil, count: plan.steps.count)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        render()
        applyColors()
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - Public updates

    public func markRunning(_ step: VerifyPlan.Step) {
        if let i = index(of: step) { statuses[i] = .running; render() }
    }

    public func setResult(_ r: VerifyRunner.StepResult) {
        if let i = index(of: r.step) {
            statuses[i] = r.passed ? .passed : .failed
            results[i] = r
            render()
        }
    }

    public func finish(allPassed: Bool) {
        self.finished = true
        self.allPassed = allPassed
        render()
        applyColors()
    }

    // MARK: - Build / render

    private func build() {
        card.wantsLayer = true
        card.layer?.cornerRadius = 7
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            card.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let header = NSTextField(labelWithString: headerText())
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = headerColor()
        stack.addArrangedSubview(header)

        for (i, step) in plan.steps.enumerated() {
            let row = NSTextField(labelWithString: "\(symbol(statuses[i]))  \(step.label) — \(step.command)")
            row.font = .systemFont(ofSize: 11)
            row.textColor = statuses[i] == .failed ? .systemRed : .secondaryLabelColor
            row.lineBreakMode = .byTruncatingMiddle
            stack.addArrangedSubview(row)
        }

        // Failing step output + fix button.
        if finished, !allPassed, let failed = results.compactMap({ $0 }).first(where: { !$0.passed }) {
            let out = NSTextView()
            out.isEditable = false
            out.drawsBackground = true
            out.backgroundColor = .textBackgroundColor
            out.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            out.textColor = .labelColor
            out.string = String(failed.output.suffix(1200))
            let scroll = NSScrollView()
            scroll.documentView = out
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
            scroll.widthAnchor.constraint(equalToConstant: 280).isActive = true
            stack.addArrangedSubview(scroll)

            let fix = NSButton(title: "Ask agent to fix", target: self, action: #selector(fixTapped))
            fix.bezelStyle = .rounded
            fix.controlSize = .small
            fix.font = .systemFont(ofSize: 11)
            stack.addArrangedSubview(fix)
        }
    }

    @objc private func fixTapped() {
        if let failed = results.compactMap({ $0 }).first(where: { !$0.passed }) { onFix?(failed) }
    }

    private func headerText() -> String {
        let eco = plan.ecosystem.isEmpty ? "" : " · \(plan.ecosystem)"
        if !finished { return "⚙︎ Verifying\(eco)…" }
        return allPassed ? "✓ Verified\(eco) — all checks passed"
                         : "✗ Verification failed\(eco)"
    }

    private func symbol(_ s: StepStatus) -> String {
        switch s {
        case .pending: return "◦"
        case .running: return "▸"
        case .passed:  return "✓"
        case .failed:  return "✗"
        }
    }

    private func headerColor() -> NSColor {
        guard finished else { return .secondaryLabelColor }
        return allPassed ? .systemGreen : .systemRed
    }

    private func index(of step: VerifyPlan.Step) -> Int? {
        plan.steps.firstIndex(where: { $0.label == step.label && $0.command == step.command })
    }

    private func applyColors() {
        let tint: NSColor = !finished ? .secondaryLabelColor : (allPassed ? .systemGreen : .systemRed)
        card.layer?.backgroundColor = tint.withAlphaComponent(0.08).cgColor
        card.layer?.borderColor = tint.withAlphaComponent(0.4).cgColor
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }
}
