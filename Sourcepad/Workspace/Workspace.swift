// SPDX-License-Identifier: MIT
// Sourcepad — workspace model.
//
// A workspace is a user-named collection of folder roots plus per-workspace
// settings (which sidebar tabs to show, which indexer features are enabled).
// Everything downstream — Cmd-P file picker, project symbol search, tag
// browser, backlinks, tasks dashboard — reads through the active workspace.
//
// The default workspace is auto-created on first launch with no roots.
// When the user opens a folder via "Open Folder…" we add that folder to
// the active workspace if it isn't already a root.

import Foundation

public struct Workspace: Codable, Equatable {

    /// Stable identifier; UUID string. Used as the on-disk filename.
    public var id: String

    /// Human-readable name shown in the title bar + workspace menu.
    public var name: String

    /// Folder roots shown in the sidebar. May be empty (workspace exists
    /// but no folder open yet).
    public var roots: [URL]

    /// Per-workspace settings.
    public var settings: Settings

    /// Wall-clock date the workspace was created. Useful for sort order.
    public var createdAt: Date

    public struct Settings: Codable, Equatable {

        /// Whether the background ProjectIndex runs for this workspace.
        public var indexerEnabled: Bool

        /// Files larger than this many bytes are listed in the index but
        /// not opened/hashed (skip the content scan that downstream
        /// symbol/tag passes need). Keeps the indexer responsive on
        /// repos with binary blobs or vendored bundles.
        public var indexerMaxFileSize: Int

        /// Directories (by basename) the indexer never descends into.
        /// Matches the legacy excluded set the Find-in-Files engine uses,
        /// kept in sync so users see consistent skip behavior.
        public var excludedDirs: Set<String>

        public init(indexerEnabled: Bool = true,
                    indexerMaxFileSize: Int = 1_000_000,
                    excludedDirs: Set<String> = Workspace.defaultExcludedDirs) {
            self.indexerEnabled = indexerEnabled
            self.indexerMaxFileSize = indexerMaxFileSize
            self.excludedDirs = excludedDirs
        }
    }

    public init(id: String = UUID().uuidString,
                name: String,
                roots: [URL] = [],
                settings: Settings = Settings(),
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.roots = roots
        self.settings = settings
        self.createdAt = createdAt
    }

    public static let defaultExcludedDirs: Set<String> = [
        ".git", "node_modules", "dist", ".build", "DerivedData",
        ".next", ".cache", "target", "Pods", "vendor", "build",
        ".idea", ".vscode", "__pycache__", ".venv", "venv",
        ".tox", ".mypy_cache", ".pytest_cache", ".terraform",
    ]
}
