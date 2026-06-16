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

    // MARK: - Active-download tracking (app-wide)
    //
    // Lets the app warn before quitting while a pull is still running. Guarded
    // by a lock because pulls run on a background queue but `isDownloading` is
    // read from the main thread (e.g. applicationShouldTerminate).

    private static let activeLock = NSLock()
    private static var _active = Set<String>()

    /// True while any model download is in progress.
    public static var isDownloading: Bool {
        activeLock.lock(); defer { activeLock.unlock() }
        return !_active.isEmpty
    }

    /// Model ids currently downloading.
    public static var activeDownloads: [String] {
        activeLock.lock(); defer { activeLock.unlock() }
        return _active.sorted()
    }

    private static func markStart(_ id: String) {
        activeLock.lock(); _active.insert(id); activeLock.unlock()
    }
    private static func markEnd(_ id: String) {
        activeLock.lock(); _active.remove(id); activeLock.unlock()
    }

    /// Download a model into the cache, streaming progress (main queue);
    /// `completion(success)` on the main queue.
    public static func pull(modelID: String,
                            progress: @escaping (String) -> Void,
                            completion: @escaping (Bool) -> Void) {
        guard let hf = downloaderCLI() else {
            DispatchQueue.main.async { progress("Hugging Face CLI not found (install MLX first)."); completion(false) }
            return
        }
        markStart(modelID)
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
                markEnd(modelID)
                DispatchQueue.main.async { progress("launch failed: \(error.localizedDescription)"); completion(false) }
                return
            }
            p.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            markEnd(modelID)
            let ok = p.terminationStatus == 0 && isFullyDownloaded(modelID)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    public static func remove(modelID: String) {
        try? FileManager.default.removeItem(at: cacheHubDir.appendingPathComponent(cacheDirName(for: modelID)))
    }

    /// The Hugging Face download CLI: `hf` (huggingface-hub 1.x) is preferred —
    /// the old `huggingface-cli` is deprecated and no longer functions in 1.x.
    /// Both accept `download <model-id>`. Prefers the managed venv's copy.
    private static func downloaderCLI() -> URL? {
        for name in ["hf", "huggingface-cli"] {
            let venv = MLXEnvironment.venvDir.appendingPathComponent("bin/\(name)")
            if FileManager.default.isExecutableFile(atPath: venv.path) { return venv }
            if let onPath = AgentExecutable.locate(name) { return onPath }
        }
        return nil
    }
}
