// SPDX-License-Identifier: MIT
// Sourcepad — parse `mlx_lm.generate` output into the answer + token usage.
//
// mlx_lm.generate prints:
//     ==========
//     <the generated answer>
//     ==========
//     Prompt: 39 tokens, 91.345 tokens-per-sec
//     Generation: 50 tokens, 238.379 tokens-per-sec
//     Peak memory: 0.345 GB
// We extract the answer (between the delimiter lines) and the prompt/generation
// token counts. Pure + Foundation-only so it's headless-testable.

import Foundation

public enum MLXOutputParser {

    public struct Result: Equatable {
        public let text: String
        public let promptTokens: Int
        public let generationTokens: Int
    }

    public static func parse(_ stdout: String) -> Result {
        let lines = stdout.components(separatedBy: "\n")
        let delims = lines.enumerated().compactMap { idx, line -> Int? in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("==========") ? idx : nil
        }
        let text: String
        if delims.count >= 2 {
            text = lines[(delims[0] + 1)..<delims[1]].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // No delimiters (older/edge output) — strip trailing stats lines.
            text = lines.filter { l in
                let t = l.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("Prompt:") && !t.hasPrefix("Generation:") && !t.hasPrefix("Peak memory:")
            }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Result(text: text,
                      promptTokens: tokenCount(prefix: "Prompt:", in: stdout),
                      generationTokens: tokenCount(prefix: "Generation:", in: stdout))
    }

    /// Pull N out of a line like "Prompt: 39 tokens, 91.345 tokens-per-sec".
    private static func tokenCount(prefix: String, in text: String) -> Int {
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix(prefix) else { continue }
            // first integer after the prefix
            let rest = t.dropFirst(prefix.count)
            var digits = ""
            for ch in rest {
                if ch.isNumber { digits.append(ch) }
                else if !digits.isEmpty { break }
            }
            return Int(digits) ?? 0
        }
        return 0
    }
}
