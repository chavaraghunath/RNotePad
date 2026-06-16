// SPDX-License-Identifier: MIT
// Sourcepad — the right-side agent conversation panel (VS Code chat geometry).
//
// Layout (top → bottom):
//   ┌───────────────────────────────────┐
//   │ [CLI ▾] [Model ▾] [Perm ▾]   + ⟲  │  header
//   ├───────────────────────────────────┤
//   │  scrollable transcript (bubbles)  │
//   │                                   │
//   ├───────────────────────────────────┤
//   │  input field            [ Send ]  │
//   └───────────────────────────────────┘
//
// One AgentConversationController drives a turn at a time; the panel renders
// streamed text into a live assistant bubble and lets the user switch CLI /
// model / permission mid-conversation. RootContentViewController hosts the
// panel as the collapsible right item of a horizontal split.

import AppKit

/// A stack view that lays its arranged subviews out top-to-bottom (AppKit's
/// default coordinate origin is bottom-left, which bottom-pins a short
/// transcript). Flipping it makes a chat flow naturally from the top.
final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// A compact, single-line row of "context chips" shown above the input,
/// previewing what editor context (active file, selection, `@`-mentions) will
/// ride along with the next turn. Collapses to nothing when empty.
final class AgentContextBar: NSView {
    struct Chip {
        let symbol: String
        let text: String
        let tooltip: String
    }

    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setChips(_ chips: [Chip]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let color = resolvedPillColor()
        for chip in chips { stack.addArrangedSubview(pill(chip, color: color)) }
    }

    private func pill(_ chip: Chip, color: CGColor) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.backgroundColor = color
        container.translatesAutoresizingMaskIntoConstraints = false
        container.toolTip = chip.tooltip

        let label = NSTextField(labelWithString: chip.text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        let row: NSStackView
        if let img = NSImage(systemSymbolName: chip.symbol, accessibilityDescription: nil) {
            let iv = NSImageView(image: img)
            iv.contentTintColor = .secondaryLabelColor
            iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.setContentHuggingPriority(.required, for: .horizontal)
            row = NSStackView(views: [iv, label])
        } else {
            row = NSStackView(views: [label])
        }
        row.orientation = .horizontal
        row.spacing = 3
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
        ])
        return container
    }

    /// Resolve the (dynamic) pill background under THIS view's effective
    /// appearance, so dark/light is honoured even when set off the main draw
    /// cycle (the same baked-`.cgColor` pitfall the panel hit elsewhere).
    private func resolvedPillColor() -> CGColor {
        var cg = NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cg = NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor
        }
        return cg
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let color = resolvedPillColor()
        for pill in stack.arrangedSubviews {
            pill.layer?.backgroundColor = color
        }
    }
}

/// A transcript row shown after an Auto-mode turn that edited files on disk:
/// a summary plus "Review diff" (opens the unified diff) and "Revert" (restores
/// the workspace to the pre-turn checkpoint).
final class AgentChangesCard: NSView {
    private let diff: String
    private let revert: () -> Bool
    /// Invoked when the user clicks "Verify" to run the project's build/test.
    var onVerify: (() -> Void)?
    private let card = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let reviewButton = NSButton()
    private let revertButton = NSButton()
    private let verifyButton = NSButton()

    init(diff: String, revert: @escaping () -> Bool) {
        self.diff = diff
        self.revert = revert
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        applyColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build() {
        card.wantsLayer = true
        card.layer?.cornerRadius = 7
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let n = diff.components(separatedBy: "diff --git ").count - 1
        titleLabel.stringValue = "✎ \(n == 1 ? "1 file" : "\(max(n, 1)) files") changed this turn"
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        configure(reviewButton, title: "Review diff", action: #selector(review))
        configure(verifyButton, title: "Verify", action: #selector(doVerify))
        configure(revertButton, title: "Revert", action: #selector(doRevert))

        let buttons = NSStackView(views: [reviewButton, verifyButton, revertButton])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let v = NSStackView(views: [titleLabel, buttons])
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 6
        v.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(v)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            card.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            v.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            v.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            v.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            v.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
    }

    private func configure(_ b: NSButton, title: String, action: Selector) {
        b.title = title
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = .systemFont(ofSize: 11)
        b.target = self
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func review() {
        let alert = NSAlert()
        alert.messageText = "Changes this turn"
        let tv = NSTextView()
        tv.isEditable = false
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.textStorage?.setAttributedString(Self.colorizedDiff(diff))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = tv
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Done")
        if let w = window { alert.beginSheetModal(for: w) { _ in } } else { alert.runModal() }
    }

    @objc private func doVerify() {
        verifyButton.isEnabled = false
        onVerify?()
    }

    @objc private func doRevert() {
        let ok = revert()
        if ok {
            titleLabel.stringValue = "↩︎ Reverted changes from this turn"
            reviewButton.isEnabled = false
            revertButton.isEnabled = false
        } else {
            NSSound.beep()
        }
    }

    private func applyColors() {
        card.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.07).cgColor
        card.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// Colorize a unified diff: green additions, red deletions, secondary hunks.
    static func colorizedDiff(_ diff: String) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let out = NSMutableAttributedString()
        for line in diff.components(separatedBy: "\n") {
            let color: NSColor
            if line.hasPrefix("+") && !line.hasPrefix("+++") { color = .systemGreen }
            else if line.hasPrefix("-") && !line.hasPrefix("---") { color = .systemRed }
            else if line.hasPrefix("@@") || line.hasPrefix("diff ") { color = .secondaryLabelColor }
            else { color = .labelColor }
            out.append(NSAttributedString(string: line + "\n",
                                          attributes: [.font: mono, .foregroundColor: color]))
        }
        return out
    }
}

/// A turn-level governance recap shown when the agent took one or more
/// high-risk actions (per the policy engine). Red-tinted, lists each flagged
/// action and why — so a risky action isn't lost in the streamed transcript.
final class AgentGovernanceCard: NSView {
    private let card = NSView()

    init(actions: [(title: String, reason: String)]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(actions)
        applyColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build(_ actions: [(title: String, reason: String)]) {
        card.wantsLayer = true
        card.layer?.cornerRadius = 7
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let n = actions.count
        let header = NSTextField(labelWithString:
            "⚠︎ \(n == 1 ? "1 high-risk action" : "\(n) high-risk actions") this turn")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .systemRed
        header.translatesAutoresizingMaskIntoConstraints = false

        var rows: [NSView] = [header]
        for a in actions.prefix(8) {
            let line = NSTextField(labelWithString: "• \(a.title) — \(a.reason)")
            line.font = .systemFont(ofSize: 10.5)
            line.textColor = .secondaryLabelColor
            line.lineBreakMode = .byTruncatingTail
            line.maximumNumberOfLines = 2
            line.translatesAutoresizingMaskIntoConstraints = false
            rows.append(line)
        }

        let v = NSStackView(views: rows)
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 3
        v.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(v)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            card.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            v.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            v.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            v.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            v.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
    }

    private func applyColors() {
        card.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
        card.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.4).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }
}

/// The panel's root view, filled with the window background colour so the panel
/// has an explicit, appearance-following backdrop (its child scroll view and
/// header are transparent and would otherwise show through to nothing). Redraws
/// when the effective appearance flips dark↔light.
final class AgentPanelRootView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

public final class AgentPanelViewController: NSViewController, AgentConversationDelegate {

    /// Resolves the directory new conversations run in (workspace root → doc → $HOME).
    public var workingDirectoryProvider: (() -> String)?

    // Header
    private let cliPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let permPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let newButton = NSButton()
    private let historyButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let costButton = NSButton()
    private var historyPopover: NSPopover?

    // Transcript
    private let scrollView = NSScrollView()
    private let stack = FlippedStackView()
    private var inputHeight: NSLayoutConstraint!

    // Input
    private let input = AgentInputTextView()
    private let inputScroll = NSScrollView()
    private let sendButton = NSButton()

    // Live editor-context preview (active file / selection / @-mentions).
    private let contextBar = AgentContextBar()
    private var contextBarHeight: NSLayoutConstraint!
    private var contextBarTopGap: NSLayoutConstraint!

    private let registry = AgentRegistry.shared
    private var controller: AgentConversationController?
    private var streamingBubble: AgentMessageBubble?
    private var toolCards: [String: AgentToolCard] = [:]
    private var selectedCLIID: String?
    private var emptyLabel: NSTextField?
    private var cliChangeObserver: NSObjectProtocol?
    private var verifyRunner: VerifyRunner?

    // Best-of-N comparison state.
    private let compareButton = NSButton()
    private var compareCards: [String: AgentCompareCard] = [:]
    private var compareHandles: [AgentTurnHandle] = []
    private var compareTexts: [String: String] = [:]
    private var comparePending = 0

    // Autonomous Plan→Act→Verify→Fix loop (event-driven).
    private let autoButton = NSButton()
    private var lastTurnChangedFiles = false
    private var autoFixIterations = 0
    private static let autoFixCap = 3
    private var autoVerifyEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "Sourcepad.agent.autoVerify") }
        set { UserDefaults.standard.set(newValue, forKey: "Sourcepad.agent.autoVerify") }
    }
    private var autoFixEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "Sourcepad.agent.autoFix") }
        set { UserDefaults.standard.set(newValue, forKey: "Sourcepad.agent.autoFix") }
    }
    // High-risk actions flagged by the policy engine during the current turn,
    // surfaced as a governance summary when the turn finishes.
    private var turnFlaggedActions: [(title: String, reason: String)] = []

    // MARK: - Load

    public override func loadView() {
        let root = AgentPanelRootView(frame: NSRect(x: 0, y: 0, width: 360, height: 720))
        root.wantsLayer = true

        buildHeader(in: root)
        buildTranscript(in: root)
        buildInput(in: root)
        self.view = root
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        populatePermissions()
        rebuildCLIPopup()
        registry.warmUp { [weak self] in self?.rebuildCLIPopup() }
        refreshStatus()
        updateEmptyState()
        refreshContextBar()
        updateAutoButton()
        cliChangeObserver = NotificationCenter.default.addObserver(
            forName: .sourcepadAgentCLIsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildCLIPopup()
        }
    }

    deinit {
        if let cliChangeObserver { NotificationCenter.default.removeObserver(cliChangeObserver) }
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        // The active document / selection may have changed while the panel was
        // hidden; refresh the preview when it becomes visible.
        refreshContextBar()
    }

    // MARK: - UI construction

    private func buildHeader(in root: NSView) {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        for popup in [cliPopup, modelPopup, permPopup] {
            popup.translatesAutoresizingMaskIntoConstraints = false
            popup.bezelStyle = .rounded
            popup.controlSize = .small
            popup.font = .systemFont(ofSize: 11)
        }
        cliPopup.target = self;  cliPopup.action = #selector(cliChanged)
        modelPopup.target = self; modelPopup.action = #selector(modelChanged)
        permPopup.target = self;  permPopup.action = #selector(permChanged)

        newButton.translatesAutoresizingMaskIntoConstraints = false
        newButton.bezelStyle = .texturedRounded
        newButton.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "New conversation")
        newButton.imagePosition = .imageOnly
        newButton.toolTip = "New conversation"
        newButton.target = self
        newButton.action = #selector(newConversation)

        historyButton.translatesAutoresizingMaskIntoConstraints = false
        historyButton.bezelStyle = .texturedRounded
        historyButton.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "History")
        historyButton.imagePosition = .imageOnly
        historyButton.toolTip = "Conversation history"
        historyButton.target = self
        historyButton.action = #selector(showHistory)

        compareButton.translatesAutoresizingMaskIntoConstraints = false
        compareButton.bezelStyle = .texturedRounded
        compareButton.image = NSImage(systemSymbolName: "square.split.2x1", accessibilityDescription: "Compare (best-of-N)")
        compareButton.imagePosition = .imageOnly
        compareButton.toolTip = "Compare this prompt across multiple agents (best-of-N)"
        compareButton.target = self
        compareButton.action = #selector(compareTapped)

        autoButton.translatesAutoresizingMaskIntoConstraints = false
        autoButton.bezelStyle = .texturedRounded
        autoButton.image = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: "Auto-pilot")
        autoButton.imagePosition = .imageOnly
        autoButton.toolTip = "Auto-pilot: auto-verify after changes, auto-fix on failure"
        autoButton.target = self
        autoButton.action = #selector(autoMenuTapped)

        let row = NSStackView(views: [cliPopup, modelPopup, permPopup, NSView(), compareButton, autoButton, historyButton, newButton])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(row)

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(statusLabel)

        // Live token/cost readout; click to set or clear a per-conversation budget.
        costButton.translatesAutoresizingMaskIntoConstraints = false
        costButton.isBordered = false
        costButton.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        costButton.contentTintColor = .secondaryLabelColor
        costButton.alignment = .right
        costButton.title = ""
        costButton.target = self
        costButton.action = #selector(showBudgetMenu)
        costButton.toolTip = "Token usage / cost — click to set a budget"
        costButton.setContentHuggingPriority(.required, for: .horizontal)
        costButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        header.addSubview(costButton)

        let divider = NSBox(); divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(divider)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),

            row.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: header.topAnchor, constant: 6),
            newButton.widthAnchor.constraint(equalToConstant: 26),
            historyButton.widthAnchor.constraint(equalToConstant: 26),
            compareButton.widthAnchor.constraint(equalToConstant: 26),
            autoButton.widthAnchor.constraint(equalToConstant: 26),

            statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            statusLabel.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 3),

            costButton.leadingAnchor.constraint(greaterThanOrEqualTo: statusLabel.trailingAnchor, constant: 6),
            costButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            costButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),

            divider.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            divider.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 5),
            divider.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
        self.headerBottom = divider.bottomAnchor
    }

    private var headerBottom: NSLayoutYAxisAnchor!
    private var inputTop: NSLayoutYAxisAnchor!

    private func buildTranscript(in root: NSView) {
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = stack
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    private func buildInput(in root: NSView) {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(bar)

        input.onSubmit = { [weak self] in self?.submit() }
        input.onHeightChange = { [weak self] h in
            self?.inputHeight.animator().constant = min(150, max(34, h))
        }
        input.onTextChange = { [weak self] in self?.refreshContextBar() }
        input.font = .systemFont(ofSize: 13)
        input.isRichText = false
        input.isEditable = true
        input.isSelectable = true
        input.drawsBackground = true
        input.backgroundColor = .textBackgroundColor
        input.textColor = .labelColor
        input.insertionPointColor = .labelColor
        input.minSize = NSSize(width: 0, height: 28)
        input.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainerInset = NSSize(width: 4, height: 5)
        input.textContainer?.widthTracksTextView = true
        input.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        inputScroll.documentView = input
        inputScroll.hasVerticalScroller = true
        inputScroll.drawsBackground = true
        inputScroll.backgroundColor = .textBackgroundColor
        inputScroll.borderType = .bezelBorder
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(inputScroll)
        inputHeight = inputScroll.heightAnchor.constraint(equalToConstant: 34)
        inputHeight.isActive = true

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.bezelStyle = .rounded
        sendButton.title = "Send"
        sendButton.keyEquivalent = "\r"
        sendButton.target = self
        sendButton.action = #selector(submit)
        bar.addSubview(sendButton)

        let divider = NSBox(); divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(divider)

        // Context bar sits between the divider and the input field. It collapses
        // to zero height when there is nothing to preview.
        contextBar.isHidden = true
        bar.addSubview(contextBar)
        contextBarHeight = contextBar.heightAnchor.constraint(equalToConstant: 0)
        contextBarTopGap = contextBar.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 0)
        contextBarHeight.isActive = true
        contextBarTopGap.isActive = true

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            divider.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: bar.topAnchor),

            contextBar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            contextBar.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),

            inputScroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            inputScroll.topAnchor.constraint(equalTo: contextBar.bottomAnchor, constant: 8),
            inputScroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8),

            sendButton.leadingAnchor.constraint(equalTo: inputScroll.trailingAnchor, constant: 6),
            sendButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            sendButton.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 56),
        ])

        // Connect scroll view between header and input bar.
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerBottom),
            scrollView.bottomAnchor.constraint(equalTo: bar.topAnchor),
        ])
    }

    // MARK: - Pickers

    private func populatePermissions() {
        permPopup.removeAllItems()
        permPopup.addItems(withTitles: ["Plan", "Auto"])
        permPopup.selectItem(withTitle: "Plan")   // safe default until Phase 3 approvals
        permPopup.toolTip = "Plan = read-only · Auto = let the agent edit/run freely"
    }

    private var permissionMode: AgentPermissionMode {
        permPopup.titleOfSelectedItem == "Auto" ? .auto : .readOnly
    }

    private func rebuildCLIPopup() {
        let clis = registry.availableCLIs()
        let previous = selectedCLIID
        cliPopup.removeAllItems()
        for cli in clis { cliPopup.addItem(withTitle: cli.displayName); cliPopup.lastItem?.representedObject = cli.id }
        // A trailing entry to open the CLI manager (add/remove CLIs by command).
        cliPopup.menu?.addItem(.separator())
        let manage = NSMenuItem(title: "Manage CLIs…", action: nil, keyEquivalent: "")
        manage.representedObject = "__manage__"
        cliPopup.menu?.addItem(manage)
        let mlx = NSMenuItem(title: "MLX Models…", action: nil, keyEquivalent: "")
        mlx.representedObject = "__mlx__"
        cliPopup.menu?.addItem(mlx)
        if let prev = previous, let idx = clis.firstIndex(where: { $0.id == prev }) {
            cliPopup.selectItem(at: idx)
            selectedCLIID = prev
        } else if let first = clis.first {
            cliPopup.selectItem(at: 0)
            selectedCLIID = first.id
        } else {
            selectedCLIID = nil
        }
        rebuildModelPopup()
        updateEmptyState()
    }

    private func rebuildModelPopup() {
        modelPopup.removeAllItems()
        guard let cliID = selectedCLIID else { return }
        let models = registry.models(for: cliID)
        if models.isEmpty {
            modelPopup.addItem(withTitle: "Default")
            modelPopup.lastItem?.representedObject = nil
        } else {
            for m in models {
                modelPopup.addItem(withTitle: m.displayName)
                modelPopup.lastItem?.representedObject = m
            }
        }
    }

    private var selectedModel: AgentModel? {
        modelPopup.selectedItem?.representedObject as? AgentModel
    }

    // MARK: - Actions

    @objc private func cliChanged() {
        // The trailing "Manage CLIs…" entry opens the manager and restores the
        // previous selection rather than changing the active CLI.
        let sentinel = cliPopup.selectedItem?.representedObject as? String
        if sentinel == "__manage__" || sentinel == "__mlx__" {
            if sentinel == "__mlx__" { MLXModelsWindowController.shared.show() }
            else { AgentCLIManagerWindowController.shared.show() }
            if let id = selectedCLIID,
               let idx = (0..<cliPopup.numberOfItems).first(where: { (cliPopup.item(at: $0)?.representedObject as? String) == id }) {
                cliPopup.selectItem(at: idx)
            }
            return
        }
        selectedCLIID = cliPopup.selectedItem?.representedObject as? String
        rebuildModelPopup()
        if let controller, let id = selectedCLIID {
            controller.switchCLI(id, model: selectedModel)
            refreshStatus()
        }
    }

    @objc private func modelChanged() {
        if let controller, let m = selectedModel { controller.switchModel(m); refreshStatus() }
    }

    @objc private func permChanged() {
        // Plan (read-only) needs no authorization.
        guard permissionMode == .auto else {
            controller?.permission = .readOnly
            refreshStatus()
            return
        }
        // Entering Auto grants the agent power to edit files and run commands —
        // gate it behind device authentication (Touch ID / passcode). The vault
        // caches a successful auth briefly, so toggling isn't naggy.
        TouchIDVault.shared.authenticate(
            reason: "allow the agent to edit files and run commands (Auto mode)"
        ) { [weak self] ok in
            guard let self else { return }
            if ok {
                self.controller?.permission = .auto
            } else {
                // Cancelled or failed — fall back to the safe Plan mode.
                self.permPopup.selectItem(withTitle: "Plan")
                self.controller?.permission = .readOnly
            }
            self.refreshStatus()
        }
    }

    @objc private func showHistory() {
        let vc = AgentHistoryPopover()
        vc.onSelect = { [weak self] id in
            self?.historyPopover?.close()
            self?.loadConversation(id)
        }
        vc.onDelete = { [weak self] id in
            // If the user deleted the conversation that's currently open, reset
            // the panel to a fresh one so it isn't pointing at a deleted row.
            guard let self, self.controller?.conversationID == id else { return }
            self.newConversation()
        }
        let pop = NSPopover()
        pop.contentViewController = vc
        // Semitransient so showing the delete-confirm sheet doesn't dismiss it.
        pop.behavior = .semitransient
        pop.contentSize = NSSize(width: 340, height: 380)
        pop.show(relativeTo: historyButton.bounds, of: historyButton, preferredEdge: .minY)
        historyPopover = pop
    }

    /// Replace the live transcript with a persisted conversation and rebind the
    /// controller so the next turn natively resumes that conversation's session.
    private func loadConversation(_ id: Int64) {
        guard let store = AgentStore.shared, let row = store.conversation(id: id) else { return }
        controller?.cancel()
        streamingBubble = nil
        toolCards.removeAll()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let c = AgentConversationController.open(row)
        c.delegate = self
        c.permission = permissionMode
        controller = c

        // Sync pickers to the reopened conversation's CLI / model.
        if let cli = row.currentCLI,
           let idx = (0..<cliPopup.numberOfItems).first(where: { (cliPopup.item(at: $0)?.representedObject as? String) == cli }) {
            cliPopup.selectItem(at: idx)
            selectedCLIID = cli
            rebuildModelPopup()
            if let m = row.currentModel,
               let midx = (0..<modelPopup.numberOfItems).first(where: { ((modelPopup.item(at: $0)?.representedObject as? AgentModel)?.id) == m }) {
                modelPopup.selectItem(at: midx)
            }
        }
        refreshStatus()

        // Render the persisted messages.
        for m in store.messages(conversation: id) {
            switch m.role {
            case "user":      appendBubble(role: .user, text: m.content)
            case "assistant": appendBubble(role: .assistant, text: m.content)
            default:          appendBubble(role: .system, text: m.content)
            }
        }
        updateCostReadout()
        focusInput()
    }

    @objc private func newConversation() {
        controller?.cancel()
        controller = nil
        streamingBubble = nil
        toolCards.removeAll()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        refreshStatus()
        updateCostReadout()
        focusInput()
    }

    @objc private func submit() {
        let text = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard ensureConversation() else {
            appendBubble(role: .system, text: "No agent CLI is available. Install claude, codex, or opencode.")
            return
        }
        if controller?.isOverBudget == true {
            appendBubble(role: .system, text: "Budget reached. Raise or clear the budget (click the cost readout) to continue.")
            return
        }
        // Capture editor context BEFORE clearing the input (the typed text still
        // holds any `@`-mentions to resolve).
        let editorContext = currentEditorContext()
        input.string = ""
        inputHeight.constant = 34
        appendBubble(role: .user, text: text)
        // Assistant bubbles are created lazily on the first text delta so a
        // tool-only turn doesn't leave an empty bubble.
        streamingBubble = nil
        turnFlaggedActions.removeAll()
        autoFixIterations = 0   // a manual prompt starts a fresh auto-fix budget
        statusLabel.stringValue = "Thinking…"
        sendButton.isEnabled = false
        controller?.send(text, editorContext: editorContext)
        refreshContextBar()
    }

    // MARK: - Conversation lifecycle

    @discardableResult
    private func ensureConversation() -> Bool {
        if controller != nil { return true }
        guard let cliID = selectedCLIID else { return false }
        let cwd = workingDirectoryProvider?() ?? FileManager.default.homeDirectoryForCurrentUser.path
        let c = AgentConversationController.create(cliID: cliID, model: selectedModel, workingDirectory: cwd)
        c?.permission = permissionMode
        c?.delegate = self
        controller = c
        refreshStatus()
        updateCostReadout()
        return c != nil
    }

    public func focusInput() {
        view.window?.makeFirstResponder(input)
        refreshContextBar()
    }

    /// Cancel any in-flight turn. Called when the window closes.
    public func shutdown() {
        controller?.cancel()
    }

    // MARK: - Editor context

    /// Snapshot the editor the user is looking at: active file path + language,
    /// current selection, diagnostics, and open file paths. Sampled fresh at
    /// send time so what reaches the agent always reflects the live editor.
    private func currentEditorContext() -> AgentContextProvider.EditorContextSnapshot {
        let dc = NSDocumentController.shared
        let active = dc.currentDocument as? TextDocument
        let editor = active?.primaryEditorViewController()
        let pane = editor?.editorPane
        let openPaths = dc.documents.compactMap { ($0 as? TextDocument)?.fileURL?.path }
        // Agent-facing language is derived from the file extension, NOT the
        // editor's syntax lexer (which buckets many languages under "cpp").
        let language: String?
        if let activePath = active?.fileURL?.path {
            language = AgentContextProvider.languageHint(forPath: activePath)
        } else {
            language = nil
        }
        return AgentContextProvider.EditorContextSnapshot(
            activeFilePath: active?.fileURL?.path,
            activeFileLanguage: language,
            selection: pane?.selectedContextText,
            diagnostics: pane?.contextDiagnostics ?? [],
            openFilePaths: openPaths)
    }

    /// Rebuild the live context preview from the current editor + input text.
    /// This is a best-effort preview; the authoritative context is sampled
    /// fresh in `submit()`, so a slightly stale bar never sends stale context.
    private func refreshContextBar() {
        let ctx = currentEditorContext()
        var chips: [AgentContextBar.Chip] = []

        if let path = ctx.activeFilePath {
            let name = (path as NSString).lastPathComponent
            chips.append(.init(symbol: "doc.text", text: name, tooltip: "Active file: \(path)"))
        }
        if let sel = ctx.selection, !sel.isEmpty {
            let lines = sel.components(separatedBy: "\n").count
            chips.append(.init(symbol: "text.viewfinder",
                               text: "\(lines) line\(lines == 1 ? "" : "s")",
                               tooltip: "The highlighted selection will be included"))
        }
        if !ctx.diagnostics.isEmpty {
            let n = ctx.diagnostics.count
            chips.append(.init(symbol: "exclamationmark.triangle",
                               text: "\(n) issue\(n == 1 ? "" : "s")",
                               tooltip: ctx.diagnostics.prefix(8).joined(separator: "\n")))
        }
        let mentions = resolvedMentionNames()
        for name in mentions.prefix(4) {
            chips.append(.init(symbol: "at", text: name, tooltip: "Attached via @-mention"))
        }
        if mentions.count > 4 {
            chips.append(.init(symbol: "ellipsis",
                               text: "+\(mentions.count - 4)",
                               tooltip: "More @-mentioned files attached"))
        }

        let hasChips = !chips.isEmpty
        contextBar.setChips(chips)
        contextBar.isHidden = !hasChips
        contextBarHeight.constant = hasChips ? 22 : 0
        contextBarTopGap.constant = hasChips ? 6 : 0
    }

    /// File names of `@`-mentions in the current input that resolve to real
    /// files (mirrors exactly what `composeAgentPrompt` will attach).
    private func resolvedMentionNames() -> [String] {
        let text = input.string
        guard text.contains("@") else { return [] }
        let cwd = controller?.workingDirectory
            ?? workingDirectoryProvider?()
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let result = AgentContextProvider.resolveMentions(in: text, workspaceRoot: cwd, maxBytesPerFile: 1)
        return result.attachments.map { ($0.path as NSString).lastPathComponent }
    }


    @discardableResult
    private func appendBubble(role: AgentMessageBubble.Role, text: String) -> AgentMessageBubble {
        let bubble = AgentMessageBubble(role: role, text: text)
        addArrangedRow(bubble)
        return bubble
    }

    private func addArrangedRow(_ row: NSView) {
        stack.addArrangedSubview(row)
        row.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        row.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        scrollToBottom()
    }

    private func scrollToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.layoutSubtreeIfNeeded()
            let maxY = max(0, self.stack.frame.height - self.scrollView.contentView.bounds.height)
            self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    private func refreshStatus() {
        guard selectedCLIID != nil else { statusLabel.stringValue = "No agent CLI found"; return }
        let cli = cliPopup.titleOfSelectedItem ?? "—"
        let model = modelPopup.titleOfSelectedItem ?? "default"
        statusLabel.stringValue = "\(cli) · \(model)"
    }

    private func updateEmptyState() {
        let hasCLI = selectedCLIID != nil
        cliPopup.isEnabled = hasCLI
        modelPopup.isEnabled = hasCLI
        sendButton.isEnabled = hasCLI
        if !hasCLI && emptyLabel == nil {
            let l = NSTextField(labelWithString: "No agent CLI found.\nInstall claude, codex, or opencode\nand reopen this panel.")
            l.alignment = .center
            l.textColor = .secondaryLabelColor
            l.font = .systemFont(ofSize: 12)
            l.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(l)
            NSLayoutConstraint.activate([
                l.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
                l.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            ])
            emptyLabel = l
        } else if hasCLI {
            emptyLabel?.removeFromSuperview()
            emptyLabel = nil
        }
    }

    // MARK: - AgentConversationDelegate

    public func conversation(_ c: AgentConversationController, didStreamText delta: String) {
        if streamingBubble == nil { streamingBubble = appendBubble(role: .assistant, text: "") }
        streamingBubble?.appendDelta(delta)
        scrollToBottom()
    }

    public func conversation(_ c: AgentConversationController, didStreamThinking delta: String) {
        statusLabel.stringValue = "Thinking…"
    }

    public func conversation(_ c: AgentConversationController, didReceive toolCall: AgentToolCall) {
        // End the current assistant bubble; the next text delta starts a new one
        // after the tool card, matching the agent's interleaved output.
        streamingBubble = nil
        let card = AgentToolCard(toolCall: toolCall)
        // Governance: classify the action and annotate the card; remember
        // high-risk ones for the turn-level summary.
        let verdict = AgentPolicy.evaluate(toolCall, workspaceRoot: c.workingDirectory)
        card.setRisk(verdict)
        if verdict.risk == .high {
            turnFlaggedActions.append((toolCall.title, verdict.reason ?? "High-risk action"))
        }
        toolCards[toolCall.id] = card
        addArrangedRow(card)
    }

    public func conversation(_ c: AgentConversationController, didReceiveToolResult id: String, ok: Bool, output: String?) {
        toolCards[id]?.setStatus(ok ? .ok : .failed, output: output)
        scrollToBottom()
    }

    public func conversation(_ c: AgentConversationController, didUpdateUsageInputTokens input: Int, outputTokens: Int, costUSD: Double) {
        updateCostReadout()
        updateBudgetGate()
    }

    public func conversation(_ c: AgentConversationController, didChangeFilesWithDiff diff: String, revert: @escaping () -> Bool) {
        let card = AgentChangesCard(diff: diff, revert: revert)
        card.onVerify = { [weak self] in self?.runVerify() }
        addArrangedRow(card)
        lastTurnChangedFiles = true   // for the autonomous auto-verify trigger
    }

    // MARK: - Verify (Plan → Act → Verify)

    /// Detect the workspace's build/test/lint plan, run it, and surface results.
    /// On failure the verify card offers to feed the output back to the agent.
    private func runVerify() {
        let cwd = controller?.workingDirectory
            ?? workingDirectoryProvider?()
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let plan = VerifyDetector.detect(workspaceRoot: cwd)
        guard !plan.isEmpty else {
            appendBubble(role: .system, text: "No verify command detected for this workspace (looked for package.json, Cargo.toml, go.mod, Package.swift, Makefile, …).")
            return
        }
        let card = AgentVerifyCard(plan: plan)
        card.onFix = { [weak self] failed in self?.sendFixRequest(for: failed) }
        addArrangedRow(card)

        let runner = VerifyRunner(plan: plan, workingDirectory: cwd)
        verifyRunner = runner
        if let first = plan.steps.first { card.markRunning(first) }
        var index = 0
        runner.run(onStep: { [weak card, weak self] result in
            card?.setResult(result)
            index += 1
            if result.passed, index < plan.steps.count {
                card?.markRunning(plan.steps[index])
            }
            self?.scrollToBottom()
        }, onFinish: { [weak card, weak self] passed, results in
            card?.finish(allPassed: passed)
            self?.verifyRunner = nil
            self?.scrollToBottom()
            guard let self else { return }
            // Auto-fix: on failure, re-prompt the agent (capped to avoid runaway).
            if !passed, self.autoFixEnabled, self.autoFixIterations < Self.autoFixCap,
               self.controller?.isStreaming == false, self.controller?.isOverBudget == false,
               let failed = results.first(where: { !$0.passed }) {
                self.autoFixIterations += 1
                self.appendBubble(role: .system,
                                  text: "⟳ Auto-fix \(self.autoFixIterations)/\(Self.autoFixCap): asking the agent to fix the failing \(failed.step.label)…")
                self.sendFixRequest(for: failed)
            } else if !passed, self.autoFixEnabled, self.autoFixIterations >= Self.autoFixCap {
                self.appendBubble(role: .system, text: "Auto-fix stopped after \(Self.autoFixCap) attempts — needs a human.")
            }
        })
    }

    /// Start a turn asking the agent to fix a failing verification step, seeding
    /// it with the command and its output.
    private func sendFixRequest(for failed: VerifyRunner.StepResult) {
        guard let controller, !controller.isStreaming else { return }
        if controller.isOverBudget {
            appendBubble(role: .system, text: "Budget reached. Raise or clear the budget to continue.")
            return
        }
        let prompt = """
        The verification step "\(failed.step.label)" (`\(failed.step.command)`) failed (exit \(failed.exitCode)). Investigate and fix the root cause, then we'll re-verify. Output:

        ```
        \(String(failed.output.suffix(4000)))
        ```
        """
        appendBubble(role: .user, text: "Fix the failing \(failed.step.label) step")
        streamingBubble = nil
        turnFlaggedActions.removeAll()
        statusLabel.stringValue = "Thinking…"
        sendButton.isEnabled = false
        controller.send(prompt, editorContext: currentEditorContext())
    }

    // MARK: - Best-of-N comparison

    /// One harness per available CLI, using the active model for the selected
    /// CLI and each other CLI's first model.
    private func selectedHarnesses() -> [(cli: AgentCLI, model: AgentModel?)] {
        registry.availableCLIs().map { cli in
            let model = (cli.id == selectedCLIID ? selectedModel : nil) ?? registry.models(for: cli.id).first
            return (cli, model)
        }
    }

    @objc private func compareTapped() {
        let text = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { NSSound.beep(); return }
        guard comparePending == 0 else { return }
        let harnesses = selectedHarnesses()
        guard harnesses.count >= 2 else {
            appendBubble(role: .system, text: "Best-of-N needs at least two installed agents. Add another via Manage CLIs.")
            return
        }
        let names = harnesses.map { $0.cli.displayName }.joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "Compare across \(harnesses.count) agents?"
        alert.informativeText = "Runs this prompt read-only on: \(names). You pick the best answer to keep."
        alert.addButton(withTitle: "Compare")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runCompare(text: text, harnesses: harnesses)
    }

    private func runCompare(text: String, harnesses: [(cli: AgentCLI, model: AgentModel?)]) {
        guard ensureConversation(), let controller else { return }
        let cwd = controller.workingDirectory
        let editorContext = currentEditorContext()
        input.string = ""
        inputHeight.constant = 34
        appendBubble(role: .user, text: text)

        let composed = AgentContextProvider.composeAgentPrompt(typed: text, workspaceRoot: cwd, context: editorContext)
        let reseed = controller.contextReseed()

        compareCards = [:]; compareHandles = []; compareTexts = [:]
        comparePending = harnesses.count
        compareButton.isEnabled = false
        sendButton.isEnabled = false
        statusLabel.stringValue = "Comparing \(harnesses.count) agents…"

        for (cli, model) in harnesses {
            let id = cli.id
            let card = AgentCompareCard(title: "\(cli.displayName) · \(model?.displayName ?? "default")")
            card.onUse = { [weak self] in self?.useCompareAnswer(harnessID: id, prompt: text, cli: cli, model: model) }
            compareCards[id] = card
            compareTexts[id] = ""
            addArrangedRow(card)
            // Comparison turns are always read-only, so they run in parallel safely.
            let req = AgentTurnRequest(prompt: composed, model: model?.id, workingDirectory: cwd,
                                       nativeSessionID: nil, reseedTranscript: reseed, permission: .readOnly)
            let handle = cli.startTurn(req) { [weak self] ev in self?.handleCompareEvent(harnessID: id, ev) }
            compareHandles.append(handle)
        }
    }

    private func handleCompareEvent(harnessID id: String, _ ev: AgentEvent) {
        guard let card = compareCards[id] else { return }
        switch ev {
        case .textDelta(let t):
            compareTexts[id, default: ""] += t
            card.appendDelta(t)
            scrollToBottom()
        case .usage(let u):
            card.setUsage(input: u.inputTokens, output: u.outputTokens, costUSD: u.costUSD ?? 0)
        case .turnFinished:
            card.finish(error: nil); compareDidFinishOne()
        case .error(let m):
            card.finish(error: m); compareDidFinishOne()
        default:
            break
        }
    }

    private func compareDidFinishOne() {
        comparePending = max(0, comparePending - 1)
        if comparePending == 0 {
            compareButton.isEnabled = true
            sendButton.isEnabled = true
            statusLabel.stringValue = "Pick the best answer to keep"
        }
    }

    /// Adopt a harness's answer: persist the exchange, switch to that harness,
    /// drop the other comparison cards, and continue the conversation.
    private func useCompareAnswer(harnessID id: String, prompt: String, cli: AgentCLI, model: AgentModel?) {
        guard let controller, let store = AgentStore.shared else { return }
        let chosen = (compareTexts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        compareHandles.forEach { $0.cancel() }
        compareHandles = []
        compareCards.values.forEach { $0.removeFromSuperview() }
        compareCards = [:]; compareTexts = [:]; comparePending = 0

        store.appendMessage(conversation: controller.conversationID, role: "user", content: prompt, kind: "text")
        if !chosen.isEmpty {
            store.appendMessage(conversation: controller.conversationID, role: "assistant", content: chosen, kind: "text")
        }
        controller.switchCLI(cli.id, model: model)
        syncPickers(toCLI: cli.id, model: model)

        appendBubble(role: .assistant, text: chosen.isEmpty ? "_(no output)_" : chosen)
        compareButton.isEnabled = true
        sendButton.isEnabled = true
        statusLabel.stringValue = "Kept \(cli.displayName)'s answer"
        scrollToBottom()
    }

    private func syncPickers(toCLI cliID: String, model: AgentModel?) {
        guard let idx = (0..<cliPopup.numberOfItems).first(where: { (cliPopup.item(at: $0)?.representedObject as? String) == cliID }) else { return }
        cliPopup.selectItem(at: idx)
        selectedCLIID = cliID
        rebuildModelPopup()
        if let m = model?.id,
           let midx = (0..<modelPopup.numberOfItems).first(where: { ((modelPopup.item(at: $0)?.representedObject as? AgentModel)?.id) == m }) {
            modelPopup.selectItem(at: midx)
        }
    }

    // MARK: - Auto-pilot (autonomous verify → fix loop)

    @objc private func autoMenuTapped() {
        let menu = NSMenu()
        let v = NSMenuItem(title: "Auto-verify after changes", action: #selector(toggleAutoVerify), keyEquivalent: "")
        v.state = autoVerifyEnabled ? .on : .off; v.target = self
        let f = NSMenuItem(title: "Auto-fix on failure (max \(Self.autoFixCap)×)", action: #selector(toggleAutoFix), keyEquivalent: "")
        f.state = autoFixEnabled ? .on : .off; f.target = self
        menu.addItem(v)
        menu.addItem(f)
        menu.addItem(.separator())
        let note = NSMenuItem(title: "After an Auto-mode turn edits files, run the project's build/test automatically; auto-fix re-prompts the agent on failure.", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: autoButton.bounds.height + 2), in: autoButton)
    }

    @objc private func toggleAutoVerify() {
        autoVerifyEnabled.toggle()
        if !autoVerifyEnabled { autoFixEnabled = false }  // fix needs verify
        updateAutoButton()
    }

    @objc private func toggleAutoFix() {
        autoFixEnabled.toggle()
        if autoFixEnabled { autoVerifyEnabled = true }     // fix implies verify
        updateAutoButton()
    }

    private func updateAutoButton() {
        autoButton.contentTintColor = (autoVerifyEnabled || autoFixEnabled) ? .controlAccentColor : nil
    }

    public func conversation(_ c: AgentConversationController, turnDidFinish error: String?) {
        sendButton.isEnabled = true
        refreshStatus()
        updateCostReadout()
        updateBudgetGate()
        // Governance: if the agent took any high-risk actions this turn, recap
        // them so they aren't missed in the stream.
        if !turnFlaggedActions.isEmpty {
            addArrangedRow(AgentGovernanceCard(actions: turnFlaggedActions))
            turnFlaggedActions.removeAll()
        }
        if let error {
            if let b = streamingBubble, b.text.isEmpty {
                b.setText("⚠︎ \(error)")
            } else {
                appendBubble(role: .system, text: "⚠︎ \(error)")
            }
        } else if let b = streamingBubble, b.text.isEmpty {
            b.setText("_(no output)_")
        }
        streamingBubble = nil
        scrollToBottom()

        // Autonomous loop: if the turn edited files, auto-run verify.
        let changed = lastTurnChangedFiles
        lastTurnChangedFiles = false
        if error == nil, changed, autoVerifyEnabled, comparePending == 0 {
            runVerify()
        }
    }

    // MARK: - Cost & budget

    private func updateCostReadout() {
        guard let c = controller else { costButton.title = ""; return }
        var s = "↑\(Self.fmtTokens(c.totalInputTokens)) ↓\(Self.fmtTokens(c.totalOutputTokens))"
        if c.totalCostUSD > 0 { s += String(format: " · $%.4f", c.totalCostUSD) }
        if let b = c.budgetUSD, b > 0 { s += String(format: " / $%.2f", b) }
        costButton.title = s
        costButton.contentTintColor = c.isOverBudget ? .systemRed : .secondaryLabelColor
    }

    private func updateBudgetGate() {
        guard let c = controller, c.isOverBudget else { return }
        sendButton.isEnabled = false
        statusLabel.stringValue = "Budget reached — click the cost to raise it"
    }

    private static func fmtTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    @objc private func showBudgetMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Set budget…", action: #selector(setBudgetPrompt), keyEquivalent: "")
        if controller?.budgetUSD != nil {
            menu.addItem(withTitle: "Clear budget", action: #selector(clearBudget), keyEquivalent: "")
        }
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: costButton.bounds.height + 2), in: costButton)
    }

    @objc private func setBudgetPrompt() {
        guard let controller else { return }
        let alert = NSAlert()
        alert.messageText = "Conversation budget"
        alert.informativeText = "Pause sending once this conversation's cost reaches this amount (USD)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 140, height: 22))
        field.stringValue = controller.budgetUSD.map { String(format: "%.2f", $0) } ?? ""
        field.placeholderString = "e.g. 1.00"
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            controller.budgetUSD = Double(field.stringValue.trimmingCharacters(in: .whitespaces))
            sendButton.isEnabled = !controller.isOverBudget
            updateCostReadout(); refreshStatus(); updateBudgetGate()
        }
    }

    @objc private func clearBudget() {
        controller?.budgetUSD = nil
        sendButton.isEnabled = (controller != nil)
        updateCostReadout(); refreshStatus()
    }
}
