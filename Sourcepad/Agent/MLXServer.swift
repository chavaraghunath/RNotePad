// SPDX-License-Identifier: MIT
// Sourcepad — manage a persistent `mlx_lm.server` so a model stays loaded in RAM
// for fast multi-turn chat + token streaming (vs reloading per one-shot generate).
//
// One server at a time on a fixed localhost port. `ensure(model:)` starts (or
// restarts for a new model) and resolves once the OpenAI-compatible API answers.
// Shut down on app quit.

import Foundation

public final class MLXServer {

    public static let shared = MLXServer()

    private let host = "127.0.0.1"
    private let port = 8765
    public var baseURL: URL? { URL(string: "http://\(host):\(port)") }

    private var process: Process?
    private var loadedModel: String?
    private let queue = DispatchQueue(label: "sourcepad.mlx.server")

    /// Ensure the server is up and serving `model`. Completion(true) on the main
    /// queue once the API responds; false if it can't be started.
    public func ensure(model: String, completion: @escaping (Bool) -> Void) {
        queue.async {
            if self.loadedModel == model, self.process?.isRunning == true, self.pingModels() {
                DispatchQueue.main.async { completion(true) }
                return
            }
            // Reuse a server from a previous session if it's already serving this
            // model (we don't own the Process, but the API is live).
            if self.process == nil, self.servedModel() == model {
                self.loadedModel = model
                DispatchQueue.main.async { completion(true) }
                return
            }
            self.stopSync()
            guard let exe = MLXEnvironment.serverBinary() else {
                DispatchQueue.main.async { completion(false) }; return
            }
            let p = Process()
            p.executableURL = exe
            p.arguments = ["--model", model, "--host", self.host, "--port", "\(self.port)", "--log-level", "WARNING"]
            p.environment = AgentProcessRunner.inheritedEnvironment()
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch {
                DispatchQueue.main.async { completion(false) }; return
            }
            self.process = p
            self.loadedModel = model
            let ready = self.waitReady(timeoutSeconds: 90)   // model load can take a while
            if !ready { self.stopSync() }
            DispatchQueue.main.async { completion(ready) }
        }
    }

    public func shutdown() { queue.sync { stopSync() } }

    // MARK: - Internals

    private func stopSync() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        loadedModel = nil
    }

    private func waitReady(timeoutSeconds: Int) -> Bool {
        for _ in 0..<(timeoutSeconds * 2) {
            if process?.isRunning != true { return false }
            if pingModels() { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    /// The model id an already-running server reports (nil if none). Off-main.
    private func servedModel() -> String? {
        guard let url = baseURL?.appendingPathComponent("v1/models") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        let sem = DispatchSemaphore(value: 0)
        var model: String?
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if (resp as? HTTPURLResponse)?.statusCode == 200, let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = obj["data"] as? [[String: Any]], let first = arr.first {
                model = first["id"] as? String
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 3)
        return model
    }

    /// Synchronous health check (called off the main thread).
    private func pingModels() -> Bool {
        guard let url = baseURL?.appendingPathComponent("v1/models") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            ok = (resp as? HTTPURLResponse)?.statusCode == 200
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 3)
        return ok
    }
}
