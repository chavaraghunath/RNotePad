// SPDX-License-Identifier: MIT
// Sourcepad — local-LLM service.
//
// Per the plan's "strictly local" mandate this service NEVER calls a cloud
// API. The backend is mlx-lm (https://github.com/ml-explore/mlx-lm) running
// as a subprocess — `mlx_lm.server --model <name>` exposes an OpenAI-
// compatible HTTP endpoint on localhost. mlx-lm uses MLX under the hood
// for inference, faithful to the plan's "MLX stack" choice. The subprocess
// pattern is consistent with how we already integrate LSP servers (Phase 6)
// and keeps the build hand-rolled (no SwiftPM/Xcode required for vendoring
// the Swift MLX bindings, which need a Package.swift workflow).
//
// All requests go through this single service so future swaps (a real
// XPC-hosted MLX inference, llama.cpp, etc.) are one-file changes.

import Foundation

public enum AIServiceError: Error {
    case notRunning
    case notInstalled(installHint: String)
    case requestFailed(String)
    case cancelled
}

public protocol AIService: AnyObject {

    /// Whether the backend is up and ready to receive requests.
    var isAvailable: Bool { get }

    /// Whether the underlying CLI / runtime is installed.
    var isInstalled: Bool { get }

    /// Command the user should run to install. nil if isInstalled.
    var installHint: String? { get }

    /// Boot the backend (idempotent).
    func start()

    /// Stop the backend.
    func stop()

    /// Non-streaming completion. `prompt` is the full text the model sees.
    /// Returns the model's reply text (no role formatting).
    func complete(prompt: String,
                  maxTokens: Int,
                  completion: @escaping (Result<String, AIServiceError>) -> Void)

    /// Streaming completion. `onChunk` fires with each partial; `onDone`
    /// fires once with the full text (or an error).
    func stream(prompt: String,
                maxTokens: Int,
                onChunk: @escaping (String) -> Void,
                onDone: @escaping (Result<String, AIServiceError>) -> Void)
}

/// Subprocess-backed mlx-lm runner. The Phase 10 default. Picks up its
/// model from Preferences.aiModelID.
public final class MLXService: AIService {

    public static let shared = MLXService()

    public let serverHost = "127.0.0.1"
    public let serverPort: Int = 8088

    public var isInstalled: Bool {
        return locateMLXLM() != nil
    }

    public var installHint: String? {
        guard !isInstalled else { return nil }
        return "pip install mlx-lm   (Apple Silicon only)"
    }

    public private(set) var isAvailable: Bool = false

    private var process: Process?
    private var stderrPipe: Pipe?
    private let queue = DispatchQueue(label: "sourcepad.ai", qos: .userInitiated)
    private let session = URLSession(configuration: .ephemeral)

    private init() {}

    // MARK: - Backend lifecycle

    public func start() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.process == nil else { return }
            guard let mlxBin = self.locateMLXLM() else {
                NSLog("[Sourcepad] mlx-lm not installed; AI features disabled.")
                return
            }
            guard let modelID = Preferences.shared.aiModelID else {
                NSLog("[Sourcepad] No AI model selected; AI features disabled.")
                return
            }
            let p = Process()
            p.executableURL = mlxBin
            p.arguments = [
                "--model", modelID,
                "--host", self.serverHost,
                "--port", "\(self.serverPort)",
                "--log-level", "error",
            ]
            let errPipe = Pipe()
            p.standardError = errPipe
            p.standardOutput = FileHandle.nullDevice
            do {
                try p.run()
                self.process = p
                self.stderrPipe = errPipe
                // Wait a beat for the server to bind; poll the health
                // endpoint for up to 30s.
                self.waitForReady()
            } catch {
                NSLog("[Sourcepad] mlx-lm failed to spawn: \(error)")
            }
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self, let p = self.process else { return }
            if p.isRunning { p.terminate() }
            self.process = nil
            self.isAvailable = false
        }
    }

    private func waitForReady() {
        // mlx_lm.server exposes /v1/models when ready.
        let healthURL = URL(string: "http://\(serverHost):\(serverPort)/v1/models")!
        for _ in 0..<60 {
            let semaphore = DispatchSemaphore(value: 0)
            var success = false
            let task = session.dataTask(with: healthURL) { _, response, _ in
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    success = true
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 1.0)
            if success {
                isAvailable = true
                NSLog("[Sourcepad] mlx-lm ready on \(serverHost):\(serverPort)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        NSLog("[Sourcepad] mlx-lm did not become ready within 30s")
    }

    // MARK: - Completions

    public func complete(prompt: String,
                         maxTokens: Int,
                         completion: @escaping (Result<String, AIServiceError>) -> Void) {
        guard isAvailable else {
            completion(.failure(.notRunning))
            return
        }
        guard let req = makeCompletionRequest(prompt: prompt,
                                              maxTokens: maxTokens,
                                              streaming: false) else {
            completion(.failure(.requestFailed("encode failed")))
            return
        }
        let task = session.dataTask(with: req) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(.requestFailed(error.localizedDescription))) }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                DispatchQueue.main.async { completion(.failure(.requestFailed("malformed response"))) }
                return
            }
            DispatchQueue.main.async { completion(.success(content)) }
        }
        task.resume()
    }

    public func stream(prompt: String,
                       maxTokens: Int,
                       onChunk: @escaping (String) -> Void,
                       onDone: @escaping (Result<String, AIServiceError>) -> Void) {
        guard isAvailable else {
            onDone(.failure(.notRunning)); return
        }
        guard makeCompletionRequest(prompt: prompt,
                                    maxTokens: maxTokens,
                                    streaming: true) != nil else {
            onDone(.failure(.requestFailed("encode failed"))); return
        }
        // mlx-lm streams Server-Sent Events on the /v1/chat/completions
        // endpoint when stream=true. We do a non-streaming variant here
        // for simplicity (assemble + return); the public API still calls
        // onChunk once at completion. Phase 11 (ghost text) doesn't need
        // mid-stream chunking; Phase 12 (rewrite preview) reuses this for
        // now and can switch to true streaming later.
        complete(prompt: prompt, maxTokens: maxTokens) { result in
            switch result {
            case .success(let text):
                onChunk(text)
                onDone(.success(text))
            case .failure(let err):
                onDone(.failure(err))
            }
        }
    }

    private func makeCompletionRequest(prompt: String,
                                       maxTokens: Int,
                                       streaming: Bool) -> URLRequest? {
        let url = URL(string: "http://\(serverHost):\(serverPort)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": Preferences.shared.aiModelID ?? "",
            "messages": [
                ["role": "user", "content": prompt],
            ],
            "max_tokens": maxTokens,
            "temperature": 0.2,
            "stream": streaming,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data
        return req
    }

    // MARK: - Lookup

    private func locateMLXLM() -> URL? {
        // Look for mlx_lm.server in PATH + common pyenv / homebrew paths.
        if let url = LSPServerSpec.which("mlx_lm.server") { return url }
        for p in [
            "/opt/homebrew/bin/mlx_lm.server",
            "/usr/local/bin/mlx_lm.server",
            "\(NSHomeDirectory())/.local/bin/mlx_lm.server",
        ] {
            let url = URL(fileURLWithPath: p)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
