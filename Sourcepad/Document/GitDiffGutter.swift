// SPDX-License-Identifier: MIT
// Sourcepad — git diff gutter. Compares the editor buffer against the file's
// HEAD blob and paints small markers in margin 3 (added/modified/deleted).
// No git library — shells out to /usr/bin/git which is present on every
// developer Mac.

import AppKit

public final class GitDiffGutter {

    public static let addedMarker:    Int32 = 5    // safe slot, not used by fold (25-31) or bookmark (24)
    public static let modifiedMarker: Int32 = 6
    public static let deletedMarker:  Int32 = 7

    private let sciView: NSView
    private let queue = DispatchQueue(label: "Sourcepad.git-gutter", qos: .utility)

    public init(sciView: NSView) {
        self.sciView = sciView
    }

    public func setup(addedColor: NSColor, modifiedColor: NSColor, deletedColor: NSColor) {
        SciSetupGitGutter(sciView,
                          GitDiffGutter.addedMarker,
                          GitDiffGutter.modifiedMarker,
                          GitDiffGutter.deletedMarker,
                          addedColor, modifiedColor, deletedColor)
    }

    /// Recompute the gutter against HEAD. No-op outside a git repo.
    public func refresh(for fileURL: URL?, currentText: String) {
        SciGitGutterClearLines(sciView,
                               GitDiffGutter.addedMarker,
                               GitDiffGutter.modifiedMarker,
                               GitDiffGutter.deletedMarker)
        guard let url = fileURL else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard let headText = GitDiffGutter.gitShowHEAD(for: url) else { return }
            let changes = GitDiffGutter.diffLines(old: headText, new: currentText)
            DispatchQueue.main.async {
                for (line, kind) in changes {
                    let marker: Int32
                    switch kind {
                    case .added:    marker = GitDiffGutter.addedMarker
                    case .modified: marker = GitDiffGutter.modifiedMarker
                    case .deleted:  marker = GitDiffGutter.deletedMarker
                    }
                    SciMarkerAdd(self.sciView, line, marker)
                }
            }
        }
    }

    public enum ChangeKind { case added, modified, deleted }

    /// Returns 0-based line numbers in `new` that differ from `old`.
    /// `deleted` lines point at the line ABOVE the gap (so a marker shows
    /// next to the surviving line).
    static func diffLines(old: String, new: String) -> [(line: Int, kind: ChangeKind)] {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        // Tiny LCS over lines. Fine for files up to ~10K lines.
        let n = oldLines.count, m = newLines.count
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 1...max(1, n) { if i > n { break }
            for j in 1...max(1, m) { if j > m { break }
                if oldLines[i - 1] == newLines[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        var changes: [(Int, ChangeKind)] = []
        var i = n, j = m
        while i > 0 && j > 0 {
            if oldLines[i - 1] == newLines[j - 1] { i -= 1; j -= 1; continue }
            if dp[i - 1][j] >= dp[i][j - 1] {
                changes.append((j, .deleted))     // line in new ABOVE the deleted line
                i -= 1
            } else {
                changes.append((j - 1, .added))   // new line
                j -= 1
            }
        }
        while j > 0 { changes.append((j - 1, .added)); j -= 1 }
        while i > 0 { changes.append((0, .deleted)); i -= 1 }
        // Promote consecutive added/deleted pairs to modified.
        let byLine = Dictionary(grouping: changes, by: { $0.0 })
        var out: [(Int, ChangeKind)] = []
        for (line, kinds) in byLine {
            let hasAdd = kinds.contains(where: { $0.1 == .added })
            let hasDel = kinds.contains(where: { $0.1 == .deleted })
            if hasAdd && hasDel { out.append((line, .modified)) }
            else if hasAdd      { out.append((line, .added)) }
            else                { out.append((line, .deleted)) }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    static func gitShowHEAD(for url: URL) -> String? {
        let dir = url.deletingLastPathComponent()
        // Resolve repo root.
        guard let repoRoot = runGit(["-C", dir.path, "rev-parse", "--show-toplevel"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !repoRoot.isEmpty else { return nil }
        let relPath: String
        if url.path.hasPrefix(repoRoot) {
            relPath = String(url.path.dropFirst(repoRoot.count).dropFirst())
        } else {
            return nil
        }
        return runGit(["-C", repoRoot, "show", "HEAD:" + relPath])
    }

    private static func runGit(_ args: [String]) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()  // discard
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
