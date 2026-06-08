// SPDX-License-Identifier: MIT
// Sourcepad — background workspace indexer.
//
// Responsibilities:
//   1. Walk each workspace root, populating ProjectIndex.files.
//   2. Watch each root via FSEvents and react to mutations.
//   3. Skip excluded directories (node_modules, .git, etc.) and files
//      whose size exceeds the configured cap (settings.indexerMaxFileSize).
//   4. Run at .utility QoS so an indexing pass on a fresh checkout never
//      stutters the UI.
//
// Symbol extraction, tag scanning, and link resolution are NOT done here —
// they're per-language passes the later phases plug in by calling
// ProjectIndex.replaceSymbols / replaceTags / replaceLinks for the file IDs
// this coordinator reports as changed via its delegate hook.

import Foundation
import CoreServices
import AppKit

public protocol IndexerCoordinatorDelegate: AnyObject {
    /// File row was inserted or updated. `fileID` is the ProjectIndex row id;
    /// `absolutePath` and `language` come from the upsert.
    func indexer(_ coordinator: IndexerCoordinator,
                 didUpsertFileID fileID: Int64,
                 absolutePath: String,
                 language: String?)

    /// File row was removed. `fileID` may already be invalid for downstream
    /// queries by the time this is dispatched — the CASCADE delete fires
    /// before the delegate call.
    func indexer(_ coordinator: IndexerCoordinator,
                 didRemoveFileAtAbsolutePath absolutePath: String)
}

public final class IndexerCoordinator {

    public weak var delegate: IndexerCoordinatorDelegate?

    private let index: ProjectIndex
    private let workspace: Workspace
    private let queue: DispatchQueue
    private var streams: [URL: FSEventStreamRef] = [:]
    private var rootIDByPath: [String: Int64] = [:]

    public init(workspace: Workspace, index: ProjectIndex) {
        self.workspace = workspace
        self.index = index
        self.queue = DispatchQueue(
            label: "sourcepad.indexer.\(workspace.id)",
            qos: .utility)
    }

    deinit {
        stop()
    }

    public func start() {
        guard workspace.settings.indexerEnabled else { return }
        queue.async { [weak self] in
            self?.bootstrapRoots()
        }
    }

    public func stop() {
        for (_, stream) in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
    }

    // MARK: - Bootstrap

    private func bootstrapRoots() {
        for root in workspace.roots {
            // Resolve symlinks via realpath() so FSEvents callbacks (which
            // the kernel delivers using canonical paths — e.g.
            // /private/tmp/... not /tmp/...) match our stored root. Apple's
            // URL.resolvingSymlinksInPath() does NOT resolve top-level
            // symlinks like /tmp; realpath() does.
            let path = canonicalPath(root.standardizedFileURL.path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard let rootID = index.upsertRoot(absolutePath: path) else { continue }
            rootIDByPath[path] = rootID
            initialScan(rootID: rootID, absoluteRoot: path)
            startWatching(absoluteRoot: path)
        }
    }

    /// realpath()-based canonicalisation. Returns the input unchanged if
    /// the path doesn't resolve (e.g. file missing).
    private func canonicalPath(_ path: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buf) != nil {
            return String(cString: buf)
        }
        return path
    }

    // MARK: - Initial scan

    private func initialScan(rootID: Int64, absoluteRoot: String) {
        let rootURL = URL(fileURLWithPath: absoluteRoot, isDirectory: true)
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else { return }

        var seen: Set<String> = []
        for case let url as URL in enumerator {
            // Skip excluded directories by descending no further.
            let basename = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if workspace.settings.excludedDirs.contains(basename) {
                    enumerator.skipDescendants()
                }
                continue
            }
            // File — upsert with metadata. Canonicalise the URL's path so
            // the prefix-strip works regardless of whether the enumerator
            // returns /tmp/foo or /private/tmp/foo (macOS toplevel symlinks).
            let canon = canonicalPath(url.path)
            guard canon.hasPrefix(absoluteRoot + "/") else { continue }
            let relPath = String(canon.dropFirst(absoluteRoot.count + 1))
            seen.insert(relPath)
            upsertFileRow(rootID: rootID, absolutePath: canon, relPath: relPath)
        }

        // Reconcile: anything in the DB under this root that we didn't see
        // got deleted while we were offline.
        for (absPath, _) in index.allFiles() where absPath.hasPrefix(absoluteRoot + "/") {
            let rel = String(absPath.dropFirst(absoluteRoot.count + 1))
            if !seen.contains(rel) {
                index.removeFile(rootID: rootID, relPath: rel)
                delegate?.indexer(self, didRemoveFileAtAbsolutePath: absPath)
            }
        }
    }

    // MARK: - FSEvents

    private func startWatching(absoluteRoot: String) {
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil)

        // UseCFTypes is REQUIRED — without it the eventPaths argument is
        // a `char **` array, not a CFArray. Our callback bridges via
        // NSArray which requires the CFArray form.
        let flags: UInt32 =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer) |
            UInt32(kFSEventStreamCreateFlagWatchRoot) |
            UInt32(kFSEventStreamCreateFlagUseCFTypes)

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, count, paths, flags, _) in
                guard let info else { return }
                let coordinator = Unmanaged<IndexerCoordinator>
                    .fromOpaque(info).takeUnretainedValue()
                let pathsArr = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                var flagList: [UInt32] = []
                for i in 0..<count {
                    flagList.append(flags[i])
                }
                coordinator.queue.async {
                    coordinator.handleEvents(paths: pathsArr, flags: flagList)
                }
            },
            &context,
            [absoluteRoot] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            NSLog("[Sourcepad] FSEventStreamCreate failed for \(absoluteRoot)")
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        if !FSEventStreamStart(stream) {
            NSLog("[Sourcepad] FSEventStreamStart failed for \(absoluteRoot)")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        streams[URL(fileURLWithPath: absoluteRoot)] = stream
    }

    private func handleEvents(paths: [String], flags: [UInt32]) {
        for (idx, raw) in paths.enumerated() {
            // Defensive canonicalisation. FSEvents normally already gives
            // canonical paths but realpath() is cheap.
            let path = canonicalPath(raw)
            let flag = idx < flags.count ? flags[idx] : 0

            // Which root does this event belong to?
            guard let (rootPath, rootID) = rootForPath(path) else { continue }

            // Inside an excluded directory? Skip.
            let rel = path.hasPrefix(rootPath + "/")
                ? String(path.dropFirst(rootPath.count + 1))
                : path
            if relPathIsExcluded(rel) { continue }

            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)

            if !exists {
                if flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
                    || flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                    index.removeFile(rootID: rootID, relPath: rel)
                    delegate?.indexer(self, didRemoveFileAtAbsolutePath: path)
                }
                continue
            }

            if isDir.boolValue {
                // Directory event — rescan only this directory's immediate
                // children (deep changes would have surfaced their own
                // events). Cheap on warm caches.
                rescanDirectory(rootID: rootID, absoluteRoot: rootPath, absoluteDir: path)
            } else {
                upsertFileRow(rootID: rootID, absolutePath: path, relPath: rel)
            }
        }
    }

    private func rescanDirectory(rootID: Int64, absoluteRoot: String, absoluteDir: String) {
        let url = URL(fileURLWithPath: absoluteDir, isDirectory: true)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for e in entries {
            let isDir = (try? e.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let canon = canonicalPath(e.path)
            if isDir {
                if workspace.settings.excludedDirs.contains(e.lastPathComponent) { continue }
                continue
            }
            guard canon.hasPrefix(absoluteRoot + "/") else { continue }
            let rel = String(canon.dropFirst(absoluteRoot.count + 1))
            upsertFileRow(rootID: rootID, absolutePath: canon, relPath: rel)
        }
    }

    // MARK: - Upsert helper

    private func upsertFileRow(rootID: Int64, absolutePath: String, relPath: String) {
        let url = URL(fileURLWithPath: absolutePath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: absolutePath)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let language = LexerRegistry.lexer(for: url.lastPathComponent)

        let contentHash: String?
        if size <= Int64(workspace.settings.indexerMaxFileSize) {
            // Cheap content hash for change detection. SHA-256 first 64
            // bytes for small files keeps the indexer responsive.
            contentHash = quickHash(of: url)
        } else {
            contentHash = nil
        }

        guard let fileID = index.upsertFile(
            rootID: rootID,
            relPath: relPath,
            mtime: mtime,
            size: size,
            language: language,
            contentHash: contentHash
        ) else { return }

        delegate?.indexer(self, didUpsertFileID: fileID, absolutePath: absolutePath, language: language)
    }

    // MARK: - Helpers

    private func rootForPath(_ path: String) -> (String, Int64)? {
        for (rootPath, rootID) in rootIDByPath {
            if path == rootPath || path.hasPrefix(rootPath + "/") {
                return (rootPath, rootID)
            }
        }
        return nil
    }

    private func relPathIsExcluded(_ rel: String) -> Bool {
        let segments = rel.split(separator: "/").map(String.init)
        for s in segments where workspace.settings.excludedDirs.contains(s) {
            return true
        }
        return false
    }

    /// Cheap "is this file the same as last time?" sentinel — not a real
    /// content hash, just modtime + size + first 256 bytes. Symbol passes
    /// can decide whether to do a full content read based on this.
    private func quickHash(of url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        var prefix: Data = Data()
        if let fh = try? FileHandle(forReadingFrom: url) {
            defer { try? fh.close() }
            prefix = (try? fh.read(upToCount: 256)) ?? Data()
        }
        var hasher = Hasher()
        hasher.combine(size)
        hasher.combine(mtime)
        hasher.combine(prefix)
        let value = hasher.finalize()
        return String(value, radix: 16)
    }
}
