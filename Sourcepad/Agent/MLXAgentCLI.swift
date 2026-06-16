// SPDX-License-Identifier: MIT
// Sourcepad — run locally-installed MLX models in the agent panel.
//
// MLX models are raw chat LLMs (no agentic tools), so a turn = one `mlx_lm.generate`
// run that streams a text answer. The CLI appears only when MLX is installed AND at
// least one model is downloaded; its model list is the installed MLX models.
// Continuity uses the re-seed transcript (mlx_lm.generate is stateless one-shot).

import Foundation

public final class MLXAgentCLI: AgentCLI {

    public let id = "mlx"
    public let displayName = "MLX (local)"

    public var executableURL: URL? { MLXEnvironment.generateBinary() }
    public var isAvailable: Bool {
        executableURL != nil && !MLXModelManager.installedModelIDs().isEmpty
    }

    public func discoverModels() -> [AgentModel] {
        MLXModelManager.installedModelIDs().map {
            AgentModel(cliID: id, id: $0, displayName: ($0 as NSString).lastPathComponent)
        }
    }

    @discardableResult
    public func startTurn(_ request: AgentTurnRequest,
                          onEvent: @escaping (AgentEvent) -> Void) -> AgentTurnHandle {
        guard let exe = executableURL else {
            DispatchQueue.main.async { onEvent(.error("MLX is not installed.")) }
            return NullTurnHandle()
        }
        guard let model = request.model else {
            DispatchQueue.main.async { onEvent(.error("No MLX model selected.")) }
            return NullTurnHandle()
        }

        let prompt = Self.composePrompt(request)
        let args = ["--model", model, "--prompt", prompt, "--max-tokens", "2048"]

        var buffer = ""
        var finished = false
        let runner = AgentProcessRunner(
            executable: exe, arguments: args, workingDirectory: request.workingDirectory,
            onLine: { _ in },
            onRawLine: { line in buffer += line + "\n" },
            onExit: { code, stderr in
                guard !finished else { return }
                finished = true
                let result = MLXOutputParser.parse(buffer)
                if result.text.isEmpty {
                    onEvent(.error(stderr.isEmpty ? "mlx_lm exited \(code)" : stderr))
                    return
                }
                onEvent(.textDelta(result.text))
                onEvent(.usage(AgentUsage(inputTokens: result.promptTokens,
                                          outputTokens: result.generationTokens, costUSD: 0)))
                onEvent(.turnFinished(stopReason: nil))
            })
        runner.start()
        return runner
    }

    /// mlx_lm.generate is stateless, so seed prior context into the prompt.
    private static func composePrompt(_ r: AgentTurnRequest) -> String {
        guard let seed = r.reseedTranscript, !seed.isEmpty else { return r.prompt }
        return "Prior conversation for context:\n\n\(seed)\n\n---\n\n\(r.prompt)"
    }
}
