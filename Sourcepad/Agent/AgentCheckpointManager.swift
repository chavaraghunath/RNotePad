// SPDX-License-Identifier: MIT
// Sourcepad — git-backed workspace checkpoints for the agent panel.
//
// The agent panel snapshots the workspace before each agent turn so the user
// can later review the diff or revert the agent's edits (the "ckpt" pattern,
// inspired by https://github.com/mohshomis/ckpt but a smaller, self-contained
// reimplementation).
//
// Design goals / safety contract:
//
//   * NEVER disturb the user's visible git state. We do not touch HEAD, the
//     branch, the index/staging area, stashes, or the user-visible reflog.
//     All snapshots live under a PRIVATE ref namespace:
//
//         refs/sourcepad/checkpoints/<id>
//
//   * We capture the working tree with PLUMBING and a TEMPORARY index file
//     (GIT_INDEX_FILE → a scratch file in $TMPDIR). The sequence is:
//
//         GIT_INDEX_FILE=<tmp> git read-tree HEAD     (seed from HEAD, or empty)
//         GIT_INDEX_FILE=<tmp> git add -A             (stage the live worktree)
//         GIT_INDEX_FILE=<tmp> git write-tree         → <tree>
//         git commit-tree <tree> -p HEAD -m ...       → <commit>
//         git update-ref refs/sourcepad/checkpoints/<id> <commit>
//
//     The user's real index file is never opened for writing; the scratch
//     index is deleted afterwards.
//
//   * `diff(since:)` compares the snapshot tree against the LIVE working tree
//     (again via a scratch index so the user's index is untouched).
//
//   * `restore(to:)` reverts TRACKED-at-snapshot files only — see the doc on
//     `restore(to:)` for the exact, conservative semantics.
//
//   * Degrades gracefully: outside a git repo (or if git is missing) the
//     manager is a safe no-op — snapshot() returns nil, diff() returns "",
//     restore() returns false. We NEVER `git init` the user's directory.
//
// Foundation-only; git is spawned via Process. Mirrors the style of
// Workspace/ProjectIndex.swift and Agent/AgentStore.swift.

import Foundation

public final class AgentCheckpointManager {

    /// A single captured working-tree state.
    public struct Checkpoint {
        public let id: String          // opaque, also the ref leaf name
        public let createdAt: Double    // Unix epoch seconds
        public let label: String
    }

    // MARK: - Configuration

    /// Private ref namespace. Lives entirely outside refs/heads, refs/tags,
    /// refs/stash and the user-visible reflog.
    private static let refPrefix = "refs/sourcepad/checkpoints/"

    private let workingDirectory: String
    private let queue = DispatchQueue(label: "sourcepad.agent.checkpoints")

    /// Resolved absolute path to a git executable, or nil if none was found.
    private let gitPath: String?

    /// Absolute path to the repository's top level (work tree root), or nil
    /// when `workingDirectory` is not inside a git work tree. When nil the
    /// manager is a safe no-op.
    private let repoTopLevel: String?

    // MARK: - Lifecycle

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        let git = Self.locateGit()
        self.gitPath = git
        self.repoTopLevel = Self.resolveTopLevel(git: git, dir: workingDirectory)
    }

    /// Whether this manager is operating against a real git work tree.
    public var isUsable: Bool { repoTopLevel != nil }

    // MARK: - Snapshot

    /// Snapshot the current working-tree state into a private checkpoint ref.
    /// Returns nil if the directory isn't a usable git work tree, or if any
    /// plumbing step fails. Does NOT modify HEAD, the branch, the user's
    /// index, stashes, or the user-visible reflog.
    public func snapshot(label: String) -> Checkpoint? {
        queue.sync {
            guard let git = gitPath, let root = repoTopLevel else { return nil }

            let now = Date().timeIntervalSince1970
            let id = Self.makeID(now: now)
            let scratch = Self.makeScratchIndexPath()
            defer { try? FileManager.default.removeItem(atPath: scratch) }

            // Seed the scratch index from HEAD when HEAD exists; on an empty
            // repo (no commits yet) we start from an empty index instead.
            let headExists = run(git, ["-C", root, "rev-parse", "--verify", "--quiet", "HEAD"]) != nil
            let scratchEnv = ["GIT_INDEX_FILE": scratch]
            if headExists {
                guard run(git, ["-C", root, "read-tree", "HEAD"], env: scratchEnv) != nil else { return nil }
            }

            // Stage the entire live working tree (additions, modifications,
            // deletions, untracked) into the scratch index only.
            guard run(git, ["-C", root, "add", "-A"], env: scratchEnv) != nil else { return nil }

            // Write the scratch index out as a tree object.
            guard let treeRaw = run(git, ["-C", root, "write-tree"], env: scratchEnv) else { return nil }
            let tree = treeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tree.isEmpty else { return nil }

            // Build a commit object pointing at the snapshot tree. Parent it on
            // HEAD when available so the snapshot is browsable/diffable, but we
            // never move HEAD or any branch to it.
            var commitArgs = ["-C", root, "commit-tree", tree, "-m", "sourcepad-checkpoint: \(label)"]
            if headExists,
               let headSha = run(git, ["-C", root, "rev-parse", "HEAD"])?
                   .trimmingCharacters(in: .whitespacesAndNewlines),
               !headSha.isEmpty {
                commitArgs += ["-p", headSha]
            }
            // Deterministic, non-identifying committer metadata so the snapshot
            // never inherits or perturbs user identity config behaviour.
            let commitEnv = [
                "GIT_AUTHOR_NAME": "Sourcepad", "GIT_AUTHOR_EMAIL": "sourcepad@localhost",
                "GIT_COMMITTER_NAME": "Sourcepad", "GIT_COMMITTER_EMAIL": "sourcepad@localhost",
            ]
            guard let commitRaw = run(git, commitArgs, env: commitEnv) else { return nil }
            let commit = commitRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !commit.isEmpty else { return nil }

            // Publish under our private ref namespace only.
            guard run(git, ["-C", root, "update-ref", Self.refPrefix + id, commit]) != nil else { return nil }

            return Checkpoint(id: id, createdAt: now, label: label)
        }
    }

    // MARK: - Diff

    /// Unified diff of what changed in the working tree SINCE the checkpoint.
    /// Compares the checkpoint's snapshot tree against the LIVE working tree
    /// (including untracked files), without touching the user's index. Returns
    /// "" when there is no diff, the checkpoint is unknown, or the manager is a
    /// no-op.
    public func diff(since checkpoint: Checkpoint) -> String {
        queue.sync {
            guard let git = gitPath, let root = repoTopLevel else { return "" }
            guard let tree = snapshotTree(git: git, root: root, id: checkpoint.id) else { return "" }

            // Build a tree of the current working state in a scratch index so
            // untracked files participate in the diff, while the user's real
            // index is never written.
            let scratch = Self.makeScratchIndexPath()
            defer { try? FileManager.default.removeItem(atPath: scratch) }
            let scratchEnv = ["GIT_INDEX_FILE": scratch]
            let headExists = run(git, ["-C", root, "rev-parse", "--verify", "--quiet", "HEAD"]) != nil
            if headExists {
                guard run(git, ["-C", root, "read-tree", "HEAD"], env: scratchEnv) != nil else { return "" }
            }
            guard run(git, ["-C", root, "add", "-A"], env: scratchEnv) != nil else { return "" }
            guard let liveTreeRaw = run(git, ["-C", root, "write-tree"], env: scratchEnv) else { return "" }
            let liveTree = liveTreeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !liveTree.isEmpty else { return "" }

            // tree-to-tree diff: old = checkpoint, new = live worktree.
            return run(git, ["-C", root, "diff", tree, liveTree]) ?? ""
        }
    }

    // MARK: - Restore

    /// Restore the working tree to the checkpoint state, reverting agent edits.
    ///
    /// Exact (conservative) semantics:
    ///   * Every file present in the checkpoint snapshot is written back to its
    ///     snapshot content (overwriting any later agent modification).
    ///   * Every file that EXISTS NOW but did NOT exist in the snapshot is
    ///     removed — these are files the agent created after the snapshot. This
    ///     is computed as a tree-vs-tree diff (snapshot → current working tree)
    ///     filtered to status "A" (added). We only delete such added files; we
    ///     never blanket-delete untracked content, so user files that predate
    ///     the snapshot are left intact.
    ///
    /// All writes go through a scratch index (GIT_INDEX_FILE); the user's real
    /// index, HEAD, branch and stashes are untouched. Returns false on any
    /// failure or when the manager is a no-op.
    public func restore(to checkpoint: Checkpoint) -> Bool {
        queue.sync {
            guard let git = gitPath, let root = repoTopLevel else { return false }
            guard let tree = snapshotTree(git: git, root: root, id: checkpoint.id) else { return false }

            // 1) Delete files the agent ADDED after the snapshot (present now,
            //    absent in snapshot). Diff snapshot → current working tree.
            let scratch = Self.makeScratchIndexPath()
            defer { try? FileManager.default.removeItem(atPath: scratch) }
            let scratchEnv = ["GIT_INDEX_FILE": scratch]
            let headExists = run(git, ["-C", root, "rev-parse", "--verify", "--quiet", "HEAD"]) != nil
            if headExists {
                guard run(git, ["-C", root, "read-tree", "HEAD"], env: scratchEnv) != nil else { return false }
            }
            guard run(git, ["-C", root, "add", "-A"], env: scratchEnv) != nil else { return false }
            guard let liveTreeRaw = run(git, ["-C", root, "write-tree"], env: scratchEnv) else { return false }
            let liveTree = liveTreeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !liveTree.isEmpty else { return false }

            if let nameStatus = run(git, ["-C", root, "diff", "--name-status", "-z", tree, liveTree]) {
                for rel in Self.addedPaths(fromNameStatusZ: nameStatus) {
                    let abs = (root as NSString).appendingPathComponent(rel)
                    try? FileManager.default.removeItem(atPath: abs)
                }
            }

            // 2) Materialise the snapshot tree back onto disk. read-tree into a
            //    fresh scratch index then checkout-index -a -f overwrites every
            //    snapshot file with its captured content.
            let scratch2 = Self.makeScratchIndexPath()
            defer { try? FileManager.default.removeItem(atPath: scratch2) }
            let env2 = ["GIT_INDEX_FILE": scratch2]
            guard run(git, ["-C", root, "read-tree", tree], env: env2) != nil else { return false }
            guard run(git, ["-C", root, "checkout-index", "-a", "-f"], env: env2) != nil else { return false }

            return true
        }
    }

    // MARK: - Listing

    /// All checkpoints, newest first.
    public func checkpoints() -> [Checkpoint] {
        queue.sync {
            guard let git = gitPath, let root = repoTopLevel else { return [] }
            // List our private refs with their commit subject + commit time.
            // Format: <refname>\x1f<unixtime>\x1f<subject>
            let fmt = "%(refname)\u{1f}%(committerdate:unix)\u{1f}%(subject)"
            guard let out = run(git, ["-C", root, "for-each-ref",
                                      "--format=" + fmt, Self.refPrefix]) else { return [] }
            var result: [Checkpoint] = []
            for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: "\u{1f}", maxSplits: 2,
                                       omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 1 else { continue }
                let refName = parts[0]
                guard refName.hasPrefix(Self.refPrefix) else { continue }
                let id = String(refName.dropFirst(Self.refPrefix.count))
                let createdAt = parts.count >= 2 ? (Double(parts[1]) ?? 0) : 0
                let subject = parts.count >= 3 ? parts[2] : ""
                let label = subject.hasPrefix("sourcepad-checkpoint: ")
                    ? String(subject.dropFirst("sourcepad-checkpoint: ".count))
                    : subject
                result.append(Checkpoint(id: id, createdAt: createdAt, label: label))
            }
            // Newest first (createdAt desc; id is monotonic as a tiebreaker).
            return result.sorted {
                $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id > $1.id
            }
        }
    }

    // MARK: - Private helpers

    /// Resolve a checkpoint id to its snapshot tree sha, or nil if the ref is
    /// gone / unparseable.
    private func snapshotTree(git: String, root: String, id: String) -> String? {
        // `<commit>^{tree}` resolves the commit's top tree.
        guard let raw = run(git, ["-C", root, "rev-parse", "--verify", "--quiet",
                                  Self.refPrefix + id + "^{tree}"]) else { return nil }
        let tree = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return tree.isEmpty ? nil : tree
    }

    /// Parse `git diff --name-status -z` output, returning the relative paths
    /// of files with status "A" (added in the new tree relative to the old).
    private static func addedPaths(fromNameStatusZ z: String) -> [String] {
        // -z output: STATUS\0PATH\0STATUS\0PATH\0...  (renames/copies emit two
        // paths, but tree-vs-tree without -M/-C won't produce R/C entries).
        let fields = z.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        var paths: [String] = []
        var i = 0
        while i < fields.count {
            let status = fields[i]
            if status.isEmpty { i += 1; continue }
            let code = status.first!
            if code == "R" || code == "C" {
                // <status>\0<old>\0<new> — skip, restore re-materialises via tree.
                i += 3
            } else {
                guard i + 1 < fields.count else { break }
                if code == "A" { paths.append(fields[i + 1]) }
                i += 2
            }
        }
        return paths
    }

    private static func makeID(now: Double) -> String {
        // Sortable, collision-resistant: milliseconds + short random suffix.
        let ms = UInt64((now * 1000).rounded())
        let rand = String(format: "%04x", UInt16.random(in: 0...UInt16.max))
        return String(format: "%015llu-%@", ms, rand)
    }

    private static func makeScratchIndexPath() -> String {
        let name = "sourcepad-ckpt-index-\(UUID().uuidString)"
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
    }

    // MARK: - git location + invocation

    private static func locateGit() -> String? {
        let fm = FileManager.default
        // Honour PATH first, then well-known absolute locations.
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = (String(dir) as NSString).appendingPathComponent("git")
                if fm.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        for candidate in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"] {
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static func resolveTopLevel(git: String?, dir: String) -> String? {
        guard let git else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue
        else { return nil }
        guard let out = runGitStatic(git, ["-C", dir, "rev-parse", "--show-toplevel"]) else { return nil }
        let top = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return top.isEmpty ? nil : top
    }

    /// Instance convenience that closes over the resolved git path.
    private func run(_ git: String, _ args: [String], env: [String: String] = [:]) -> String? {
        Self.runGitStatic(git, args, env: env)
    }

    /// Spawn git, capture stdout, return it on exit status 0 (else nil). stderr
    /// is captured and discarded. Bounded so a wedged git can never hang the
    /// caller forever.
    private static func runGitStatic(_ git: String, _ args: [String],
                                     env: [String: String] = [:]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: git)
        task.arguments = args

        // Start from the current environment, then overlay caller env and a few
        // hardening keys so prompts / pagers / locale never wedge us.
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        environment["GIT_TERMINAL_PROMPT"] = "0"   // never prompt for credentials
        environment["GIT_PAGER"] = "cat"
        environment["GIT_OPTIONAL_LOCKS"] = "0"     // avoid taking index.lock for read paths
        environment["LC_ALL"] = "C"
        task.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        task.standardInput = FileHandle.nullDevice

        // Drain pipes on background queues so a large diff can't deadlock the
        // child against a full OS pipe buffer.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let drainQueue = DispatchQueue(label: "sourcepad.git.drain", attributes: .concurrent)
        group.enter()
        drainQueue.async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        drainQueue.async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do { try task.run() } catch {
            _ = errData  // silence unused in error path
            return nil
        }

        // Bound the wait. git plumbing here is fast; 30s is a generous ceiling.
        let deadline = DispatchTime.now() + .seconds(30)
        let finished = waitWithTimeout(task, deadline: deadline)
        if !finished {
            task.terminate()
            _ = waitWithTimeout(task, deadline: .now() + .seconds(2))
            return nil
        }

        group.wait()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: outData, encoding: .utf8) ?? ""
    }

    /// Poll for process exit until `deadline`. Returns true if it exited.
    private static func waitWithTimeout(_ task: Process, deadline: DispatchTime) -> Bool {
        while task.isRunning {
            if DispatchTime.now() >= deadline { return false }
            usleep(5_000)  // 5ms
        }
        return true
    }
}
