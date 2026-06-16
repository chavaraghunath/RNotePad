// SPDX-License-Identifier: MIT
// Sourcepad — three-way merge for the agent/user co-edit guard.
//
// When the agent rewrites a file the user is editing (unsaved buffer), we
// reconcile three versions: the last-saved ancestor, the user's buffer ("mine"),
// and the agent's on-disk write ("theirs"). Rather than hand-roll merge logic
// (subtle, and a bug risks losing the user's work), we shell out to
// `git merge-file` — git's own merge engine — which auto-merges non-overlapping
// changes and emits standard conflict markers for the rest. Trivial cases are
// resolved directly so the common paths never spawn a process.

import Foundation

public enum ThreeWayMerge {

    public struct Result {
        public let merged: String       // merged text (with conflict markers if any)
        public let hadConflicts: Bool   // true if there were overlapping edits
    }

    /// Merge `mine` and `theirs` against their common `ancestor`. Returns nil if
    /// git can't run, so the caller falls back to a manual reload/keep prompt
    /// rather than risk losing data.
    public static func merge(ancestor: String, mine: String, theirs: String,
                             mineLabel: String = "your edits (editor)",
                             theirsLabel: String = "agent (on disk)") -> Result? {
        // Trivial, unambiguous cases — resolve directly (and correctly).
        if mine == theirs { return Result(merged: mine, hadConflicts: false) }
        if mine == ancestor { return Result(merged: theirs, hadConflicts: false) }   // only the agent changed
        if theirs == ancestor { return Result(merged: mine, hadConflicts: false) }   // only the user changed

        guard let git = locateGit() else { return nil }

        let dir = NSTemporaryDirectory()
        let token = UUID().uuidString
        let mineF = dir + "sp-merge-mine-\(token)"
        let baseF = dir + "sp-merge-base-\(token)"
        let theirsF = dir + "sp-merge-theirs-\(token)"
        defer { for f in [mineF, baseF, theirsF] { try? FileManager.default.removeItem(atPath: f) } }
        do {
            try mine.write(toFile: mineF, atomically: true, encoding: .utf8)
            try ancestor.write(toFile: baseF, atomically: true, encoding: .utf8)
            try theirs.write(toFile: theirsF, atomically: true, encoding: .utf8)
        } catch { return nil }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: git)
        // -p prints the result instead of overwriting mineF; -L labels (in file
        // order: mine, base, theirs) appear in any conflict markers.
        p.arguments = ["merge-file", "-p",
                       "-L", mineLabel, "-L", "last saved", "-L", theirsLabel,
                       mineF, baseF, theirsF]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        // git merge-file exit: 0 = clean, 1..<128 = number of conflicts,
        // >=128 = error.
        let status = p.terminationStatus
        if status >= 128 || status < 0 { return nil }
        let merged = String(decoding: data, as: UTF8.self)
        let hadConflicts = status != 0 || merged.contains("<<<<<<<")
        return Result(merged: merged, hadConflicts: hadConflicts)
    }

    private static func locateGit() -> String? {
        let candidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let p = String(dir) + "/git"
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }
}
