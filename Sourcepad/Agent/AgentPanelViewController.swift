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

public final class AgentPanelViewController: NSViewController, AgentConversationDelegate {

    /// Resolves the directory new conversations run in (workspace root → doc → $HOME).
    public var workingDirectoryProvider: (() -> String)?

    // Header
    private let cliPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let permPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let newButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")

    // Transcript
    private let scrollView = NSScrollView()
    private let stack = FlippedStackView()
    private var inputHeight: NSLayoutConstraint!

    // Input
    private let input = AgentInputTextView()
    private let inputScroll = NSScrollView()
    private let sendButton = NSButton()

    private let registry = AgentRegistry.shared
    private var controller: AgentConversationController?
    private var streamingBubble: AgentMessageBubble?
    private var selectedCLIID: String?
    private var emptyLabel: NSTextField?

    // MARK: - Load

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 720))
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

        let row = NSStackView(views: [cliPopup, modelPopup, permPopup, NSView(), newButton])
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

            statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            statusLabel.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 3),

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

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            divider.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: bar.topAnchor),

            inputScroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            inputScroll.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
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
        controller?.permission = permissionMode
        refreshStatus()
    }

    @objc private func newConversation() {
        controller?.cancel()
        controller = nil
        streamingBubble = nil
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        refreshStatus()
        focusInput()
    }

    @objc private func submit() {
        let text = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard ensureConversation() else {
            appendBubble(role: .system, text: "No agent CLI is available. Install claude, codex, or opencode.")
            return
        }
        input.string = ""
        input.invalidateIntrinsicContentSize()
        appendBubble(role: .user, text: text)
        // Start a fresh assistant bubble to stream into.
        streamingBubble = appendBubble(role: .assistant, text: "")
        statusLabel.stringValue = "Thinking…"
        sendButton.isEnabled = false
        controller?.send(text)
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
        return c != nil
    }

    public func focusInput() {
        view.window?.makeFirstResponder(input)
    }

    /// Cancel any in-flight turn. Called when the window closes.
    public func shutdown() {
        controller?.cancel()
    }


    @discardableResult
    private func appendBubble(role: AgentMessageBubble.Role, text: String) -> AgentMessageBubble {
        let bubble = AgentMessageBubble(role: role, text: text)
        stack.addArrangedSubview(bubble)
        bubble.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        bubble.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        scrollToBottom()
        return bubble
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
        streamingBubble?.appendDelta(delta)
        scrollToBottom()
    }

    public func conversation(_ c: AgentConversationController, didStreamThinking delta: String) {
        statusLabel.stringValue = "Thinking…"
    }

    public func conversation(_ c: AgentConversationController, didReceive toolCall: AgentToolCall) {
        // Phase 3 renders rich tool cards; for now show a compact inline note.
        appendBubble(role: .system, text: "› \(toolCall.title)")
        // Keep streaming the assistant reply into a new bubble after a tool note.
        streamingBubble = appendBubble(role: .assistant, text: "")
    }

    public func conversation(_ c: AgentConversationController, turnDidFinish error: String?) {
        sendButton.isEnabled = true
        refreshStatus()
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
    }
}
