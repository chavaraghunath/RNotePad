// SPDX-License-Identifier: MIT
// Sourcepad — the pure, side-effect-free logic behind ConfigurableAgentCLI:
// building the argv for a turn and parsing a CLI's output into AgentEvents.
// Kept separate from the process plumbing (and the AgentCLI protocol) so it
// depends only on CLISpec + AgentEvent and is exhaustively headless-testable.

import Foundation

public enum ConfigurableCLILogic {

    /// Prepend the re-seed transcript (cross-CLI continuity) when present.
    public static func composePrompt(spec: CLISpec, request: AgentTurnRequest) -> String {
        guard let seed = request.reseedTranscript, !seed.isEmpty else { return request.prompt }
        return "Prior conversation for context:\n\n\(seed)\n\n---\n\nContinue. \(request.prompt)"
    }

    /// Build the full argv for a turn from the spec + request:
    /// baseArgs, then model flag, then plan/auto args, then the prompt flag+value.
    public static func buildArguments(spec: CLISpec, request: AgentTurnRequest) -> [String] {
        var args = spec.baseArgs
        if let mf = spec.modelFlag, let model = request.model { args += [mf, model] }
        args += (request.permission == .auto ? spec.autoArgs : spec.planArgs)
        args += [spec.promptFlag, composePrompt(spec: spec, request: request)]
        return args
    }

    /// Parse one Gemini `-o stream-json` event (verified schema):
    ///   {"type":"init","session_id":…,"model":…}
    ///   {"type":"message","role":"user"|"assistant","content":…,"delta":true}
    ///   {"type":"result","status":…,"stats":{input_tokens,output_tokens,…}}
    ///   {"type":"error","message":…}
    public static func parseGemini(_ dict: [String: Any], command: String,
                                   emit: (AgentEvent) -> Void) {
        switch dict["type"] as? String {
        case "init":
            // Empty id → the controller re-seeds the transcript for continuity
            // rather than attempting a native resume we don't yet support.
            emit(.sessionStarted(id: "", model: dict["model"] as? String))
        case "message":
            guard (dict["role"] as? String) == "assistant",
                  let content = dict["content"] as? String, !content.isEmpty else { return }
            emit(.textDelta(content))
        case "thought":
            if let t = dict["content"] as? String, !t.isEmpty { emit(.thinkingDelta(t)) }
        case "tool_call", "tool_call_request":
            let name = (dict["name"] as? String) ?? (dict["tool"] as? String) ?? "tool"
            emit(.toolCall(AgentToolCall(id: (dict["id"] as? String) ?? "tool",
                                         kind: .other, title: name, detail: nil)))
        case "result":
            if let stats = dict["stats"] as? [String: Any] {
                emit(.usage(AgentUsage(inputTokens: (stats["input_tokens"] as? Int) ?? 0,
                                       outputTokens: (stats["output_tokens"] as? Int) ?? 0,
                                       costUSD: nil)))
            }
            emit(.turnFinished(stopReason: dict["status"] as? String))
        case "error":
            emit(.error((dict["message"] as? String) ?? "\(command) error"))
        default:
            break
        }
    }
}
