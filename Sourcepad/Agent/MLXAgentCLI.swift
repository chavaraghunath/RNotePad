// SPDX-License-Identifier: MIT
// Sourcepad — run locally-installed MLX models in the agent panel.
//
// MLX models are raw chat LLMs (no agentic tools). A turn prefers the persistent
// `mlx_lm.server` (model stays loaded → fast multi-turn + token streaming) and
// falls back to one-shot `mlx_lm.generate` if the server can't start. The CLI
// appears only when MLX is installed AND a model is downloaded; its model list is
// the installed MLX models. Continuity uses the re-seed transcript.

import Foundation

/// A turn handle that cancels whichever backend (server stream or generate
/// subprocess) ends up serving the turn, even though the choice is made async.
private final class MLXTurnHandle: AgentTurnHandle {
    var onCancel: (() -> Void)?
    var stream: MLXChatStream?   // retained while streaming
    func cancel() { onCancel?() }
}

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
        let handle = MLXTurnHandle()

        // Prefer the persistent server (streaming); fall back to one-shot generate.
        MLXServer.shared.ensure(model: model) { ready in
            if ready, let base = MLXServer.shared.baseURL {
                let stream = MLXChatStream(
                    onDelta: { onEvent(.textDelta($0)) },
                    onDone: {
                        onEvent(.usage(AgentUsage(inputTokens: 0, outputTokens: 0, costUSD: 0)))
                        onEvent(.turnFinished(stopReason: nil))
                    },
                    onError: { onEvent(.error($0)) })
                handle.stream = stream
                handle.onCancel = { stream.cancel() }
                stream.start(baseURL: base, model: model, prompt: prompt)
            } else {
                let runner = MLXAgentCLI.startGenerate(exe: exe, model: model, prompt: prompt, onEvent: onEvent)
                handle.onCancel = { runner.cancel() }
            }
        }
        return handle
    }

    // MARK: - One-shot generate fallback

    private static func startGenerate(exe: URL, model: String, prompt: String,
                                      onEvent: @escaping (AgentEvent) -> Void) -> AgentProcessRunner {
        var buffer = ""
        var finished = false
        let runner = AgentProcessRunner(
            executable: exe,
            arguments: ["--model", model, "--prompt", prompt, "--max-tokens", "2048"],
            workingDirectory: NSTemporaryDirectory(),
            onLine: { _ in },
            onRawLine: { line in buffer += line + "\n" },
            onExit: { code, stderr in
                guard !finished else { return }
                finished = true
                let result = MLXOutputParser.parse(buffer)
                if result.text.isEmpty {
                    onEvent(.error(stderr.isEmpty ? "mlx_lm exited \(code)" : stderr)); return
                }
                onEvent(.textDelta(result.text))
                onEvent(.usage(AgentUsage(inputTokens: result.promptTokens,
                                          outputTokens: result.generationTokens, costUSD: 0)))
                onEvent(.turnFinished(stopReason: nil))
            })
        runner.start()
        return runner
    }

    /// mlx_lm is stateless, so seed prior context into the prompt.
    private static func composePrompt(_ r: AgentTurnRequest) -> String {
        guard let seed = r.reseedTranscript, !seed.isEmpty else { return r.prompt }
        return "Prior conversation for context:\n\n\(seed)\n\n---\n\n\(r.prompt)"
    }
}
