// SPDX-License-Identifier: MIT
// Sourcepad — normalized agent event model.
//
// Every agent CLI (claude, codex, opencode, …) speaks its own JSON event
// dialect on stdout. Each adapter parses that dialect into this single
// `AgentEvent` vocabulary so the rest of Sourcepad — the panel, the store,
// the approval UI — never has to care which CLI produced a turn.
//
// Deliberately Foundation-only (no AppKit) so the whole engine can be driven
// and verified from a headless test harness, the way the terminal spike was.

import Foundation

/// A model the user can pick for a turn: the raw id passed to the CLI's
/// `--model` flag plus a human label and the CLI it belongs to.
public struct AgentModel: Hashable, Codable {
    public let cliID: String        // "claude" | "codex" | "opencode"
    public let id: String           // value passed to --model (e.g. "sonnet", "opencode/big-pickle")
    public let displayName: String

    public init(cliID: String, id: String, displayName: String) {
        self.cliID = cliID
        self.id = id
        self.displayName = displayName
    }
}

/// One turn of work handed to an adapter.
public struct AgentTurnRequest {
    /// The user's message for this turn.
    public let prompt: String
    /// Model id to pass via `--model`; nil → the CLI's own default.
    public let model: String?
    /// Absolute path the agent runs in (workspace root / doc dir / $HOME).
    public let workingDirectory: String
    /// This CLI's native session id to resume, if continuing its own thread.
    public let nativeSessionID: String?
    /// Condensed prior transcript to seed a *fresh* session when the user has
    /// just switched CLIs (cross-CLI continuity). nil when resuming natively.
    public let reseedTranscript: String?
    /// Permission posture for this turn (maps to per-CLI sandbox/flags).
    public let permission: AgentPermissionMode

    public init(prompt: String,
                model: String?,
                workingDirectory: String,
                nativeSessionID: String? = nil,
                reseedTranscript: String? = nil,
                permission: AgentPermissionMode = .ask) {
        self.prompt = prompt
        self.model = model
        self.workingDirectory = workingDirectory
        self.nativeSessionID = nativeSessionID
        self.reseedTranscript = reseedTranscript
        self.permission = permission
    }
}

/// Coarse permission posture for a turn. Granular per-action approval (the
/// `.ask` case) is delivered in Phase 3 via each CLI's approval channel;
/// until then `.ask` maps to the safest mode each CLI supports.
public enum AgentPermissionMode: String, Codable {
    case readOnly   // no writes, no shell side effects
    case ask        // prompt for each privileged action (Phase 3)
    case auto       // run freely (yolo) — explicit opt-in only
}

/// A tool invocation the agent reports (running or completed).
public struct AgentToolCall: Codable {
    public enum Kind: String, Codable {
        case fileEdit, fileCreate, fileRead, shell, search, web, other
    }
    public let id: String
    public let kind: Kind
    public let title: String        // "Edit Foo.swift", "$ npm test", …
    public let detail: String?      // diff / command / args, for the card body

    public init(id: String, kind: Kind, title: String, detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

/// Token / cost accounting for a turn.
public struct AgentUsage: Codable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let costUSD: Double?

    public init(inputTokens: Int, outputTokens: Int, costUSD: Double? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
    }
}

/// A pending request from the agent to perform a privileged action. The UI
/// calls `approve()` / `deny()` exactly once; the adapter wires `responder`
/// to whatever channel actually gates the CLI (Phase 3).
public final class AgentPermissionRequest {
    public let id: String
    public let toolCall: AgentToolCall
    private let responder: (Bool) -> Void
    private var answered = false

    public init(id: String, toolCall: AgentToolCall, responder: @escaping (Bool) -> Void) {
        self.id = id
        self.toolCall = toolCall
        self.responder = responder
    }

    public func approve() { respond(true) }
    public func deny() { respond(false) }

    private func respond(_ allow: Bool) {
        guard !answered else { return }
        answered = true
        responder(allow)
    }
}

/// The single event vocabulary every adapter emits. Delivered on the main queue.
public enum AgentEvent {
    /// Native session id (+ resolved model) — captured for resume.
    case sessionStarted(id: String, model: String?)
    /// Streamed reasoning text (render collapsed).
    case thinkingDelta(String)
    /// Streamed assistant answer text.
    case textDelta(String)
    /// The agent is invoking / has invoked a tool.
    case toolCall(AgentToolCall)
    /// Result of a tool the agent ran.
    case toolResult(id: String, ok: Bool, output: String?)
    /// The agent is asking permission for a privileged action (Phase 3).
    case permissionRequest(AgentPermissionRequest)
    /// Token / cost accounting.
    case usage(AgentUsage)
    /// The turn finished cleanly.
    case turnFinished(stopReason: String?)
    /// The turn failed.
    case error(String)
}
