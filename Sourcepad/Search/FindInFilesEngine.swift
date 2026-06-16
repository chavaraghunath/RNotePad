// SPDX-License-Identifier: MIT
// Sourcepad — recursive search across a folder. Streams results back as each
// file finishes so the UI can display matches without waiting for the whole
// walk. Cancels cooperatively; skips binary files via a NUL-byte sniff;
// skips obvious build artefact directories (.git/node_modules/dist/build).

import Foundation

public struct FIFMatch {
    public let lineNumber: Int          // 1-based
    public let lineText: String
    public let matchRange: NSRange      // within lineText
}

public struct FIFResult {
    public let url: URL
    public let matches: [FIFMatch]
}

public struct FIFOptions {
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public init(caseSensitive: Bool = false, wholeWord: Bool = false) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
    }
}

public final class FindInFilesEngine {

    public static let excludedDirs: Set<String> = [
        ".git", "node_modules", "dist", ".build", "DerivedData",
        ".next", ".cache", "target", "Pods", "vendor", "build",
        ".idea", ".vscode", "__pycache__",
    ]

    private let queue = DispatchQueue(label: "Sourcepad.FIF", qos: .userInitiated)

    // `cancelled` is set from the caller (cancel()) and read on the search
    // queue/walk; `isRunning` is written from both the caller and the queue.
    // Back both with a lock so the cross-thread access is well-defined.
    private let stateLock = NSLock()
    private var _cancelled = false
    private var _isRunning = false
    private var cancelled: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _cancelled }
        set { stateLock.lock(); _cancelled = newValue; stateLock.unlock() }
    }
    public var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }; return _isRunning
    }
    private func setRunning(_ value: Bool) {
        stateLock.lock(); _isRunning = value; stateLock.unlock()
    }

    public init() {}

    public func cancel() { cancelled = true }

    public func search(query: String,
                       in root: URL,
                       options: FIFOptions,
                       onResult: @escaping (FIFResult) -> Void,
                       onProgress: @escaping (String) -> Void,
                       onComplete: @escaping (Int) -> Void) {
        guard !query.isEmpty else { onComplete(0); return }
        cancelled = false
        setRunning(true)
        queue.async { [weak self] in
            guard let self else { return }
            var totalMatches = 0
            self.walk(root) { fileURL in
                if self.cancelled { return false }
                DispatchQueue.main.async { onProgress(fileURL.path) }
                guard let result = self.scanFile(fileURL, query: query, options: options) else {
                    return true  // continue
                }
                totalMatches += result.matches.count
                DispatchQueue.main.async { onResult(result) }
                return true
            }
            let finalCount = totalMatches
            DispatchQueue.main.async {
                self.setRunning(false)
                onComplete(finalCount)
            }
        }
    }

    /// Returns false from `visit` to stop walking.
    private func walk(_ root: URL, visit: (URL) -> Bool) {
        let fm = FileManager.default
        guard let it = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                     errorHandler: nil) else { return }
        while let url = it.nextObject() as? URL {
            if cancelled { return }
            if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
                if FindInFilesEngine.excludedDirs.contains(url.lastPathComponent) {
                    it.skipDescendants()
                }
                continue
            }
            if !visit(url) { return }
        }
    }

    private func scanFile(_ url: URL, query: String, options: FIFOptions) -> FIFResult? {
        // 4 KB binary sniff.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 4096)
        if head.contains(0) { return nil }

        // Re-read the whole file as text.
        guard let data = try? Data(contentsOf: url), data.count < 50 * 1024 * 1024 else { return nil }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }

        let q = options.caseSensitive ? query : query.lowercased()
        var matches: [FIFMatch] = []
        var lineNumber = 0
        text.enumerateLines { line, _ in
            lineNumber += 1
            let hay = options.caseSensitive ? line : line.lowercased()
            var search = hay.startIndex
            while let r = hay.range(of: q, options: [], range: search..<hay.endIndex) {
                if options.wholeWord && !FindInFilesEngine.isWordBoundary(hay, range: r) {
                    search = hay.index(after: r.lowerBound)
                    continue
                }
                let lower = hay.distance(from: hay.startIndex, to: r.lowerBound)
                let upper = hay.distance(from: hay.startIndex, to: r.upperBound)
                matches.append(FIFMatch(lineNumber: lineNumber,
                                        lineText: line,
                                        matchRange: NSRange(location: lower, length: upper - lower)))
                search = r.upperBound
                if matches.count > 1000 { return }  // bail per-file at 1k
            }
        }
        return matches.isEmpty ? nil : FIFResult(url: url, matches: matches)
    }

    private static func isWordBoundary(_ s: String, range: Range<String.Index>) -> Bool {
        func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        let before: Character? = range.lowerBound > s.startIndex
            ? s[s.index(before: range.lowerBound)] : nil
        let after:  Character? = range.upperBound < s.endIndex
            ? s[range.upperBound] : nil
        if let b = before, isWord(b) { return false }
        if let a = after, isWord(a) { return false }
        return true
    }
}
