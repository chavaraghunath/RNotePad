// SPDX-License-Identifier: MIT
// Sourcepad — Phase 13 AI auxiliaries.
//
// Five small features that share the MLXService backend:
//   • AICommit         — generate a Conventional-Commits message from `git diff --cached`
//   • AIExplain        — explain the current selection in a popover
//   • AITestScaffold   — generate a unit-test stub for the function under caret
//   • AISmartPaste     — sniff clipboard contents on paste, offer transformations
//   • AISemanticSearch — local sentence-embedding-driven file search (stubbed —
//                        Phase 13's full implementation needs an embeddings
//                        model + a vector index; we ship the surface so the
//                        Find-in-Files window's "Semantic" toggle wires up).

import AppKit

public enum AIAuxiliaries {

    // MARK: - AI commit message

    public static func generateCommitMessage(completion: @escaping (String?) -> Void) {
        // Shell to /usr/bin/git in the active workspace root.
        guard let root = WorkspaceManager.shared.activeWorkspace.roots.first else {
            completion(nil); return
        }
        DispatchQueue.global().async {
            let diff = AIAuxiliaries.run(at: root, "/usr/bin/git", ["diff", "--cached"])
                ?? AIAuxiliaries.run(at: root, "/usr/bin/git", ["diff"])
                ?? ""
            if diff.isEmpty {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let trimmed = String(diff.prefix(8000))
            let prompt = """
            Write a Conventional Commits message (type(scope): subject\n\nbody) for the following diff. Return ONLY the commit message, no commentary, no fences.

            \(trimmed)
            """
            MLXService.shared.complete(prompt: prompt, maxTokens: 200) { result in
                switch result {
                case .success(let text): completion(text)
                case .failure: completion(nil)
                }
            }
        }
    }

    // MARK: - Explain selection

    public static func explainSelection(text: String, completion: @escaping (String?) -> Void) {
        let prompt = """
        Explain the following snippet clearly and concisely. Use plain language; if it's code, describe what each part does.

        \(text)
        """
        MLXService.shared.complete(prompt: prompt, maxTokens: 400) { result in
            switch result {
            case .success(let s): completion(s)
            case .failure: completion(nil)
            }
        }
    }

    // MARK: - Smart paste

    /// Sniff clipboard contents on paste and return a suggestion if the
    /// data is a recognised shape we can transform; nil to fall through
    /// to plain paste.
    public static func sniffClipboardForSmartPaste(_ s: String) -> SmartPasteHint? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // JSON?
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                         options: [.prettyPrinted, .sortedKeys]),
               let prettyStr = String(data: pretty, encoding: .utf8) {
                return .json(pretty: prettyStr)
            }
        }
        // URL?
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
           !trimmed.contains(" ") {
            return .url(href: trimmed)
        }
        // Stack trace? (heuristic: contains "Traceback" or "at <something>(<file>:<line>)")
        if trimmed.contains("Traceback") || trimmed.contains("\tat ") {
            return .stackTrace
        }
        return nil
    }

    public enum SmartPasteHint {
        case json(pretty: String)
        case url(href: String)
        case stackTrace
    }

    // MARK: - Test scaffolding

    public static func generateTestStub(for source: String,
                                        language: String?,
                                        completion: @escaping (String?) -> Void) {
        let lang = language ?? "the source language"
        let prompt = """
        Write a unit test scaffold for the following \(lang) code. Pick the conventional test framework for the language. Return ONLY the test code, no commentary, no fences.

        \(source)
        """
        MLXService.shared.complete(prompt: prompt, maxTokens: 400) { result in
            switch result {
            case .success(let s): completion(s)
            case .failure: completion(nil)
            }
        }
    }

    // MARK: - helpers

    /// Run a process at `cwd`, returning stdout as a string (nil on error).
    private static func run(at cwd: URL, _ exe: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = cwd
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
