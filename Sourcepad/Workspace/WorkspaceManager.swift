// SPDX-License-Identifier: MIT
// Sourcepad — load/save workspaces from disk and own the active workspace.
//
// Workspaces are stored one-JSON-per-workspace under
// ~/Library/Application Support/Sourcepad/Workspaces/<id>.json so the user
// can back them up, drop them into iCloud Drive, or hand-edit if needed.
//
// The active workspace is referenced by Preferences.defaultWorkspaceID. We
// keep that selection on launch; if the referenced workspace no longer
// exists (deleted JSON, etc.) we fall back to the most recently created.

import Foundation
import AppKit

public extension Notification.Name {
    static let sourcepadActiveWorkspaceChanged = Notification.Name("SourcepadActiveWorkspaceChanged")
    static let sourcepadWorkspaceListChanged   = Notification.Name("SourcepadWorkspaceListChanged")
}

public final class WorkspaceManager {

    public static let shared = WorkspaceManager()

    private(set) public var workspaces: [Workspace] = []

    /// The currently-active workspace. Always non-nil after first launch
    /// because we materialize a default workspace on demand.
    public var activeWorkspace: Workspace {
        get {
            if let id = Preferences.shared.defaultWorkspaceID,
               let ws = workspaces.first(where: { $0.id == id }) {
                return ws
            }
            return workspaces.first ?? ensureAtLeastOneWorkspace()
        }
        set {
            upsert(newValue)
            Preferences.shared.defaultWorkspaceID = newValue.id
            NotificationCenter.default.post(name: .sourcepadActiveWorkspaceChanged, object: nil)
        }
    }

    private init() {
        loadAll()
        _ = ensureAtLeastOneWorkspace()
    }

    // MARK: - Disk layout

    private var workspacesDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        let dir = support
            .appendingPathComponent("Sourcepad", isDirectory: true)
            .appendingPathComponent("Workspaces", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(for id: String) -> URL {
        workspacesDir.appendingPathComponent("\(id).json", isDirectory: false)
    }

    // MARK: - Load / save

    public func loadAll() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: workspacesDir,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles]) else {
            workspaces = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [Workspace] = []
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let ws   = try? decoder.decode(Workspace.self, from: data) else {
                NSLog("[Sourcepad] failed to decode workspace at \(url.path); skipping")
                continue
            }
            loaded.append(ws)
        }
        // Sort by creation date so UI lists are stable.
        loaded.sort { $0.createdAt < $1.createdAt }
        workspaces = loaded
    }

    public func save(_ workspace: Workspace) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(workspace)
            try data.write(to: fileURL(for: workspace.id), options: .atomic)
        } catch {
            NSLog("[Sourcepad] failed to save workspace \(workspace.id): \(error)")
        }
    }

    public func delete(_ id: String) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        workspaces.removeAll { $0.id == id }
        if Preferences.shared.defaultWorkspaceID == id {
            Preferences.shared.defaultWorkspaceID = workspaces.first?.id
        }
        NotificationCenter.default.post(name: .sourcepadWorkspaceListChanged, object: nil)
    }

    // MARK: - Mutation helpers

    /// Insert or replace `ws` in the workspaces list and persist.
    public func upsert(_ ws: Workspace) {
        if let idx = workspaces.firstIndex(where: { $0.id == ws.id }) {
            workspaces[idx] = ws
        } else {
            workspaces.append(ws)
        }
        save(ws)
        NotificationCenter.default.post(name: .sourcepadWorkspaceListChanged, object: nil)
    }

    /// Add `root` to the active workspace if not already present. Returns
    /// the updated workspace.
    @discardableResult
    public func addRoot(_ root: URL, to workspace: Workspace? = nil) -> Workspace {
        var ws = workspace ?? activeWorkspace
        let std = root.standardizedFileURL
        if !ws.roots.contains(where: { $0.standardizedFileURL == std }) {
            ws.roots.append(std)
            upsert(ws)
        }
        return ws
    }

    @discardableResult
    public func removeRoot(_ root: URL, from workspace: Workspace? = nil) -> Workspace {
        var ws = workspace ?? activeWorkspace
        let std = root.standardizedFileURL
        ws.roots.removeAll { $0.standardizedFileURL == std }
        upsert(ws)
        return ws
    }

    @discardableResult
    private func ensureAtLeastOneWorkspace() -> Workspace {
        if let existing = workspaces.first { return existing }
        let ws = Workspace(name: "Default")
        upsert(ws)
        Preferences.shared.defaultWorkspaceID = ws.id
        return ws
    }
}
