// SPDX-License-Identifier: MIT
// Sourcepad — contextual policy/governance for agent actions.
//
// Given a tool the agent is about to run (or has run), classify its risk so the
// UI can annotate it and the governance layer can gate the high-risk ones. This
// is deliberately AppKit-free and side-effect-free: a pure classifier that is
// exhaustively headless-testable. It inspects the normalized shell command, the
// target file path, and the tool kind against an ordered ruleset and returns the
// HIGHEST-risk verdict that matches (with the reason of the most specific rule
// at that tier).
//
// Note on the execution model: headless agent CLIs do not expose a reliable
// mid-turn per-action approval hook, so this engine does not pretend to *block*
// individual actions in-flight. Its job is (a) real-time visibility — a risk
// badge on each tool card — and (b) feeding the turn-level governance summary +
// the Touch-ID-gated boundaries the panel *can* control (entering Auto mode,
// keeping a turn's changes).

import Foundation

public enum AgentPolicy {

    // MARK: - Risk

    public enum Risk: Int, Comparable {
        case allow = 0     // routine, no annotation
        case caution = 1   // notable — subtle badge
        case high = 2      // dangerous/irreversible — prominent badge + governance

        public static func < (l: Risk, r: Risk) -> Bool { l.rawValue < r.rawValue }
    }

    public struct Verdict: Equatable {
        public let risk: Risk
        public let reason: String?
        public let ruleID: String?
        public init(risk: Risk, reason: String? = nil, ruleID: String? = nil) {
            self.risk = risk
            self.reason = reason
            self.ruleID = ruleID
        }
        public static let allow = Verdict(risk: .allow)
    }

    // MARK: - Entry point

    public static func evaluate(_ call: AgentToolCall, workspaceRoot: String?) -> Verdict {
        switch call.kind {
        case .shell:
            return evaluateShell(call.detail ?? stripPrompt(call.title))
        case .fileCreate, .fileEdit:
            return evaluateWrite(path: call.path, title: call.title, workspaceRoot: workspaceRoot)
        case .fileRead:
            return evaluateRead(path: call.path, title: call.title)
        case .web:
            return Verdict(risk: .caution, reason: "Network access", ruleID: "net.web")
        case .search, .other:
            return .allow
        }
    }

    // MARK: - Shell

    private struct Rule {
        let risk: Risk
        let reason: String
        let id: String
        let regex: NSRegularExpression
        init(_ risk: Risk, _ reason: String, _ id: String, _ pattern: String) {
            self.risk = risk
            self.reason = reason
            self.id = id
            // Patterns are authored carefully; a bad pattern is a programming
            // error we want to surface loudly in tests, not silently ignore.
            self.regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }

    // Ordered high→caution so that, among rules matching at the top tier, the
    // first (most specific) wins the reason. Patterns operate on the raw command.
    private static let shellRules: [Rule] = [
        // — Irreversible / destructive filesystem —
        Rule(.high, "Recursive/forced file deletion", "sh.rm",
             #"(^|[|;&]|\s)rm\s+(-\S*\s+)*(-\S*[rf]|--(recursive|force))"#),
        Rule(.high, "Fork bomb", "sh.forkbomb", #":\(\)\s*\{"#),
        Rule(.high, "Low-level disk write", "sh.disk",
             #"(^|[|;&]|\s)(dd|mkfs\S*|fdisk|shred|diskutil)\b|>\s*/dev/(sd|disk|rdisk)"#),
        // — Remote code execution / exfiltration —
        Rule(.high, "Pipes downloaded content into a shell", "sh.pipe2shell",
             #"\|\s*(sudo\s+)?(sh|bash|zsh|python\S*|perl|ruby)\b"#),
        Rule(.high, "Raw network shell (reverse shell risk)", "sh.netcat",
             #"(^|[|;&]|\s)(nc|ncat|netcat|telnet)\b|/dev/tcp/"#),
        // — Credentials / secrets —
        Rule(.high, "Accesses credentials or secrets", "sh.secret", secretPattern),
        // — Privilege escalation —
        Rule(.high, "Runs with elevated privileges", "sh.sudo",
             #"(^|[|;&]|\s)(sudo|doas)\s|(^|\s)su\s+-"#),
        // — Security posture —
        Rule(.high, "Disables system security", "sh.security",
             #"\b(csrutil|spctl)\s+(disable|--master-disable)|\bnvram\b"#),
        // — Version control: lossy / irreversible —
        Rule(.high, "Force-overwrites remote history", "sh.gitforce",
             #"\bgit\s+push\s+[^|;&]*(--force\b|-f\b)|--force-with-lease"#),
        Rule(.high, "Discards local work irreversibly", "sh.gitreset",
             #"\bgit\s+(reset\s+--hard|clean\s+-\S*f|checkout\s+--?\s|branch\s+-D)"#),
        // — Publishing / deploy (public, hard to undo) —
        Rule(.high, "Publishes or deploys to a remote", "sh.publish",
             #"\b((npm|yarn|pnpm)\s+publish|gem\s+push|cargo\s+publish|twine\s+upload|docker\s+push|gh\s+release\s+create|terraform\s+(apply|destroy)|kubectl\s+(delete|apply))\b"#),
        Rule(.high, "World-writable permissions", "sh.chmod777",
             #"\bchmod\s+(-\S+\s+)*0?777\b"#),

        // — Caution tier —
        Rule(.caution, "Installs packages (may run install scripts)", "sh.install",
             #"\b((npm|yarn|pnpm)\s+(install|i|add)|pip\d?\s+install|brew\s+install|gem\s+install|cargo\s+(install|add)|go\s+(get|install)|apt(-get)?\s+install)\b"#),
        Rule(.caution, "Network access", "sh.net",
             #"(^|[|;&]|\s)(curl|wget|scp|ssh|sftp|rsync|ftp)\b"#),
        Rule(.caution, "Mutates version-control state", "sh.gitwrite",
             #"\bgit\s+(commit|push|merge|rebase|cherry-pick|tag|stash\s+drop)\b"#),
        Rule(.caution, "Changes file ownership/permissions", "sh.perm",
             #"\b(chmod|chown|chgrp)\b"#),
        Rule(.caution, "Terminates processes", "sh.kill",
             #"\b(kill|killall|pkill)\b"#),
        Rule(.caution, "Modifies system configuration", "sh.syscfg",
             #"\b(launchctl|defaults\s+write|systemsetup|scutil)\b"#),
        Rule(.caution, "Deletes files", "sh.del", #"(^|[|;&]|\s)rm\b"#),
    ]

    private static func evaluateShell(_ command: String) -> Verdict {
        let range = NSRange(command.startIndex..., in: command)
        var best = Verdict.allow
        for rule in shellRules {
            guard rule.regex.firstMatch(in: command, options: [], range: range) != nil else { continue }
            if rule.risk > best.risk {
                best = Verdict(risk: rule.risk, reason: rule.reason, ruleID: rule.id)
                if best.risk == .high { /* keep scanning won't raise higher, but a later high rule could be more specific — first wins, so stop at first high */ break }
            }
        }
        return best
    }

    // MARK: - File writes / reads

    private static func evaluateWrite(path: String?, title: String, workspaceRoot: String?) -> Verdict {
        let hay = ((path ?? "") + " " + title)
        if matchesSecretPath(hay) {
            return Verdict(risk: .high, reason: "Writes to a credential/secret file", ruleID: "file.secret")
        }
        if let path = path, let root = workspaceRoot, !root.isEmpty,
           isAbsolute(path), isOutside(path: path, root: root) {
            return Verdict(risk: .high, reason: "Writes outside the workspace", ruleID: "file.outside")
        }
        if hay.contains("/.git/") {
            return Verdict(risk: .caution, reason: "Modifies git internals", ruleID: "file.git")
        }
        return .allow
    }

    private static func evaluateRead(path: String?, title: String) -> Verdict {
        let hay = ((path ?? "") + " " + title)
        if matchesSecretPath(hay) {
            return Verdict(risk: .caution, reason: "Reads a credential/secret file", ruleID: "file.readsecret")
        }
        return .allow
    }

    // MARK: - Helpers

    /// Secret/credential indicators, shared by the shell and file rules.
    private static let secretTokens = [
        ".ssh/", "id_rsa", "id_ed25519", "id_dsa", ".aws/credentials", ".netrc",
        ".pem", ".env", ".npmrc", ".pgpass", ".kube/config", "secring", "credentials.json",
    ]
    private static let secretPattern: String = {
        // Word-ish boundaries around each token; used in shell command matching.
        let alts = secretTokens.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return "(\(alts))"
    }()

    private static func matchesSecretPath(_ hay: String) -> Bool {
        let lower = hay.lowercased()
        return secretTokens.contains { lower.contains($0) }
    }

    private static func isAbsolute(_ path: String) -> Bool {
        path.hasPrefix("/") || path.hasPrefix("~")
    }

    /// True when `path` resolves outside `root` (both standardized). Relative
    /// paths are treated as inside (they resolve against the workspace cwd).
    private static func isOutside(path: String, root: String) -> Bool {
        let p = (path as NSString).expandingTildeInPath
        let stdPath = (p as NSString).standardizingPath
        let stdRoot = ((root as NSString).expandingTildeInPath as NSString).standardizingPath
        guard stdPath.hasPrefix("/") else { return false }
        if stdPath == stdRoot { return false }
        return !stdPath.hasPrefix(stdRoot + "/")
    }

    /// Strip a leading shell prompt marker ("$ ") that the card title carries.
    private static func stripPrompt(_ title: String) -> String {
        if title.hasPrefix("$ ") { return String(title.dropFirst(2)) }
        return title
    }
}
