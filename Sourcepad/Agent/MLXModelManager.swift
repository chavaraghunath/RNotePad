// SPDX-License-Identifier: MIT
// Sourcepad — installed MLX models (the local side of the registry).
//
// Pulled models live in the Hugging Face hub cache. This lists what's installed,
// pulls new ones (via huggingface-cli, streaming progress), and removes them.

import Foundation

public enum MLXModelManager {

    /// The Hugging Face hub cache directory (honours HF_HOME / HUGGINGFACE_HUB_CACHE).
    public static var cacheHubDir: URL {
        let env = ProcessInfo.processInfo.environment
        if let hub = env["HUGGINGFACE_HUB_CACHE"], !hub.isEmpty {
            return URL(fileURLWithPath: hub)
        }
        if let hf = env["HF_HOME"], !hf.isEmpty {
            return URL(fileURLWithPath: hf).appendingPathComponent("hub")
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache/huggingface/hub")
    }

    /// Reconstruct a model id from a hub cache dir name. The cache encodes
    /// `mlx-community/Name` as `models--mlx-community--Name`. Returns nil for
    /// non-mlx-community entries. Pure (headless-testable).
    public static func modelID(fromCacheDir dir: String) -> String? {
        let prefix = "models--mlx-community--"
        guard dir.hasPrefix(prefix) else { return nil }
        let name = String(dir.dropFirst(prefix.count))
        guard !name.isEmpty else { return nil }
        return "mlx-community/\(name)"
    }

    private static func cacheDirName(for modelID: String) -> String {
        "models--" + modelID.replacingOccurrences(of: "/", with: "--")
    }

    /// mlx-community models that are fully present in the cache, sorted.
    public static func installedModelIDs() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: cacheHubDir.path) else { return [] }
        return entries.compactMap { modelID(fromCacheDir: $0) }
            .filter { isFullyDownloaded($0) }
            .sorted()
    }

    public static func isInstalled(_ modelID: String) -> Bool {
        isFullyDownloaded(modelID)
    }

    /// True when the cached snapshot has real weights (a `.safetensors` or a
    /// `config.json`) — not just a partial/metadata stub.
    static func isFullyDownloaded(_ modelID: String) -> Bool {
        let snap = cacheHubDir.appendingPathComponent(cacheDirName(for: modelID))
            .appendingPathComponent("snapshots")
        guard let revs = try? FileManager.default.contentsOfDirectory(atPath: snap.path) else { return false }
        for rev in revs {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: snap.appendingPathComponent(rev).path)) ?? []
            if files.contains(where: { $0.hasSuffix(".safetensors") || $0 == "config.json" }) { return true }
        }
        return false
    }

    /// Download a model into the cache, streaming progress (main queue);
    /// `completion(success)` on the main queue.
    public static func pull(modelID: String,
                            progress: @escaping (String) -> Void,
                            completion: @escaping (Bool) -> Void) {
        guard let hf = huggingfaceCLI() else {
            DispatchQueue.main.async { progress("huggingface-cli not found (install MLX first)."); completion(false) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = hf
            p.arguments = ["download", modelID]
            p.environment = AgentProcessRunner.inheritedEnvironment()
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty else { return }
                let s = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .newlines)
                if !s.isEmpty { DispatchQueue.main.async { progress(s) } }
            }
            do { try p.run() } catch {
                DispatchQueue.main.async { progress("launch failed: \(error.localizedDescription)"); completion(false) }
                return
            }
            p.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            let ok = p.terminationStatus == 0 && isFullyDownloaded(modelID)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    public static func remove(modelID: String) {
        try? FileManager.default.removeItem(at: cacheHubDir.appendingPathComponent(cacheDirName(for: modelID)))
    }

    private static func huggingfaceCLI() -> URL? {
        let venv = MLXEnvironment.venvDir.appendingPathComponent("bin/huggingface-cli")
        if FileManager.default.isExecutableFile(atPath: venv.path) { return venv }
        return AgentExecutable.locate("huggingface-cli")
    }
}
