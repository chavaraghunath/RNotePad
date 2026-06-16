// SPDX-License-Identifier: MIT
// Sourcepad — parse the OpenAI-style SSE stream from mlx_lm.server.
//
// The server streams `data: {json}` lines (and `: keepalive` comments). Each json
// chunk carries `choices[0].delta.content` (a token) and a final chunk with
// `finish_reason: "stop"`; the stream may also end with `data: [DONE]`. This is a
// pure, incremental parser: feed it the accumulated buffer, get back the complete
// events plus the leftover partial line to carry forward. Headless-testable.

import Foundation

public enum MLXSSEParser {

    public enum Event: Equatable {
        case delta(String)   // a content token
        case done            // stream finished
        case error(String)
    }

    /// Parse all COMPLETE lines in `buffer`; return the events and the trailing
    /// partial line (no newline yet) to prepend to the next chunk.
    public static func parse(buffer: String) -> (events: [Event], remainder: String) {
        var events: [Event] = []
        // Keep the last segment as remainder unless the buffer ends with a newline.
        let endsClean = buffer.hasSuffix("\n")
        var lines = buffer.components(separatedBy: "\n")
        let remainder = endsClean ? "" : (lines.popLast() ?? "")

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(":") { continue }       // blank / keepalive comment
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { events.append(.done); continue }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
                events.append(.error(msg)); continue
            }
            guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first else { continue }
            if let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String, !content.isEmpty {
                events.append(.delta(content))
            }
            if let reason = first["finish_reason"] as? String, !reason.isEmpty {
                events.append(.done)
            }
        }
        return (events, remainder)
    }
}
