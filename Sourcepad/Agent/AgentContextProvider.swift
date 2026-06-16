// SPDX-License-Identifier: MIT
// Sourcepad — turns editor context into agent-prompt context (the "@-mention"
// feature IDE agents like Cursor/Continue expose). It (a) resolves `@path`
// mentions in a user prompt by attaching the referenced file contents, and
// (b) formats a labeled, fenced context block (active file, selection,
// diagnostics, open files) to prepend to an agent turn. AppKit-free so the
// whole module is headless-testable with Foundation only.

import Foundation

public enum AgentContextProvider {

    // MARK: - Types

    /// A file pulled in by an `@path` mention. `content` may carry a truncation
    /// marker if the file exceeded the per-file byte cap.
    public struct Attachment {
        public let path: String
        public let content: String
        public init(path: String, content: String) {
            self.path = path
            self.content = content
        }
    }

    /// Outcome of mention resolution: the prompt with successfully-resolved
    /// `@tokens` removed, plus the attachments they referred to. Tokens that
    /// did not resolve to a real readable file are left untouched in the text.
    public struct MentionResult {
        public let cleanedPrompt: String
        public let attachments: [Attachment]
        public init(cleanedPrompt: String, attachments: [Attachment]) {
            self.cleanedPrompt = cleanedPrompt
            self.attachments = attachments
        }
    }

    /// A point-in-time capture of the editor the user is looking at, fed
    /// alongside a turn so the agent knows the active file, what's highlighted,
    /// any diagnostics, and what else is open. Carries names/selection only —
    /// never whole file bodies (those come from explicit `@`-mentions), keeping
    /// per-turn token cost predictable. Foundation-only; the AppKit panel fills
    /// it in from the live editor.
    public struct EditorContextSnapshot {
        public let activeFilePath: String?
        public let activeFileLanguage: String?
        public let selection: String?
        public let diagnostics: [String]
        public let openFilePaths: [String]

        public init(activeFilePath: String? = nil,
                    activeFileLanguage: String? = nil,
                    selection: String? = nil,
                    diagnostics: [String] = [],
                    openFilePaths: [String] = []) {
            self.activeFilePath = activeFilePath
            self.activeFileLanguage = activeFileLanguage
            self.selection = selection
            self.diagnostics = diagnostics
            self.openFilePaths = openFilePaths
        }

        /// True when the snapshot carries nothing worth prepending to a turn.
        public var isEmpty: Bool {
            let noActive = (activeFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let noSel = (selection?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return noActive && noSel && diagnostics.isEmpty && openFilePaths.isEmpty
        }
    }

    // MARK: - Caps

    /// Upper bound on the formatted context block, so a giant active file or a
    /// flood of diagnostics can never produce a multi-megabyte prepend.
    private static let maxContextBlockBytes = 64 * 1024
    /// Per-section cap for inlined file/selection text inside the context block.
    private static let maxInlineSectionBytes = 24 * 1024

    // MARK: - Mention resolution

    /// Find `@relative/or/abs/path` tokens in `prompt`, resolve them against
    /// `workspaceRoot`, read the files (capped at `maxBytesPerFile`), and return
    /// the cleaned prompt plus attachments. Rules:
    ///   - A token must resolve to a real, readable, regular file; otherwise the
    ///     literal `@token` is left in the text. This means a bare `@`, an
    ///     email-like `a@b`, a directory, or a missing path are never attached.
    ///   - Trailing punctuation (`. , ; : ) ] } ! ?` and quotes) is trimmed off
    ///     the candidate path before resolution.
    ///   - Binary (non-UTF-8) files are skipped and left as text.
    ///   - Over-cap files are attached but truncated with a clear marker.
    ///   - Repeated mentions of the same resolved file de-dupe to one attachment.
    public static func resolveMentions(in prompt: String,
                                       workspaceRoot: String,
                                       maxBytesPerFile: Int) -> MentionResult {
        let cap = max(0, maxBytesPerFile)
        var attachments: [Attachment] = []
        var seenResolved = Set<String>()

        // Scan for `@` that begins a token (start of string or preceded by
        // whitespace). This rejects email-like `user@host` because the `@`
        // there is preceded by a non-whitespace character.
        let chars = Array(prompt)
        var output = ""
        var i = 0

        while i < chars.count {
            let c = chars[i]
            // A mention starts at `@` only when it begins a token: at string
            // start, after whitespace, or after an opening bracket/quote. This
            // rejects email-like `user@host` where `@` follows a word char.
            let openers: Set<Character> = ["(", "[", "{", "'", "\"", "`", "<"]
            let prev = i == 0 ? nil : chars[i - 1]
            let atTokenStart = (c == "@") &&
                (prev == nil || prev!.isWhitespace || openers.contains(prev!))
            guard atTokenStart else {
                output.append(c)
                i += 1
                continue
            }

            // Collect the raw token up to the next whitespace.
            var j = i + 1
            while j < chars.count && !chars[j].isWhitespace {
                j += 1
            }
            let rawToken = String(chars[i + 1..<j]) // text after the '@'
            let candidate = trimTrailingPunctuation(rawToken)

            // Empty candidate (a lone '@') is not a mention.
            if candidate.isEmpty {
                output.append(c)
                i += 1
                continue
            }

            let resolvedPath = resolvePath(candidate, workspaceRoot: workspaceRoot)
            if let resolvedPath, let attachment = readAttachment(at: resolvedPath, cap: cap) {
                if seenResolved.insert(resolvedPath).inserted {
                    attachments.append(attachment)
                }
                // Drop the resolved `@candidate` from the prompt text, but keep
                // any trailing punctuation we trimmed (e.g. `@foo.swift.`).
                let consumedLen = 1 + candidate.count // '@' + candidate
                let trailing = String(chars[(i + consumedLen)..<j])
                output.append(trailing)
                i = j
            } else {
                // Unresolvable — leave the literal `@token` in place.
                output.append("@")
                i += 1
            }
        }

        let cleaned = collapsePromptWhitespace(output)
        return MentionResult(cleanedPrompt: cleaned, attachments: attachments)
    }

    // MARK: - Context block

    /// Build a labeled, fenced context block to prepend to a turn. Any nil/empty
    /// input is omitted; large text is truncated; the whole block is capped.
    public static func formatContext(activeFilePath: String?,
                                     activeFileLanguage: String?,
                                     selection: String?,
                                     diagnostics: [String],
                                     openFilePaths: [String]) -> String {
        var sections: [String] = []

        if let path = nonEmpty(activeFilePath) {
            let name = (path as NSString).lastPathComponent
            var body = "## Active file: \(name)\n"
            if let content = readTextFile(at: path) {
                let fence = fenceLanguage(activeFileLanguage, path: path)
                let (text, truncated) = truncate(content, to: maxInlineSectionBytes)
                body += "```\(fence)\n\(text)\n```"
                if truncated { body += "\n_(truncated)_" }
            } else {
                body += "_(path: \(path))_"
            }
            sections.append(body)
        }

        if let sel = nonEmpty(selection) {
            let (text, truncated) = truncate(sel, to: maxInlineSectionBytes)
            var body = "## Selection:\n```\n\(text)\n```"
            if truncated { body += "\n_(truncated)_" }
            sections.append(body)
        }

        let diags = diagnostics.compactMap { nonEmpty($0) }
        if !diags.isEmpty {
            let lines = diags.map { "- \($0)" }.joined(separator: "\n")
            sections.append("## Diagnostics:\n\(lines)")
        }

        let opens = openFilePaths.compactMap { nonEmpty($0) }
        if !opens.isEmpty {
            let lines = opens
                .map { "- \(($0 as NSString).lastPathComponent)" }
                .joined(separator: "\n")
            sections.append("## Open files:\n\(lines)")
        }

        let block = sections.joined(separator: "\n\n")
        let (capped, _) = truncate(block, to: maxContextBlockBytes)
        return capped
    }

    // MARK: - Compose

    /// Combine attachments + context block + cleaned prompt into the final text
    /// for the agent. Sections present only when non-empty; deterministic order:
    /// attachments, then context, then the prompt.
    public static func compose(prompt: String,
                               contextBlock: String,
                               attachments: [Attachment]) -> String {
        var parts: [String] = []

        if !attachments.isEmpty {
            var attBody = "## Attached files\n"
            attBody += attachments.map { att -> String in
                let name = (att.path as NSString).lastPathComponent
                let fence = fenceLanguage(nil, path: att.path)
                return "### \(name)\n```\(fence)\n\(att.content)\n```"
            }.joined(separator: "\n\n")
            parts.append(attBody)
        }

        if let ctx = nonEmpty(contextBlock) {
            parts.append(ctx)
        }

        if let p = nonEmpty(prompt) {
            parts.append(p)
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Ambient context (lightweight, no bodies)

    /// Build a *lightweight* ambient context block: the active file's **name** +
    /// language, the current selection, diagnostics, and open file **names**.
    /// Unlike `formatContext`, this never inlines whole file bodies — full
    /// contents are pulled in deliberately via `@`-mentions, so each turn's
    /// token cost stays predictable. Any nil/empty input is omitted; the
    /// selection is truncated if huge; the whole block is capped.
    public static func formatAmbientContext(activeFilePath: String?,
                                            activeFileLanguage: String?,
                                            selection: String?,
                                            diagnostics: [String],
                                            openFilePaths: [String]) -> String {
        var sections: [String] = []

        if let path = nonEmpty(activeFilePath) {
            let name = (path as NSString).lastPathComponent
            if let lang = nonEmpty(activeFileLanguage) {
                sections.append("## Active file: \(name) (\(lang.lowercased()))")
            } else {
                sections.append("## Active file: \(name)")
            }
        }

        if let sel = nonEmpty(selection) {
            let (text, truncated) = truncate(sel, to: maxInlineSectionBytes)
            var body = "## Selection:\n```\n\(text)\n```"
            if truncated { body += "\n_(truncated)_" }
            sections.append(body)
        }

        let diags = diagnostics.compactMap { nonEmpty($0) }
        if !diags.isEmpty {
            let lines = diags.map { "- \($0)" }.joined(separator: "\n")
            sections.append("## Diagnostics:\n\(lines)")
        }

        let opens = openFilePaths.compactMap { nonEmpty($0) }
        if !opens.isEmpty {
            let lines = opens
                .map { "- \(($0 as NSString).lastPathComponent)" }
                .joined(separator: "\n")
            sections.append("## Open files:\n\(lines)")
        }

        let block = sections.joined(separator: "\n\n")
        let (capped, _) = truncate(block, to: maxContextBlockBytes)
        return capped
    }

    /// Full agent-prompt pipeline: resolve `@path` mentions in `typed` into
    /// attached file bodies, prepend a lightweight ambient context block built
    /// from `context`, and append the cleaned user text. Returns `typed`
    /// unchanged when composition would be empty. Pure/Foundation-only so the
    /// whole flow is headless-testable.
    public static func composeAgentPrompt(typed: String,
                                          workspaceRoot: String,
                                          context: EditorContextSnapshot?) -> String {
        let mention = resolveMentions(in: typed,
                                      workspaceRoot: workspaceRoot,
                                      maxBytesPerFile: maxContextBlockBytes)
        var contextBlock = ""
        if let ctx = context, !ctx.isEmpty {
            contextBlock = formatAmbientContext(activeFilePath: ctx.activeFilePath,
                                                activeFileLanguage: ctx.activeFileLanguage,
                                                selection: ctx.selection,
                                                diagnostics: ctx.diagnostics,
                                                openFilePaths: ctx.openFilePaths)
        }
        let composed = compose(prompt: mention.cleanedPrompt,
                               contextBlock: contextBlock,
                               attachments: mention.attachments)
        return composed.isEmpty ? typed : composed
    }

    // MARK: - Path helpers

    /// Resolve a mention candidate to an absolute path string if a regular file
    /// exists there. Absolute candidates are used as-is; relative ones join the
    /// workspace root. Returns nil for directories and missing paths.
    private static func resolvePath(_ candidate: String, workspaceRoot: String) -> String? {
        let expanded = (candidate as NSString).expandingTildeInPath
        let absolute: String
        if (expanded as NSString).isAbsolutePath {
            absolute = expanded
        } else {
            absolute = (workspaceRoot as NSString)
                .appendingPathComponent(expanded)
        }
        // Canonicalize (resolve symlinks, `..`, `.`) for a reliable containment
        // check on both sides.
        let standardized = (absolute as NSString).resolvingSymlinksInPath

        // Security boundary: only attach files INSIDE the workspace root. This
        // blocks a prompt from exfiltrating arbitrary local files via an
        // absolute path or `..` escape (e.g. `@~/.ssh/config`, `@/etc/...`).
        let root = (workspaceRoot as NSString).resolvingSymlinksInPath
        guard !root.isEmpty else { return nil }
        let rootBoundary = root.hasSuffix("/") ? root : root + "/"
        guard standardized == root || standardized.hasPrefix(rootBoundary) else {
            NSLog("[Sourcepad] @-mention outside workspace ignored: \(candidate)")
            return nil
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir),
              !isDir.boolValue else {
            return nil
        }
        return standardized
    }

    /// Read a file as an attachment, applying the per-file byte cap. Returns nil
    /// for unreadable or binary (non-UTF-8) content.
    private static func readAttachment(at path: String, cap: Int) -> Attachment? {
        guard let content = readTextFile(at: path) else { return nil }
        let (text, truncated) = truncate(content, to: cap)
        let final = truncated
            ? text + "\n… [truncated: file exceeds \(cap) bytes]"
            : text
        return Attachment(path: path, content: final)
    }

    /// Read a file and decode as UTF-8, returning nil if it is not valid UTF-8
    /// (a cheap binary-file guard) or cannot be read.
    private static func readTextFile(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - String helpers

    private static func nonEmpty(_ value: String?) -> String? {
        guard let v = value else { return nil }
        let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : v
    }

    /// Trim trailing punctuation/quotes commonly attached to a path in prose,
    /// e.g. `see @Foo.swift.` or `(@bar.txt)`. A trailing `.` is only trimmed
    /// when it is clearly sentence punctuation, not part of the filename — we
    /// trim greedily here and rely on path resolution to validate the result.
    private static func trimTrailingPunctuation(_ token: String) -> String {
        let trailing: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "'", "\"", "`", ">"]
        var chars = Array(token)
        while let last = chars.last, trailing.contains(last) {
            chars.removeLast()
        }
        return String(chars)
    }

    /// Collapse runs of spaces/blank lines left behind after removing mentions,
    /// and trim surrounding whitespace, without mangling intentional newlines.
    private static func collapsePromptWhitespace(_ text: String) -> String {
        // Collapse 3+ consecutive spaces/tabs to one space; trim line edges.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let collapsed = line
                .replacingOccurrences(of: "\t", with: " ")
            // Squeeze runs of spaces.
            var out = ""
            var prevSpace = false
            for ch in collapsed {
                if ch == " " {
                    if !prevSpace { out.append(ch) }
                    prevSpace = true
                } else {
                    out.append(ch)
                    prevSpace = false
                }
            }
            return out.trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Truncate a string to at most `maxBytes` UTF-8 bytes on a character
    /// boundary, reporting whether truncation happened.
    private static func truncate(_ text: String, to maxBytes: Int) -> (String, Bool) {
        guard maxBytes >= 0 else { return ("", !text.isEmpty) }
        if text.utf8.count <= maxBytes { return (text, false) }
        var result = ""
        var used = 0
        for ch in text {
            let len = String(ch).utf8.count
            if used + len > maxBytes { break }
            result.append(ch)
            used += len
        }
        return (result, true)
    }

    /// Public, agent-facing language name for a file, derived from its
    /// extension (e.g. `Foo.swift` → "swift"). Prefer this over an editor's
    /// syntax-lexer id, which is a highlighting bucket — many languages share
    /// the C++ lexer, so the lexer would mislabel Swift/C#/Dart as "cpp".
    /// Returns nil when the extension maps to no known language.
    public static func languageHint(forPath path: String) -> String? {
        knownLanguage(forExtension: (path as NSString).pathExtension)
    }

    /// Map a file extension to a known language name, or nil if unrecognised.
    /// The single source of truth for both the agent-facing language hint and
    /// fenced-code language tags.
    private static func knownLanguage(forExtension extension: String) -> String? {
        switch `extension`.lowercased() {
        case "swift":               return "swift"
        case "m", "mm", "h":        return "objc"
        case "c":                   return "c"
        case "cpp", "cc", "cxx":    return "cpp"
        case "py":                  return "python"
        case "js", "mjs", "cjs":    return "javascript"
        case "ts":                  return "typescript"
        case "tsx", "jsx":          return "tsx"
        case "go":                  return "go"
        case "rs":                  return "rust"
        case "rb":                  return "ruby"
        case "java":                return "java"
        case "kt":                  return "kotlin"
        case "json":                return "json"
        case "yaml", "yml":         return "yaml"
        case "toml":                return "toml"
        case "md", "markdown":      return "markdown"
        case "sh", "bash", "zsh":   return "bash"
        case "html":                return "html"
        case "css":                 return "css"
        case "sql":                 return "sql"
        case "xml":                 return "xml"
        default:                    return nil
        }
    }

    /// Best-effort fenced-code language hint from an explicit language or the
    /// file extension. Falls back to the raw extension so code still fences.
    private static func fenceLanguage(_ explicit: String?, path: String) -> String {
        if let lang = nonEmpty(explicit) {
            return lang.lowercased()
        }
        let ext = (path as NSString).pathExtension.lowercased()
        return knownLanguage(forExtension: ext) ?? ext
    }
}
