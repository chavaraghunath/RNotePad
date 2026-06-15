// SPDX-License-Identifier: MIT
// Sourcepad — opencode adapter.
//
// Drives `opencode run --format json` one turn at a time. Event dialect (verified):
//   {type:step_start,  sessionID, part}                 → sessionStarted
//   {type:text,        part:{text}}                      → textDelta
//   {type:reasoning,   part:{text}}                      → thinkingDelta
//   {type:tool,        part:{…}}                         → toolCall
//   {type:step_finish, part:{tokens, cost}}             → usage
//
// Every event carries `sessionID` (ses_…). Resume via --session <id>.
// Models come from `opencode models` (depends on authenticated providers).

import Foundation

public final class OpencodeAgentCLI: AgentCLI {

    public let id = "opencode"
    public let displayName = "opencode"

    public var executableURL: URL? { AgentExecutable.locate("opencode") }
    public var isAvailable: Bool { executableURL != nil }

    public func discoverModels() -> [AgentModel] {
        guard let exe = executableURL else { return [] }
        let p = Process()
        p.executableURL = exe
        p.arguments = ["models"]
        p.environment = AgentProcessRunner.inheritedEnvironment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            // Lines look like "provider/model". Skip noise.
            guard s.contains("/"), !s.contains(" "), s.count < 120 else { return nil }
            return AgentModel(cliID: id, id: s, displayName: s)
        }
    }

    @discardableResult
    public func startTurn(_ request: AgentTurnRequest,
                          onEvent: @escaping (AgentEvent) -> Void) -> AgentTurnHandle {
        guard let exe = executableURL else {
            DispatchQueue.main.async { onEvent(.error("opencode not installed")) }
            return NullTurnHandle()
        }

        var args = ["run", "--format", "json"]
        if let model = request.model { args += ["-m", model] }
        if let sid = request.nativeSessionID { args += ["--session", sid] }
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
                else { onEvent(.error(stderr.isEmpty ? "opencode exited \(code)" : stderr)) }
            })
        runner.start()
        return runner
    }

    private func composePrompt(_ r: AgentTurnRequest) -> String {
        guard let seed = r.reseedTranscript, !seed.isEmpty else { return r.prompt }
        return "Prior conversation for context:\n\n\(seed)\n\n---\n\nContinue. \(r.prompt)"
    }

    // MARK: - Event parsing

    private static var sessionEmitted = Set<String>()

    private static func parse(_ dict: [String: Any], emit: @escaping (AgentEvent) -> Void) {
        let part = dict["part"] as? [String: Any]
        switch dict["type"] as? String {
        case "step_start":
            if let sid = dict["sessionID"] as? String {
                emit(.sessionStarted(id: sid, model: nil))
            }
        case "text":
            if let t = part?["text"] as? String, !t.isEmpty { emit(.textDelta(t)) }
        case "reasoning":
            if let t = part?["text"] as? String, !t.isEmpty { emit(.thinkingDelta(t)) }
        case "tool":
            let name = part?["tool"] as? String ?? "tool"
            emit(.toolCall(AgentToolCall(id: part?["id"] as? String ?? UUID().uuidString,
                                         kind: .other, title: name, detail: nil)))
        case "step_finish":
            if let tokens = part?["tokens"] as? [String: Any] {
                emit(.usage(AgentUsage(
                    inputTokens: (tokens["input"] as? Int) ?? 0,
                    outputTokens: (tokens["output"] as? Int) ?? 0,
                    costUSD: part?["cost"] as? Double)))
            }
        case "error":
            emit(.error((part?["message"] as? String) ?? "opencode error"))
        default:
            break
        }
    }
}
