// SPDX-License-Identifier: MIT
// Sourcepad — best-effort detection of whether an agent CLI is signed in.
//
// We never store provider credentials; each CLI owns its own auth. To show the
// right action ("Sign in" vs "Signed in ✓"), we look for the CLI's own auth
// artifact on disk (the file its login writes) or a recognised API-key env var.
// Detection is deliberately conservative: `.ready` only when we positively find
// credentials, otherwise `.unknown` — we never assert "signed out", since a CLI
// may authenticate in a way we can't observe.
//
// Foundation-only; reads small files / env vars, safe to call off the main queue.

import Foundation

public enum CLIAuthStatus {

    public enum Status { case ready, unknown }

    private static var home: String { NSHomeDirectory() }
    private static func exists(_ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: (home as NSString).appendingPathComponent(rel))
    }
    private static func env(_ name: String) -> Bool {
        if let v = ProcessInfo.processInfo.environment[name], !v.isEmpty { return true }
        return false
    }

    /// Best-effort auth state for a catalog CLI id.
    public static func status(for id: String) -> Status {
        switch id {
        case "claude":
            return (exists(".claude/.credentials.json") || exists(".claude.json")
                    || env("ANTHROPIC_API_KEY")) ? .ready : .unknown
        case "codex":
            return (exists(".codex/auth.json") || env("OPENAI_API_KEY")) ? .ready : .unknown
        case "opencode":
            return (exists(".local/share/opencode/auth.json")
                    || exists(".config/opencode/auth.json")) ? .ready : .unknown
        case "gemini":
            return (exists(".gemini/oauth_creds.json")
                    || env("GEMINI_API_KEY") || env("GOOGLE_API_KEY")) ? .ready : .unknown
        case "qwen":
            return (exists(".qwen/oauth_creds.json") || env("OPENAI_API_KEY")
                    || env("DASHSCOPE_API_KEY")) ? .ready : .unknown
        case "aider":
            return (env("OPENAI_API_KEY") || env("ANTHROPIC_API_KEY")
                    || env("GEMINI_API_KEY") || exists(".aider.conf.yml")) ? .ready : .unknown
        case "crush":
            return (env("ANTHROPIC_API_KEY") || env("OPENAI_API_KEY")
                    || env("GEMINI_API_KEY") || exists(".config/crush/crush.json")) ? .ready : .unknown
        case "goose":
            return exists(".config/goose/config.yaml") ? .ready : .unknown
        case "amp":
            return exists(".config/amp/settings.json") ? .ready : .unknown
        default:
            return .unknown   // q, cursor-agent, user-added CLIs — can't observe reliably
        }
    }
}
