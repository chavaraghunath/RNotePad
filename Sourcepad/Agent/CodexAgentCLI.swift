// SPDX-License-Identifier: MIT
// Sourcepad — Codex CLI adapter.
//
// Drives `codex exec --json` one turn at a time. Event dialect (verified):
//   {type:thread.started, thread_id}                    → sessionStarted
//   {type:turn.started}
//   {type:item.completed, item:{type:agent_message|reasoning|command_execution|file_change, …}}
//   {type:turn.completed, usage}                        → usage + finished
//
// Resume via `codex exec resume <thread_id>`. Needs a trusted/git dir or
// --skip-git-repo-check; stdin is closed so it doesn't wait for piped input.

import Foundation

public final class CodexAgentCLI: AgentCLI {

    public let id = "codex"
    public let displayName = "Codex"

    public var executableURL: URL? { AgentExecutable.locate("codex") }
    public var isAvailable: Bool { executableURL != nil }

    public func discoverModels() -> [AgentModel] {
        // Codex exposes no machine-readable model list (`--model` takes a free
        // string), so we offer the configured default (from ~/.codex/config.toml)
        // first, then the current model family shipped with the installed CLI.
        // The ids below were verified against the codex 0.139.0 model catalog
        // (the gpt-5.1-codex generation is retired); the user can still type any
        // other id. When the CLI ships new models, refresh this list.
        var models: [AgentModel] = []
        if let configured = configuredModel() {
            models.append(AgentModel(cliID: id, id: configured, displayName: "\(configured) (config)"))
        }
        let current: [(String, String)] = [
            ("gpt-5.3-codex", "GPT-5.3 Codex"),   // current coding-tuned flagship
            ("gpt-5.2-codex", "GPT-5.2 Codex"),   // prior coding-tuned
            ("gpt-5.5",       "GPT-5.5"),          // newest general flagship
            ("gpt-5.4",       "GPT-5.4"),
            ("gpt-5.4-mini",  "GPT-5.4 mini"),     // fast / lower cost
        ]
        for (mid, label) in current where !models.contains(where: { $0.id == mid }) {
            models.append(AgentModel(cliID: id, id: mid, displayName: label))
        }
        return models
    }

    private func configuredModel() -> String? {
        let path = "\(NSHomeDirectory())/.codex/config.toml"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("model") && t.contains("=") {
                let v = t.split(separator: "=", maxSplits: 1)[1]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !v.isEmpty { return v }
            }
        }
        return nil
    }

    @discardableResult
    public func startTurn(_ request: AgentTurnRequest,
                          onEvent: @escaping (AgentEvent) -> Void) -> AgentTurnHandle {
        guard let exe = executableURL else {
            DispatchQueue.main.async { onEvent(.error("codex not installed")) }
            return NullTurnHandle()
        }

        var args = ["exec"]
        if let sid = request.nativeSessionID { args += ["resume", sid] }
        args += ["--json", "--skip-git-repo-check", "-C", request.workingDirectory]
        switch request.permission {
        case .readOnly, .ask: args += ["--sandbox", "read-only"]
        case .auto:
            // Sandbox toggle (Settings ▸ Agent CLIs): when on, confine writes to
            // the working directory; when off, grant full disk access.
            let sandbox = Preferences.shared.agentSandboxEnabled ? "workspace-write" : "danger-full-access"
            args += ["--sandbox", sandbox, "-c", "approval_policy=\"never\""]
        }
        if let model = request.model { args += ["-m", model] }
        args.append(composePrompt(request))

        var finished = false
        let emit: (AgentEvent) -> Void = { ev in
            if case .turnFinished = ev { finished = true }
            if case .error = ev { finished = true }
            onEvent(ev)
        }

        let runner = AgentProcessRunner(
            executable: exe,
            arguments: args,
            workingDirectory: request.workingDirectory,
            onLine: { dict in Self.parse(dict, emit: emit) },
            onExit: { code, stderr in
                guard !finished else { return }
                if code == 0 { onEvent(.turnFinished(stopReason: nil)) }
                else { onEvent(.error(stderr.isEmpty ? "codex exited \(code)" : stderr)) }
            })
        runner.start()
        return runner
    }

    private func composePrompt(_ r: AgentTurnRequest) -> String {
        guard let seed = r.reseedTranscript, !seed.isEmpty else { return r.prompt }
        return "Prior conversation for context:\n\n\(seed)\n\n---\n\nContinue. \(r.prompt)"
    }

    // MARK: - Event parsing

    private static func parse(_ dict: [String: Any], emit: @escaping (AgentEvent) -> Void) {
        switch dict["type"] as? String {
        case "thread.started":
            emit(.sessionStarted(id: dict["thread_id"] as? String ?? "", model: nil))
        case "item.completed":
            guard let item = dict["item"] as? [String: Any] else { return }
            parseItem(item, emit: emit)
        case "turn.completed":
            if let usage = dict["usage"] as? [String: Any] {
                emit(.usage(AgentUsage(
                    inputTokens: (usage["input_tokens"] as? Int) ?? 0,
                    outputTokens: (usage["output_tokens"] as? Int) ?? 0,
                    costUSD: nil)))
            }
            emit(.turnFinished(stopReason: nil))
        case "error":
            emit(.error(dict["message"] as? String ?? "codex error"))
        default:
            break
        }
    }

    private static func parseItem(_ item: [String: Any], emit: @escaping (AgentEvent) -> Void) {
        let itemID = item["id"] as? String ?? UUID().uuidString
        switch item["type"] as? String {
        case "agent_message":
            if let t = item["text"] as? String, !t.isEmpty { emit(.textDelta(t)) }
        case "reasoning":
            if let t = item["text"] as? String, !t.isEmpty { emit(.thinkingDelta(t)) }
        case "command_execution":
            let cmd = item["command"] as? String ?? "command"
            emit(.toolCall(AgentToolCall(id: itemID, kind: .shell, title: "$ \(cmd)", detail: cmd)))
            if let out = item["aggregated_output"] as? String {
                let ok = (item["exit_code"] as? Int ?? 0) == 0
                emit(.toolResult(id: itemID, ok: ok, output: out))
            }
        case "file_change":
            let path = (item["path"] as? String).map { ($0 as NSString).lastPathComponent } ?? "file"
            emit(.toolCall(AgentToolCall(id: itemID, kind: .fileEdit, title: "Edit \(path)",
                                         detail: item["diff"] as? String)))
        default:
            break
        }
    }
}
