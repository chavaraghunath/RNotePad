// SPDX-License-Identifier: MIT
// Sourcepad — manages the Python environment that runs MLX models.
//
// Policy (user choice): prefer an existing `mlx_lm` on PATH; otherwise create +
// own a dedicated venv under Application Support and `pip install mlx-lm` into
// it. Apple-Silicon only (MLX requires it).

import Foundation

public enum MLXEnvironment {

    /// True on Apple Silicon (MLX won't run otherwise).
    public static var isAppleSilicon: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return machine.hasPrefix("arm64")
    }

    /// The managed venv directory (created on demand).
    public static var venvDir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Sourcepad/mlx-venv", isDirectory: true)
    }

    /// `mlx_lm.generate` to use: an existing one on PATH first, else the managed
    /// venv's. Nil if neither is present.
    public static func generateBinary() -> URL? {
        if let onPath = AgentExecutable.locate("mlx_lm.generate") { return onPath }
        let venv = venvDir.appendingPathComponent("bin/mlx_lm.generate")
        return FileManager.default.isExecutableFile(atPath: venv.path) ? venv : nil
    }

    /// `mlx_lm.server` to use (existing on PATH first, else the managed venv's).
    public static func serverBinary() -> URL? {
        if let onPath = AgentExecutable.locate("mlx_lm.server") { return onPath }
        let venv = venvDir.appendingPathComponent("bin/mlx_lm.server")
        return FileManager.default.isExecutableFile(atPath: venv.path) ? venv : nil
    }

    /// The python used for management tasks (downloads). Prefers the venv's.
    public static func pythonBinary() -> URL? {
        let venvPy = venvDir.appendingPathComponent("bin/python")
        if FileManager.default.isExecutableFile(atPath: venvPy.path) { return venvPy }
        return AgentExecutable.locate("python3")
    }

    public static var isInstalled: Bool { generateBinary() != nil }

    /// Create the managed venv and install mlx-lm into it. Streams pip output via
    /// `progress` (main queue); `completion(success)` on the main queue.
    public static func install(progress: @escaping (String) -> Void,
                               completion: @escaping (Bool) -> Void) {
        guard isAppleSilicon else {
            DispatchQueue.main.async { progress("MLX requires Apple Silicon."); completion(false) }
            return
        }
        guard let basePython = AgentExecutable.locate("python3") else {
            DispatchQueue.main.async { progress("python3 not found on PATH."); completion(false) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let dir = venvDir
            try? FileManager.default.createDirectory(at: dir.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            // 1. Create the venv.
            if run(basePython.path, ["-m", "venv", dir.path], progress: progress) != 0 {
                finish(progress, completion, "Failed to create the Python virtual environment.", false); return
            }
            let pip = dir.appendingPathComponent("bin/pip").path
            // 2. Upgrade pip, then install mlx-lm.
            _ = run(pip, ["install", "--upgrade", "pip"], progress: progress)
            progress("Installing mlx-lm (this can take a minute)…")
            let code = run(pip, ["install", "mlx-lm"], progress: progress)
            let ok = code == 0 && generateBinary() != nil
            finish(progress, completion, ok ? "MLX is ready." : "mlx-lm install failed.", ok)
        }
    }

    // MARK: - Helpers

    private static func finish(_ progress: @escaping (String) -> Void,
                               _ completion: @escaping (Bool) -> Void,
                               _ message: String, _ ok: Bool) {
        DispatchQueue.main.async { progress(message); completion(ok) }
    }

    /// Run a command to completion, streaming combined output lines via `progress`.
    @discardableResult
    private static func run(_ exe: String, _ args: [String],
                            progress: @escaping (String) -> Void) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = AgentProcessRunner.inheritedEnvironment()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            let s = String(decoding: d, as: UTF8.self)
            DispatchQueue.main.async { progress(s.trimmingCharacters(in: .newlines)) }
        }
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        return p.terminationStatus
    }
}
