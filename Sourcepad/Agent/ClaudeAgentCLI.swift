// SPDX-License-Identifier: MIT
// Sourcepad — Claude Code adapter.
//
// Drives `claude -p --output-format stream-json --verbose` one turn at a time.
// Event dialect (verified, see AGENT-CLI-KNOWLEDGE-BASE.md):
//   {type:system, subtype:init, session_id, model}      → sessionStarted
//   {type:assistant, message:{content:[thinking|text|tool_use]}}
//   {type:user, message:{content:[tool_result]}}
//   {type:result, subtype, usage, total_cost_usd, is_error} → usage + finished
//
// Resume via --resume <session_id>. No list-models command, so models are a
// curated set the user can extend by typing a full id.

import Foundation

public final class ClaudeAgentCLI: AgentCLI {

    public let id = "claude"
    public let displayName = "Claude Code"

    public var executableURL: URL? { AgentExecutable.locate("claude") }
    public var isAvailable: Bool { executableURL != nil }

    public func discoverModels() -> [AgentModel] {
        // Claude Code has no `list-models`; ship a curated set of aliases the
        // CLI resolves. Users can also type a full model id.
        [
            ("opus",   "Claude Opus 4.8"),
            ("sonnet", "Claude Sonnet 4.6"),
            ("haiku",  "Claude Haiku 4.5"),
        ].map { AgentModel(cliID: id, id: $0.0, displayName: $0.1) }
    }

    @discardableResult
    public func startTurn(_ request: AgentTurnRequest,
                          onEvent: @escaping (AgentEvent) -> Void) -> AgentTurnHandle {
        guard let exe = executableURL else {
            DispatchQueue.main.async { onEvent(.error("claude not installed")) }
            return NullTurnHandle()
        }

        var args = ["-p", "--output-format", "stream-json", "--verbose"]
        if let model = request.model { args += ["--model", model] }
        if let sid = request.nativeSessionID { args += ["--resume", sid] }
        switch request.permission {
        case .readOnly, .ask: args += ["--permission-mode", "plan"]   // no edits until Phase 3 approval
        case .auto:           args += ["--dangerously-skip-permissions"]
        }
        args.append(Self.composePrompt(request))

        var finished = false
        let emitFinish: (AgentEvent) -> Void = { ev in
            if case .turnFinished = ev { finished = true }
            if case .error = ev { finished = true }
            onEvent(ev)
        }

        let runner = AgentProcessRunner(
            executable: exe,
            arguments: args,
            workingDirectory: request.workingDirectory,
            onLine: { dict in Self.parse(dict, emit: emitFinish) },
            onExit: { code, stderr in
                guard !finished else { return }
                if code == 0 { onEvent(.turnFinished(stopReason: nil)) }
                else { onEvent(.error(stderr.isEmpty ? "claude exited \(code)" : stderr)) }
            })
        runner.start()
        return runner
    }

    /// When switching CLIs we have no native session to resume, so prepend a
    /// condensed transcript so the fresh session keeps continuity.
    static func composePrompt(_ r: AgentTurnRequest) -> String {
        guard let seed = r.reseedTranscript, !seed.isEmpty else { return r.prompt }
        return "Here is the prior conversation for context:\n\n\(seed)\n\n---\n\nContinue. \(r.prompt)"
    }

    // MARK: - Event parsing

    private static func parse(_ dict: [String: Any], emit: @escaping (AgentEvent) -> Void) {
        guard let type = dict["type"] as? String else { return }
        switch type {
        case "system":
            if (dict["subtype"] as? String) == "init" {
                let sid = dict["session_id"] as? String ?? ""
                emit(.sessionStarted(id: sid, model: dict["model"] as? String))
            }
        case "assistant":
            guard let message = dict["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return }
            for block in content { parseAssistantBlock(block, emit: emit) }
        case "user":
            guard let message = dict["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return }
            for block in content where (block["type"] as? String) == "tool_result" {
                let tid = block["tool_use_id"] as? String ?? ""
                let isError = (block["is_error"] as? Bool) ?? false
                emit(.toolResult(id: tid, ok: !isError, output: AgentJSON.text(block["content"])))
            }
        case "result":
            if let usage = dict["usage"] as? [String: Any] {
                emit(.usage(AgentUsage(
                    inputTokens: (usage["input_tokens"] as? Int) ?? 0,
                    outputTokens: (usage["output_tokens"] as? Int) ?? 0,
                    costUSD: dict["total_cost_usd"] as? Double)))
            }
            let isError = (dict["is_error"] as? Bool) ?? false
            if isError {
                emit(.error(AgentJSON.text(dict["result"]) ?? (dict["subtype"] as? String ?? "error")))
            } else {
                emit(.turnFinished(stopReason: dict["subtype"] as? String))
            }
        default:
            break
        }
    }

    private static func parseAssistantBlock(_ block: [String: Any],
                                            emit: @escaping (AgentEvent) -> Void) {
        switch block["type"] as? String {
        case "thinking":
            if let t = block["thinking"] as? String, !t.isEmpty { emit(.thinkingDelta(t)) }
        case "text":
            if let t = block["text"] as? String, !t.isEmpty { emit(.textDelta(t)) }
        case "tool_use":
            let name = block["name"] as? String ?? "tool"
            let input = block["input"] as? [String: Any] ?? [:]
            emit(.toolCall(AgentToolCall(
                id: block["id"] as? String ?? UUID().uuidString,
                kind: AgentJSON.toolKind(forClaudeTool: name),
                title: AgentJSON.toolTitle(forClaudeTool: name, input: input),
                detail: AgentJSON.toolDetail(forClaudeTool: name, input: input),
                path: AgentJSON.toolPath(forClaudeTool: name, input: input))))
        default:
            break
        }
    }
}

/// A no-op handle returned when a turn can't even start.
final class NullTurnHandle: AgentTurnHandle {
    func cancel() {}
}
