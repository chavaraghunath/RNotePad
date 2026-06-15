// SPDX-License-Identifier: MIT
// Sourcepad — dependency-free local text embedder for conversation recall.
//
// Produces a fixed-dimension Float vector from text using hashed features
// (word unigrams + character trigrams, TF-weighted, L2-normalized). This is a
// classic "hashing trick" bag-of-features embedding: fully offline, no model,
// deterministic, and good enough for "find the conversation about X" semantic
// ranking via cosine similarity (see AgentStore.semanticRank).
//
// If a real local embedding model becomes available (e.g. via the MLX backend
// behind AI/AISemanticSearch), swap this out — AgentStore stores arbitrary
// Float vectors, so only the producer changes.

import Foundation

public enum AgentEmbedder {

    public static let dimensions = 256

    public static func embed(_ text: String) -> [Float] {
        var v = [Float](repeating: 0, count: dimensions)
        let lower = text.lowercased()
        let words = lower.split { !$0.isLetter && !$0.isNumber }
        for word in words {
            let w = String(word)
            v[Int(fnv1a(w) % UInt64(dimensions))] += 1.0
            // Character trigrams capture morphology / typos / partial matches.
            let padded = Array("#" + w + "#")
            if padded.count >= 3 {
                for i in 0...(padded.count - 3) {
                    let tri = String(padded[i..<i+3])
                    v[Int(fnv1a(tri) % UInt64(dimensions))] += 0.5
                }
            }
        }
        // L2-normalize so cosine similarity is just a dot product.
        var norm: Float = 0
        for x in v { norm += x * x }
        norm = norm.squareRoot()
        if norm > 0 { for i in v.indices { v[i] /= norm } }
        return v
    }

    /// Deterministic FNV-1a hash (Swift's Hasher is randomized per launch, which
    /// would make stored vectors incompatible across sessions).
    private static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
