// SPDX-License-Identifier: MIT
// Sourcepad — LSP message shapes we care about.
//
// Pragmatic balance: we use [String: Any] for raw payloads (LSP messages
// are heterogeneous + the protocol is large), with small Swift helpers
// that read the common shapes (Position, Range, Diagnostic, etc.) on top.
// Adding new shapes is "add a small reader struct here" — no boilerplate
// for shapes we don't yet consume.

import Foundation

public enum LSP {

    // MARK: - Position / Range

    /// Zero-based (line, character). Characters are UTF-16 code units per
    /// the LSP spec (this is the default position-encoding even in 3.17;
    /// many servers also support 'utf-8' or 'utf-32' but we keep it simple
    /// by speaking UTF-16 and converting at the bridge if needed).
    public struct Position: Hashable {
        public let line: Int
        public let character: Int

        public init(line: Int, character: Int) {
            self.line = line
            self.character = character
        }

        public init?(_ raw: Any?) {
            guard let d = raw as? [String: Any],
                  let l = d["line"] as? Int,
                  let c = d["character"] as? Int else { return nil }
            self.line = l
            self.character = c
        }

        public var dict: [String: Any] {
            ["line": line, "character": character]
        }
    }

    public struct Range_: Hashable {
        public let start: Position
        public let end: Position

        public init(start: Position, end: Position) {
            self.start = start
            self.end = end
        }

        public init?(_ raw: Any?) {
            guard let d = raw as? [String: Any],
                  let s = Position(d["start"]),
                  let e = Position(d["end"]) else { return nil }
            self.start = s
            self.end = e
        }

        public var dict: [String: Any] {
            ["start": start.dict, "end": end.dict]
        }
    }

    public struct Location {
        public let uri: String
        public let range: Range_

        public init?(_ raw: Any?) {
            guard let d = raw as? [String: Any],
                  let u = d["uri"] as? String,
                  let r = Range_(d["range"]) else { return nil }
            self.uri = u
            self.range = r
        }
    }

    // MARK: - Diagnostic

    public enum DiagnosticSeverity: Int {
        case error = 1, warning = 2, information = 3, hint = 4
    }

    public struct Diagnostic {
        public let range: Range_
        public let severity: DiagnosticSeverity
        public let message: String
        public let source: String?
        public let code: String?

        public init?(_ raw: Any?) {
            guard let d = raw as? [String: Any],
                  let r = Range_(d["range"]),
                  let m = d["message"] as? String else { return nil }
            self.range = r
            self.severity = (d["severity"] as? Int).flatMap(DiagnosticSeverity.init) ?? .information
            self.message = m
            self.source = d["source"] as? String
            if let c = d["code"] as? String { self.code = c }
            else if let c = d["code"] as? Int { self.code = String(c) }
            else { self.code = nil }
        }
    }

    public struct PublishDiagnosticsParams {
        public let uri: String
        public let diagnostics: [Diagnostic]

        public init?(_ raw: Any?) {
            guard let d = raw as? [String: Any],
                  let u = d["uri"] as? String,
                  let arr = d["diagnostics"] as? [[String: Any]] else { return nil }
            self.uri = u
            self.diagnostics = arr.compactMap(Diagnostic.init)
        }
    }

    // MARK: - Hover

    public struct Hover {
        /// Hover content as markdown text. LSP `contents` can be a string,
        /// `{language, value}`, an array, or `MarkupContent`. We collapse
        /// everything to a markdown string the popover renderer consumes.
        public let markdown: String
        public let range: Range_?

        public init?(_ raw: Any?) {
            guard let d = raw as? [String: Any] else { return nil }
            self.range = Range_(d["range"])
            self.markdown = Hover.flatten(d["contents"]) ?? ""
            if self.markdown.isEmpty { return nil }
        }

        private static func flatten(_ contents: Any?) -> String? {
            if let s = contents as? String { return s }
            if let m = contents as? [String: Any] {
                if let value = m["value"] as? String { return value }
            }
            if let arr = contents as? [Any] {
                let parts = arr.compactMap(flatten)
                return parts.joined(separator: "\n\n")
            }
            return nil
        }
    }

    // MARK: - Completion

    public struct CompletionItem {
        public let label: String
        public let detail: String?
        public let kind: Int?    // LSP CompletionItemKind enum (numeric)
        public let insertText: String?

        public init?(_ raw: Any?) {
            guard let d = raw as? [String: Any],
                  let l = d["label"] as? String else { return nil }
            self.label = l
            self.detail = d["detail"] as? String
            self.kind = d["kind"] as? Int
            self.insertText = d["insertText"] as? String
        }
    }

    public struct CompletionList {
        public let isIncomplete: Bool
        public let items: [CompletionItem]

        public init?(_ raw: Any?) {
            if let arr = raw as? [[String: Any]] {
                self.isIncomplete = false
                self.items = arr.compactMap(CompletionItem.init)
                return
            }
            guard let d = raw as? [String: Any],
                  let arr = d["items"] as? [[String: Any]] else { return nil }
            self.isIncomplete = d["isIncomplete"] as? Bool ?? false
            self.items = arr.compactMap(CompletionItem.init)
        }
    }

    // MARK: - URI helpers

    /// file:// URI for an on-disk path. LSP uses these as document
    /// identifiers throughout.
    public static func uri(forPath path: String) -> String {
        return URL(fileURLWithPath: path).absoluteString
    }

    public static func path(forURI uri: String) -> String? {
        return URL(string: uri)?.path
    }
}
