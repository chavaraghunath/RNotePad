// SPDX-License-Identifier: MIT
// Sourcepad — fzf-style fuzzy matching for palettes.
//
// The match accepts the query characters in order anywhere in the candidate.
// The score rewards:
//   - consecutive matched runs (so "RVC" scores better in "RootViewController"
//     than in "ResolveValueConstraint")
//   - matches at word boundaries (cap or after '/'/'_'/'-'/'.')
//   - matches at the start of the string
// And penalises:
//   - gaps between matched runs
//   - long tails after the last matched character
//
// All comparisons are case-insensitive. The matched index list is returned
// so the UI can underline / highlight matched chars in the cell.
//
// Designed to handle 50k candidates in <100ms on Apple Silicon.

import Foundation

public struct FuzzyMatch {
    public let score: Int
    /// Indices (into the candidate's UnicodeScalar view) that were matched.
    public let indices: [Int]
}

public enum PaletteFuzzy {

    /// Returns nil if any query char is missing in `candidate`. Empty query
    /// matches any candidate with score 0 and no indices.
    public static func match(query: String, candidate: String) -> FuzzyMatch? {
        if query.isEmpty { return FuzzyMatch(score: 0, indices: []) }

        let qChars = query.lowercased().unicodeScalars.map { $0 }
        let cChars = candidate.unicodeScalars.map { $0 }
        let cLower = candidate.lowercased().unicodeScalars.map { $0 }

        if qChars.count > cChars.count { return nil }

        // Greedy left-to-right with a single-token lookahead boost. This isn't
        // the optimal fzf algorithm (which uses DP), but the scoring is good
        // enough for typical palette usage and stays O(n).
        var qi = 0
        var indices: [Int] = []
        indices.reserveCapacity(qChars.count)
        var score = 0
        var streak = 0

        for i in 0..<cLower.count {
            guard qi < qChars.count else { break }
            if cLower[i] == qChars[qi] {
                var bonus = 1
                // Word-boundary bonus.
                if i == 0 { bonus += 4 }
                else {
                    let prev = cChars[i - 1]
                    if prev == "/" || prev == "_" || prev == "-" || prev == "." || prev == " " {
                        bonus += 3
                    }
                    // Camel-hump bonus: lowercase->uppercase boundary.
                    let isUpper = cChars[i].properties.isUppercase
                    let prevIsLower = !prev.properties.isUppercase &&
                        prev.properties.generalCategory == .lowercaseLetter
                    if isUpper && prevIsLower { bonus += 2 }
                }
                // Consecutive-match streak bonus.
                streak += 1
                bonus += streak
                score += bonus
                indices.append(i)
                qi += 1
            } else {
                streak = 0
                score -= 1  // small per-gap penalty
            }
        }

        guard qi == qChars.count else { return nil }
        // Penalise long tails so shorter candidates win when both contain
        // the query. Tail = chars after the last matched index.
        if let last = indices.last {
            let tail = cChars.count - last - 1
            score -= tail / 4
        }
        return FuzzyMatch(score: score, indices: indices)
    }
}
