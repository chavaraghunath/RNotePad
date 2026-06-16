// SPDX-License-Identifier: MIT
// Sourcepad — the dynamic MLX model registry.
//
// MLX community models live on the Hugging Face Hub under the `mlx-community`
// org. The Hub API (https://huggingface.co/api/models?author=mlx-community) is
// the dynamic, searchable registry — the Docker-Hub analog for local models.
// This fetches + parses that list (and per-model download sizes). The parsing
// is pure so it's headless-testable against captured JSON.

import Foundation

public struct MLXModelInfo: Equatable {
    public let id: String          // "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    public let downloads: Int
    public let likes: Int
    public var sizeBytes: Int64?   // total download size (filled lazily)

    public init(id: String, downloads: Int, likes: Int, sizeBytes: Int64? = nil) {
        self.id = id
        self.downloads = downloads
        self.likes = likes
        self.sizeBytes = sizeBytes
    }

    /// The model name without the org prefix, for display.
    public var name: String { (id as NSString).lastPathComponent }
}

public enum MLXModelRegistry {

    // MARK: - Pure parsing (headless-testable)

    /// Parse the `?author=mlx-community` list JSON (an array of model objects).
    public static func parseList(_ data: Data) -> [MLXModelInfo] {
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return arr.compactMap { m in
            guard let id = (m["id"] as? String) ?? (m["modelId"] as? String) else { return nil }
            return MLXModelInfo(id: id,
                                downloads: m["downloads"] as? Int ?? 0,
                                likes: m["likes"] as? Int ?? 0)
        }
    }

    /// Total download size from a single model's `?blobs=true` JSON (sums the
    /// `siblings[].size` fields).
    public static func parseSize(_ data: Data) -> Int64? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let siblings = obj["siblings"] as? [[String: Any]] else { return nil }
        let total = siblings.reduce(Int64(0)) { acc, s in
            acc + ((s["size"] as? Int).map(Int64.init) ?? 0)
        }
        return total > 0 ? total : nil
    }

    // MARK: - Network

    /// Search the mlx-community registry (newest/most-downloaded first), optionally
    /// filtered by a query. Calls completion on the main queue.
    public static func search(query: String?, limit: Int = 50,
                              completion: @escaping ([MLXModelInfo]) -> Void) {
        var comps = URLComponents(string: "https://huggingface.co/api/models")!
        var items = [
            URLQueryItem(name: "author", value: "mlx-community"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let q = query?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
            items.append(URLQueryItem(name: "search", value: q))
        }
        comps.queryItems = items
        guard let url = comps.url else { completion([]); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let models = data.map(parseList) ?? []
            DispatchQueue.main.async { completion(models) }
        }.resume()
    }

    /// Fetch a single model's total download size. Calls completion on the main queue.
    public static func fetchSize(modelID: String, completion: @escaping (Int64?) -> Void) {
        guard let url = URL(string: "https://huggingface.co/api/models/\(modelID)?blobs=true") else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let size = data.flatMap(parseSize)
            DispatchQueue.main.async { completion(size) }
        }.resume()
    }

    /// Human-readable byte size, e.g. "0.71 GB".
    public static func formatSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }
}
