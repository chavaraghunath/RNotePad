// SPDX-License-Identifier: MIT
// Sourcepad — owns the ProjectIndex + IndexerCoordinator for the active workspace.
//
// Single point that decides "which database / which indexer is live right
// now". When the user switches active workspaces, this singleton tears down
// the prior pair and stands a new pair up so the rest of the app can keep
// the same reference.

import Foundation
import AppKit

public final class WorkspaceIndexHost: IndexerCoordinatorDelegate {

    public static let shared = WorkspaceIndexHost()

    public private(set) var index: ProjectIndex?
    public private(set) var indexer: IndexerCoordinator?
    public private(set) var workspace: Workspace?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activeWorkspaceChanged),
            name: .sourcepadActiveWorkspaceChanged,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Boot the host using the current active workspace. Idempotent.
    public func start() {
        let ws = WorkspaceManager.shared.activeWorkspace
        load(workspace: ws)
    }

    @objc private func activeWorkspaceChanged() {
        let ws = WorkspaceManager.shared.activeWorkspace
        guard ws.id != workspace?.id else {
            // Same workspace, just metadata changed — keep index/indexer.
            workspace = ws
            return
        }
        load(workspace: ws)
    }

    private func load(workspace ws: Workspace) {
        // Tear down prior.
        indexer?.stop()
        indexer = nil
        index?.close()
        index = nil

        // Per-workspace SQLite under Application Support/Sourcepad/Workspaces/<id>.db
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        let dbURL = support
            .appendingPathComponent("Sourcepad/Workspaces", isDirectory: true)
            .appendingPathComponent("\(ws.id).db", isDirectory: false)

        guard let newIndex = ProjectIndex(databaseURL: dbURL) else {
            NSLog("[Sourcepad] Could not open ProjectIndex at \(dbURL.path)")
            workspace = ws
            return
        }

        let coord = IndexerCoordinator(workspace: ws, index: newIndex)
        coord.delegate = self
        coord.start()

        self.workspace = ws
        self.index = newIndex
        self.indexer = coord
    }

    // MARK: - IndexerCoordinatorDelegate (no-ops for Phase 2)
    //
    // Symbol / tag / link extraction will be hooked here by later phases
    // (Tree-sitter, LSP, wikilink parser). For now we only need the index
    // to know which files exist so ⌘P can list them.

    public func indexer(_ coordinator: IndexerCoordinator,
                        didUpsertFileID fileID: Int64,
                        absolutePath: String,
                        language: String?) {
        // Reserved for symbol/tag/link extraction in later phases.
        _ = (fileID, absolutePath, language)
    }

    public func indexer(_ coordinator: IndexerCoordinator,
                        didRemoveFileAtAbsolutePath absolutePath: String) {
        _ = absolutePath
    }
}
