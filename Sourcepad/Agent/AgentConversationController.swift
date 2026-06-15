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
    /// The agent wants permission for a privileged action (Phase 3).
    func conversation(_ c: AgentConversationController, didRequest permission: AgentPermissionRequest)
    /// The turn ended; `error` is nil on success.
    func conversation(_ c: AgentConversationController, turnDidFinish error: String?)
}

// Default no-ops so the panel only implements what it needs.
public extension AgentConversationDelegate {
    func conversationDidUpdate(_ c: AgentConversationController) {}
    func conversation(_ c: AgentConversationController, didStreamText delta: String) {}
    func conversation(_ c: AgentConversationController, didStreamThinking delta: String) {}
    func conversation(_ c: AgentConversationController, didReceive toolCall: AgentToolCall) {}
    func conversation(_ c: AgentConversationController, didRequest permission: AgentPermissionRequest) {}
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

    private let store: AgentStore?
    private let registry: AgentRegistry
    private var activeHandle: AgentTurnHandle?
    private var pendingText = ""

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
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming, let cli = registry.cli(withID: cliID) else { return false }

        store?.appendMessage(conversation: conversationID, role: "user", content: prompt, kind: "text")
        delegate?.conversationDidUpdate(self)

        // Native resume if we have a session for THIS cli; otherwise re-seed the
        // prior transcript so a freshly-switched CLI keeps continuity.
        let native = store?.nativeSession(conversation: conversationID, cli: cliID)
        let reseed = (native == nil) ? buildReseedTranscript() : nil

        let req = AgentTurnRequest(prompt: prompt, model: model?.id,
                                   workingDirectory: workingDirectory,
                                   nativeSessionID: native, reseedTranscript: reseed,
                                   permission: permission)
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
        case .toolResult:
            break
        case .permissionRequest(let pr):
            delegate?.conversation(self, didRequest: pr)
        case .usage:
            break
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
        delegate?.conversationDidUpdate(self)
        delegate?.conversation(self, turnDidFinish: error)
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
