// SPDX-License-Identifier: MIT
// Sourcepad — small JSON helpers shared by the agent adapters: extracting text
// from heterogeneous content fields and mapping CLI-specific tool names to the
// shared AgentToolCall vocabulary.

import Foundation

enum AgentJSON {

    /// Content fields arrive as a String, or an array of blocks like
    /// `[{type:text, text:"…"}]`, or nil. Flatten to a plain string.
    static func text(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let arr = value as? [[String: Any]] {
            let parts = arr.compactMap { $0["text"] as? String }
            return parts.isEmpty ? nil : parts.joined()
        }
        return nil
    }

    // MARK: - Claude tool mapping

    static func toolKind(forClaudeTool name: String) -> AgentToolCall.Kind {
        switch name {
        case "Write":                    return .fileCreate
        case "Edit", "MultiEdit":        return .fileEdit
        case "Read", "NotebookEdit":     return .fileRead
        case "Bash":                     return .shell
        case "Grep", "Glob":             return .search
        case "WebFetch", "WebSearch":    return .web
        default:                         return .other
        }
    }

    static func toolTitle(forClaudeTool name: String, input: [String: Any]) -> String {
        switch name {
        case "Write", "Edit", "MultiEdit", "Read":
            if let p = input["file_path"] as? String {
                return "\(name) \((p as NSString).lastPathComponent)"
            }
        case "Bash":
            if let c = input["command"] as? String { return "$ \(c)" }
        case "Grep":
            if let q = input["pattern"] as? String { return "search “\(q)”" }
        default:
            break
        }
        return name
    }

    static func toolDetail(forClaudeTool name: String, input: [String: Any]) -> String? {
        switch name {
        case "Bash":      return input["command"] as? String
        case "Write":     return input["content"] as? String
        case "Edit":      return (input["old_string"] as? String).map { "- \($0)" }
        case "Grep":      return input["pattern"] as? String
        default:          return nil
        }
    }
}
