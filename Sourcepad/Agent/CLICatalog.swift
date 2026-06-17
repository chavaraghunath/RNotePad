// SPDX-License-Identifier: MIT
// Sourcepad — catalog of known agent CLIs and how to install / sign in / manage them.
//
// This is pure data (no AppKit, no side effects) describing each mainstream
// agentic coding CLI: how to install it (one or more package-manager methods,
// tried in priority order), how the user signs in, where its config lives, and
// the docs URL. The "Agent CLIs" settings pane turns these into one-click
// install / update / uninstall / sign-in actions, and `CLIInstaller` runs the
// chosen command headlessly with streamed progress.
//
// Install commands are authored against each tool's official guidance (probed
// 2026-06; see AGENT-CLI-KNOWLEDGE-BASE.md). They run via the user's login shell
// so pipes (`curl … | bash`) and PATH resolve exactly as in a real terminal.

import Foundation

/// One way to install / update / uninstall a CLI via a specific package manager.
/// `requiresCommand` (when set) must be on PATH for the method to be offered, so
/// we never propose `brew …` on a machine without Homebrew.
public struct CLIInstallMethod: Equatable {
    public let id: String              // "brew" | "npm" | "pipx" | "script" | "cargo"
    public let label: String           // "Homebrew", "npm (global)", "Official installer", …
    public let requiresCommand: String? // "brew" | "npm" | "pipx" | nil (always available, e.g. curl script)
    public let shellCommand: String    // full command, run via `<login-shell> -lc "…"`

    public init(id: String, label: String, requiresCommand: String?, shellCommand: String) {
        self.id = id; self.label = label
        self.requiresCommand = requiresCommand; self.shellCommand = shellCommand
    }
}

/// How a CLI is authenticated. Sourcepad never stores provider credentials — it
/// triggers the CLI's own login (which writes the CLI's own config) and detects
/// the resulting auth state.
public struct CLIAuthSpec: Equatable {
    public enum Kind: String { case browserOAuth, envKey, manual }
    public let kind: Kind
    public let command: String?   // login command (browserOAuth / manual)
    public let envVar: String?    // environment variable carrying the key (envKey)
    public let note: String?      // short guidance shown in the UI

    public init(kind: Kind, command: String? = nil, envVar: String? = nil, note: String? = nil) {
        self.kind = kind; self.command = command; self.envVar = envVar; self.note = note
    }
}

/// A known agent CLI and everything needed to install / manage / sign in to it.
public struct CLICatalogEntry: Equatable {
    public let id: String                 // matches AgentCLI.id / CLISpec.id ("claude", "codex", …)
    public let name: String               // display name
    public let blurb: String              // one-line description
    public let command: String            // executable name to locate on PATH
    public let docsURL: String
    public let configDir: String?         // ~-relative config dir, for "Open config folder" (nil if none)
    public let auth: CLIAuthSpec
    public let installMethods: [CLIInstallMethod]
    public let updateMethods: [CLIInstallMethod]
    public let uninstallMethods: [CLIInstallMethod]
    public let enabled: Bool              // false → shown but actions disabled (e.g. broken upstream)
    public let disabledNote: String?

    public init(id: String, name: String, blurb: String, command: String, docsURL: String,
                configDir: String?, auth: CLIAuthSpec,
                installMethods: [CLIInstallMethod],
                updateMethods: [CLIInstallMethod] = [],
                uninstallMethods: [CLIInstallMethod] = [],
                enabled: Bool = true, disabledNote: String? = nil) {
        self.id = id; self.name = name; self.blurb = blurb; self.command = command
        self.docsURL = docsURL; self.configDir = configDir; self.auth = auth
        self.installMethods = installMethods
        self.updateMethods = updateMethods
        self.uninstallMethods = uninstallMethods
        self.enabled = enabled; self.disabledNote = disabledNote
    }

    /// The first install method whose required package manager is present, or
    /// nil when none of its prerequisites are installed.
    public func preferredInstall(available: (String) -> Bool) -> CLIInstallMethod? {
        firstAvailable(installMethods, available)
    }
    public func preferredUpdate(available: (String) -> Bool) -> CLIInstallMethod? {
        firstAvailable(updateMethods, available)
    }
    public func preferredUninstall(available: (String) -> Bool) -> CLIInstallMethod? {
        firstAvailable(uninstallMethods, available)
    }
    private func firstAvailable(_ methods: [CLIInstallMethod], _ available: (String) -> Bool) -> CLIInstallMethod? {
        methods.first { $0.requiresCommand == nil || available($0.requiresCommand!) }
    }
}

// MARK: - The catalog

public enum CLICatalog {

    /// All known CLIs in display order. The first four are the Tier-1 set we
    /// drive + test directly; the rest are supported via the spec/probe path.
    public static let entries: [CLICatalogEntry] = [
        claude, codex, opencode, gemini,
        aider, amp, qwen, goose, crush, amazonQ,
        cursorAgent,
    ]

    public static func entry(id: String) -> CLICatalogEntry? {
        entries.first { $0.id == id }
    }

    // Reusable install-method builders.
    private static func brew(_ formula: String, cask: Bool = false, label: String = "Homebrew") -> CLIInstallMethod {
        CLIInstallMethod(id: "brew", label: label, requiresCommand: "brew",
                         shellCommand: "brew install \(cask ? "--cask " : "")\(formula)")
    }
    private static func npm(_ pkg: String) -> CLIInstallMethod {
        CLIInstallMethod(id: "npm", label: "npm (global)", requiresCommand: "npm",
                         shellCommand: "npm install -g \(pkg)")
    }
    private static func pipx(_ pkg: String) -> CLIInstallMethod {
        CLIInstallMethod(id: "pipx", label: "pipx", requiresCommand: "pipx",
                         shellCommand: "pipx install \(pkg)")
    }
    private static func script(_ url: String, label: String = "Official installer") -> CLIInstallMethod {
        CLIInstallMethod(id: "script", label: label, requiresCommand: nil,
                         shellCommand: "curl -fsSL \(url) | bash")
    }
    private static func brewUpgrade(_ formula: String, cask: Bool = false) -> CLIInstallMethod {
        CLIInstallMethod(id: "brew", label: "Homebrew", requiresCommand: "brew",
                         shellCommand: "brew upgrade \(cask ? "--cask " : "")\(formula)")
    }
    private static func npmUpgrade(_ pkg: String) -> CLIInstallMethod {
        CLIInstallMethod(id: "npm", label: "npm (global)", requiresCommand: "npm",
                         shellCommand: "npm install -g \(pkg)@latest")
    }
    private static func pipxUpgrade(_ pkg: String) -> CLIInstallMethod {
        CLIInstallMethod(id: "pipx", label: "pipx", requiresCommand: "pipx",
                         shellCommand: "pipx upgrade \(pkg)")
    }
    private static func brewRemove(_ formula: String, cask: Bool = false) -> CLIInstallMethod {
        CLIInstallMethod(id: "brew", label: "Homebrew", requiresCommand: "brew",
                         shellCommand: "brew uninstall \(cask ? "--cask " : "")\(formula)")
    }
    private static func npmRemove(_ pkg: String) -> CLIInstallMethod {
        CLIInstallMethod(id: "npm", label: "npm (global)", requiresCommand: "npm",
                         shellCommand: "npm uninstall -g \(pkg)")
    }
    private static func pipxRemove(_ pkg: String) -> CLIInstallMethod {
        CLIInstallMethod(id: "pipx", label: "pipx", requiresCommand: "pipx",
                         shellCommand: "pipx uninstall \(pkg)")
    }

    // MARK: - Tier 1

    static let claude = CLICatalogEntry(
        id: "claude", name: "Claude Code", blurb: "Anthropic's agentic coding CLI.",
        command: "claude", docsURL: "https://docs.claude.com/en/docs/claude-code",
        configDir: "~/.claude",
        auth: CLIAuthSpec(kind: .manual, command: "claude",
                          envVar: "ANTHROPIC_API_KEY",
                          note: "Run `claude`, then `/login` to sign in — or set ANTHROPIC_API_KEY."),
        installMethods: [script("https://claude.ai/install.sh"), brew("--cask claude-code", cask: true), npm("@anthropic-ai/claude-code")],
        updateMethods: [npmUpgrade("@anthropic-ai/claude-code"), brewUpgrade("claude-code", cask: true)],
        uninstallMethods: [npmRemove("@anthropic-ai/claude-code"), brewRemove("claude-code", cask: true)])

    static let codex = CLICatalogEntry(
        id: "codex", name: "Codex", blurb: "OpenAI's coding agent CLI.",
        command: "codex", docsURL: "https://developers.openai.com/codex/cli",
        configDir: "~/.codex",
        auth: CLIAuthSpec(kind: .browserOAuth, command: "codex login",
                          envVar: "OPENAI_API_KEY",
                          note: "Sign in with ChatGPT, or set OPENAI_API_KEY."),
        installMethods: [brew("codex"), npm("@openai/codex")],
        updateMethods: [brewUpgrade("codex"), npmUpgrade("@openai/codex")],
        uninstallMethods: [brewRemove("codex"), npmRemove("@openai/codex")])

    static let opencode = CLICatalogEntry(
        id: "opencode", name: "opencode", blurb: "Open-source, provider-agnostic coding agent.",
        command: "opencode", docsURL: "https://opencode.ai/docs",
        configDir: "~/.config/opencode",
        auth: CLIAuthSpec(kind: .manual, command: "opencode auth login",
                          note: "Run `opencode auth login` to pick a provider and sign in."),
        installMethods: [script("https://opencode.ai/install"), brew("sst/tap/opencode"), npm("opencode-ai")],
        updateMethods: [npmUpgrade("opencode-ai"), brewUpgrade("sst/tap/opencode")],
        uninstallMethods: [npmRemove("opencode-ai"), brewRemove("sst/tap/opencode")])

    static let gemini = CLICatalogEntry(
        id: "gemini", name: "Gemini", blurb: "Google's Gemini coding CLI.",
        command: "gemini", docsURL: "https://github.com/google-gemini/gemini-cli",
        configDir: "~/.gemini",
        auth: CLIAuthSpec(kind: .envKey, command: "gemini", envVar: "GEMINI_API_KEY",
                          note: "Set GEMINI_API_KEY, or run `gemini` once to sign in with Google."),
        installMethods: [npm("@google/gemini-cli"), brew("gemini-cli")],
        updateMethods: [npmUpgrade("@google/gemini-cli"), brewUpgrade("gemini-cli")],
        uninstallMethods: [npmRemove("@google/gemini-cli"), brewRemove("gemini-cli")])

    // MARK: - Popular

    static let aider = CLICatalogEntry(
        id: "aider", name: "Aider", blurb: "Pair-programming agent with a strong git workflow.",
        command: "aider", docsURL: "https://aider.chat/docs",
        configDir: nil,
        auth: CLIAuthSpec(kind: .envKey, envVar: "OPENAI_API_KEY",
                          note: "Set OPENAI_API_KEY / ANTHROPIC_API_KEY (or another provider key)."),
        installMethods: [pipx("aider-chat"), brew("aider")],
        updateMethods: [pipxUpgrade("aider-chat"), brewUpgrade("aider")],
        uninstallMethods: [pipxRemove("aider-chat"), brewRemove("aider")])

    static let amp = CLICatalogEntry(
        id: "amp", name: "Amp", blurb: "Sourcegraph's agentic coding CLI.",
        command: "amp", docsURL: "https://ampcode.com/manual",
        configDir: nil,
        auth: CLIAuthSpec(kind: .manual, command: "amp login",
                          note: "Run `amp login` to authenticate."),
        installMethods: [npm("@sourcegraph/amp")],
        updateMethods: [npmUpgrade("@sourcegraph/amp")],
        uninstallMethods: [npmRemove("@sourcegraph/amp")])

    static let qwen = CLICatalogEntry(
        id: "qwen", name: "Qwen Code", blurb: "Alibaba's Qwen-based coding CLI.",
        command: "qwen", docsURL: "https://github.com/QwenLM/qwen-code",
        configDir: "~/.qwen",
        auth: CLIAuthSpec(kind: .envKey, command: "qwen", envVar: "OPENAI_API_KEY",
                          note: "Run `qwen` to sign in, or set an OpenAI-compatible API key."),
        installMethods: [npm("@qwen-code/qwen-code")],
        updateMethods: [npmUpgrade("@qwen-code/qwen-code")],
        uninstallMethods: [npmRemove("@qwen-code/qwen-code")])

    static let goose = CLICatalogEntry(
        id: "goose", name: "Goose", blurb: "Block's extensible, recipe-driven coding agent.",
        command: "goose", docsURL: "https://block.github.io/goose",
        configDir: "~/.config/goose",
        auth: CLIAuthSpec(kind: .manual, command: "goose configure",
                          note: "Run `goose configure` to choose a provider and add keys."),
        installMethods: [brew("block-goose-cli"),
                         script("https://github.com/block/goose/releases/download/stable/download_cli.sh")],
        updateMethods: [brewUpgrade("block-goose-cli")],
        uninstallMethods: [brewRemove("block-goose-cli")])

    static let crush = CLICatalogEntry(
        id: "crush", name: "Crush", blurb: "Charm's glamorous terminal coding agent.",
        command: "crush", docsURL: "https://github.com/charmbracelet/crush",
        configDir: "~/.config/crush",
        auth: CLIAuthSpec(kind: .envKey, envVar: "ANTHROPIC_API_KEY",
                          note: "Set a provider API key (ANTHROPIC_API_KEY, OPENAI_API_KEY, …)."),
        installMethods: [brew("charmbracelet/tap/crush"), npm("@charmland/crush")],
        updateMethods: [brewUpgrade("charmbracelet/tap/crush"), npmUpgrade("@charmland/crush")],
        uninstallMethods: [brewRemove("charmbracelet/tap/crush"), npmRemove("@charmland/crush")])

    static let amazonQ = CLICatalogEntry(
        id: "q", name: "Amazon Q", blurb: "Amazon Q Developer agent CLI.",
        command: "q", docsURL: "https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line.html",
        configDir: nil,
        auth: CLIAuthSpec(kind: .manual, command: "q login",
                          note: "Run `q login` to authenticate with Builder ID or IAM Identity Center."),
        installMethods: [brew("amazon-q", cask: true)],
        updateMethods: [brewUpgrade("amazon-q", cask: true)],
        uninstallMethods: [brewRemove("amazon-q", cask: true)])

    // MARK: - Deferred (shown disabled)

    static let cursorAgent = CLICatalogEntry(
        id: "cursor-agent", name: "Cursor Agent", blurb: "Cursor's terminal coding agent.",
        command: "cursor-agent", docsURL: "https://docs.cursor.com/en/cli/overview",
        configDir: nil,
        auth: CLIAuthSpec(kind: .manual, command: "cursor-agent login",
                          note: "Run `cursor-agent login` to authenticate."),
        installMethods: [script("https://cursor.com/install", label: "Official installer")],
        updateMethods: [CLIInstallMethod(id: "self", label: "Built-in updater", requiresCommand: "cursor-agent",
                                         shellCommand: "cursor-agent update")],
        uninstallMethods: [],
        enabled: false,
        disabledNote: "Currently emits invalid output to its CLI interface in our testing; integration deferred until upstream is stable.")
}
