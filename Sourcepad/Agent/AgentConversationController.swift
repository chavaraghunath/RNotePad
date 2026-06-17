// SPDX-License-Identifier: MIT
// Sourcepad — the conversation brain (no UI).
//
// Ties an AgentCLI adapter to the AgentStore and drives one turn at a time:
//   • persists the user message, runs the turn, accumulates the streamed reply,
//     persists the assistant message and the CLI's native session id;
//   • on a CLI switch, decides between native resume (same CLI, known session)
//     and re-seeding a fresh session with the prior transcript (cross-CLI
//     continuity — the user's chosen behavior);
//   • surfaces streaming text / thinking / tool calls / permission requests to a
//     delegate (the panel) on the main queue.
//
// Foundation-only and callback-driven so it can be exercised headlessly.

import Foundation

public protocol AgentConversationDelegate: AnyObject {
    /// The persisted transcript changed — reload from the store.
    func conversationDidUpdate(_ c: AgentConversationController)
    /// Live assistant text arrived (append to the in-progress bubble).
    func conversation(_ c: AgentConversationController, didStreamText delta: String)
    /// Live reasoning text arrived (render collapsed).
    func conversation(_ c: AgentConversationController, didStreamThinking delta: String)
    /// The agent invoked a tool.
    func conversation(_ c: AgentConversationController, didReceive toolCall: AgentToolCall)
    /// Result of a tool the agent ran (matches a prior toolCall by id).
    func conversation(_ c: AgentConversationController, didReceiveToolResult id: String, ok: Bool, output: String?)
    /// The agent wants permission for a privileged action (Phase 3).
    func conversation(_ c: AgentConversationController, didRequest permission: AgentPermissionRequest)
    /// Token/cost totals changed (running sum for the conversation).
    func conversation(_ c: AgentConversationController, didUpdateUsageInputTokens input: Int, outputTokens: Int, costUSD: Double)
    /// An (Auto-mode) turn changed files on disk. `diff` is a unified diff;
    /// calling `revert` restores the workspace to the pre-turn checkpoint.
    func conversation(_ c: AgentConversationController, didChangeFilesWithDiff diff: String, revert: @escaping () -> Bool)
    /// The turn ended; `error` is nil on success.
    func conversation(_ c: AgentConversationController, turnDidFinish error: String?)
}

// Default no-ops so the panel only implements what it needs.
public extension AgentConversationDelegate {
    func conversationDidUpdate(_ c: AgentConversationController) {}
    func conversation(_ c: AgentConversationController, didStreamText delta: String) {}
    func conversation(_ c: AgentConversationController, didStreamThinking delta: String) {}
    func conversation(_ c: AgentConversationController, didReceive toolCall: AgentToolCall) {}
    func conversation(_ c: AgentConversationController, didReceiveToolResult id: String, ok: Bool, output: String?) {}
    func conversation(_ c: AgentConversationController, didRequest permission: AgentPermissionRequest) {}
    func conversation(_ c: AgentConversationController, didUpdateUsageInputTokens input: Int, outputTokens: Int, costUSD: Double) {}
    func conversation(_ c: AgentConversationController, didChangeFilesWithDiff diff: String, revert: @escaping () -> Bool) {}
    func conversation(_ c: AgentConversationController, turnDidFinish error: String?) {}
}

public final class AgentConversationController {

    public let conversationID: Int64
    public private(set) var cliID: String
    public private(set) var model: AgentModel?
    public var workingDirectory: String
    public var permission: AgentPermissionMode = .readOnly

    public weak var delegate: AgentConversationDelegate?
    public private(set) var isStreaming = false

    /// Running token/cost totals for this conversation (loaded from the store on
    /// open, accumulated live as `.usage` events arrive).
    public private(set) var totalInputTokens = 0
    public private(set) var totalOutputTokens = 0
    public private(set) var totalCostUSD = 0.0

    /// Optional per-conversation budget in USD. When exceeded, `isOverBudget`
    /// becomes true and the panel gates further sends until raised.
    public var budgetUSD: Double?
    public var isOverBudget: Bool {
        guard let budgetUSD, budgetUSD > 0 else { return false }
        return totalCostUSD >= budgetUSD
    }

    private let store: AgentStore?
    private let registry: AgentRegistry
    private var activeHandle: AgentTurnHandle?
    private var pendingText = ""
    private var titleSet = false
    // Checkpoint taken before an Auto-mode turn, so its file changes can be
    // reviewed/reverted once it finishes.
    private var turnCheckpointManager: AgentCheckpointManager?
    private var turnCheckpoint: AgentCheckpointManager.Checkpoint?

    public init(conversationID: Int64, cliID: String, model: AgentModel?,
                workingDirectory: String,
                store: AgentStore? = AgentStore.shared,
                registry: AgentRegistry = .shared) {
        self.conversationID = conversationID
        self.cliID = cliID
        self.model = model
        self.workingDirectory = workingDirectory
        self.store = store
        self.registry = registry
        if let u = store?.usage(conversation: conversationID) {
            totalInputTokens = u.input
            totalOutputTokens = u.output
            totalCostUSD = u.cost
        }
    }

    /// Start a brand-new conversation backed by a fresh store row.
    public static func create(cliID: String, model: AgentModel?, workingDirectory: String,
                              title: String = "New conversation",
                              store: AgentStore? = AgentStore.shared,
                              registry: AgentRegistry = .shared) -> AgentConversationController? {
        guard let id = store?.createConversation(title: title, cwd: workingDirectory) else {
            // No store (e.g. disk failure) — fall back to an ephemeral id so the
            // panel still works in-memory this session.
            return AgentConversationController(conversationID: -1, cliID: cliID, model: model,
                                               workingDirectory: workingDirectory,
                                               store: nil, registry: registry)
        }
        store?.setCurrentCLIModel(id, cli: cliID, model: model?.id)
        return AgentConversationController(conversationID: id, cliID: cliID, model: model,
                                           workingDirectory: workingDirectory,
                                           store: store, registry: registry)
    }

    /// Reopen an existing persisted conversation (from history).
    public static func open(_ row: AgentStore.ConversationRow,
                            store: AgentStore? = AgentStore.shared,
                            registry: AgentRegistry = .shared) -> AgentConversationController {
        let cliID = row.currentCLI ?? registry.availableCLIs().first?.id ?? "claude"
        let model = registry.models(for: cliID).first { $0.id == row.currentModel }
        let cwd = row.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        let c = AgentConversationController(conversationID: row.id, cliID: cliID, model: model,
                                            workingDirectory: cwd, store: store, registry: registry)
        c.titleSet = true
        return c
    }

    // MARK: - Switching CLI / model

    public func switchCLI(_ newCLIID: String, model newModel: AgentModel?) {
        cliID = newCLIID
        model = newModel
        store?.setCurrentCLIModel(conversationID, cli: cliID, model: model?.id)
    }

    public func switchModel(_ newModel: AgentModel) {
        model = newModel
        store?.setCurrentCLIModel(conversationID, cli: cliID, model: model?.id)
    }

    // MARK: - Sending a turn

    @discardableResult
    public func send(_ text: String) -> Bool {
        return send(text, editorContext: nil)
    }

    /// Send a turn, optionally augmented with editor context. The user's typed
    /// text is persisted verbatim (with `@`-mentions intact for display); the
    /// agent receives an augmented prompt where mentions are expanded to file
    /// bodies and a lightweight editor-context block is prepended.
    @discardableResult
    public func send(_ text: String, editorContext: AgentContextProvider.EditorContextSnapshot?) -> Bool {
        return send(text, editorContext: editorContext, attachmentPaths: [])
    }

    /// Send a turn, attaching `attachmentPaths` (files chosen as `@`-mention
    /// chips) in addition to any `@token`s typed in `text`. `text` is persisted
    /// verbatim as the user message (chips rendered as `@name` by the caller).
    @discardableResult
    public func send(_ text: String,
                     editorContext: AgentContextProvider.EditorContextSnapshot?,
                     attachmentPaths: [String]) -> Bool {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming, let cli = registry.cli(withID: cliID) else { return false }

        store?.appendMessage(conversation: conversationID, role: "user", content: prompt, kind: "text")
        // Title the conversation from its first user message.
        if !titleSet {
            store?.renameConversation(conversationID, title: Self.makeTitle(prompt))
            titleSet = true
        }
        delegate?.conversationDidUpdate(self)

        // The agent-facing prompt: `@`-mentions expanded to file bodies + a
        // lightweight editor-context block prepended. Falls back to the raw
        // prompt when there is nothing to add.
        let agentPrompt = AgentContextProvider.composeAgentPrompt(
            typed: prompt, workspaceRoot: workingDirectory, context: editorContext,
            explicitPaths: attachmentPaths)

        // Native resume if we have a session for THIS cli; otherwise re-seed the
        // prior transcript so a freshly-switched CLI keeps continuity.
        let native = store?.nativeSession(conversation: conversationID, cli: cliID)
        let reseed = (native == nil) ? buildReseedTranscript() : nil

        let req = AgentTurnRequest(prompt: agentPrompt, model: model?.id,
                                   workingDirectory: workingDirectory,
                                   nativeSessionID: native, reseedTranscript: reseed,
                                   permission: permission)
        // Snapshot the workspace before an Auto-mode turn so its on-disk edits
        // can be reviewed and reverted. Plan/read-only turns make no edits, so
        // no checkpoint is needed.
        turnCheckpoint = nil
        turnCheckpointManager = nil
        if permission == .auto {
            let mgr = AgentCheckpointManager(workingDirectory: workingDirectory)
            if mgr.isUsable {
                turnCheckpointManager = mgr
                turnCheckpoint = mgr.snapshot(label: Self.makeTitle(prompt))
            }
        }

        isStreaming = true
        pendingText = ""
        activeHandle = cli.startTurn(req) { [weak self] ev in self?.handle(ev) }
        return true
    }

    public func cancel() {
        activeHandle?.cancel()
    }

    private func handle(_ event: AgentEvent) {
        switch event {
        case .sessionStarted(let id, _):
            if !id.isEmpty {
                store?.setNativeSession(conversation: conversationID, cli: cliID, sessionID: id)
            }
        case .textDelta(let t):
            pendingText += t
            delegate?.conversation(self, didStreamText: t)
        case .thinkingDelta(let t):
            delegate?.conversation(self, didStreamThinking: t)
        case .toolCall(let tc):
            delegate?.conversation(self, didReceive: tc)
        case .toolResult(let id, let ok, let output):
            delegate?.conversation(self, didReceiveToolResult: id, ok: ok, output: output)
        case .permissionRequest(let pr):
            delegate?.conversation(self, didRequest: pr)
        case .usage(let u):
            totalInputTokens += u.inputTokens
            totalOutputTokens += u.outputTokens
            totalCostUSD += (u.costUSD ?? 0)
            store?.addUsage(conversation: conversationID,
                            input: u.inputTokens, output: u.outputTokens, cost: u.costUSD ?? 0)
            delegate?.conversation(self, didUpdateUsageInputTokens: totalInputTokens,
                                   outputTokens: totalOutputTokens, costUSD: totalCostUSD)
        case .turnFinished:
            finishTurn(error: nil)
        case .error(let msg):
            finishTurn(error: msg)
        }
    }

    private func finishTurn(error: String?) {
        let reply = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reply.isEmpty {
            store?.appendMessage(conversation: conversationID, role: "assistant",
                                 content: reply, kind: "text")
        }
        if let error {
            store?.appendMessage(conversation: conversationID, role: "system",
                                 content: error, kind: "error")
        }
        isStreaming = false
        activeHandle = nil
        if error == nil { updateEmbedding() }

        // Surface on-disk changes the turn made (Auto mode) for review/revert.
        if let cp = turnCheckpoint, let mgr = turnCheckpointManager {
            let diff = mgr.diff(since: cp)
            if !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                delegate?.conversation(self, didChangeFilesWithDiff: diff,
                                       revert: { mgr.restore(to: cp) })
            }
        }
        turnCheckpoint = nil
        turnCheckpointManager = nil

        delegate?.conversationDidUpdate(self)
        delegate?.conversation(self, turnDidFinish: error)
    }

    /// Re-embed the whole conversation for semantic recall (cheap, offline).
    private func updateEmbedding() {
        guard let rows = store?.messages(conversation: conversationID), !rows.isEmpty else { return }
        let text = rows.filter { $0.kind != "error" }.map { $0.content }.joined(separator: "\n")
        store?.setEmbedding(conversation: conversationID,
                            vector: AgentEmbedder.embed(text),
                            model: "fnv-ngram-v1")
    }

    private static func makeTitle(_ prompt: String) -> String {
        let firstLine = prompt.split(separator: "\n").first.map(String.init) ?? prompt
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 48 ? String(trimmed.prefix(48)) + "…" : trimmed
    }

    /// A compact transcript of this conversation for seeding other harnesses
    /// (e.g. best-of-N comparison runs) with the same context. Nil if empty.
    public func contextReseed() -> String? {
        buildReseedTranscript()
    }

    // MARK: - Re-seed transcript (cross-CLI continuity)

    /// A compact rendering of the persisted transcript, fed to a fresh session
    /// when switching CLIs so the new agent "remembers" the conversation.
    private func buildReseedTranscript(maxChars: Int = 12_000) -> String? {
        guard let rows = store?.messages(conversation: conversationID), !rows.isEmpty else { return nil }
        var lines: [String] = []
        for m in rows where m.kind != "error" {
            let who = m.role == "user" ? "User" : (m.role == "assistant" ? "Assistant" : m.role.capitalized)
            lines.append("\(who): \(m.content)")
        }
        var text = lines.joined(separator: "\n\n")
        if text.count > maxChars { text = "…\n" + String(text.suffix(maxChars)) }
        return text.isEmpty ? nil : text
    }
}
