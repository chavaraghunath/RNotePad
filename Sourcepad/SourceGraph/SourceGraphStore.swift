// SPDX-License-Identifier: MIT
// Sourcepad — SourceGraph persistence and workspace resolution.

import Foundation

public enum SourceGraphStoreError: Error, CustomStringConvertible {
    case missingArgument
    case unreadableGraph(String)
    case workspaceNotIndexed(String)
    case cannotOpenIndex(String)

    public var description: String {
        switch self {
        case .missingArgument:
            return "missing SourceGraph path argument"
        case .unreadableGraph(let path):
            return "could not read SourceGraph JSON at \(path)"
        case .workspaceNotIndexed(let path):
            return "no indexed Sourcepad workspace contains \(path)"
        case .cannotOpenIndex(let path):
            return "could not open ProjectIndex at \(path)"
        }
    }
}

public enum SourceGraphStore {
    public static func loadOrBuild(argument: String) throws -> SourceGraph {
        let url = URL(fileURLWithPath: argument).standardizedFileURL
        if url.pathExtension.lowercased() == "json",
           let data = try? Data(contentsOf: url),
           let graph = try? SourceGraphJSON.decode(data) {
            return graph
        }

        let workspacePath = url.hasDirectoryPath ? url.path : url.deletingLastPathComponent().path
        let resolved = try resolveIndexedWorkspace(containing: workspacePath)
        guard let index = ProjectIndex(databaseURL: resolved.databaseURL) else {
            throw SourceGraphStoreError.cannotOpenIndex(resolved.databaseURL.path)
        }
        defer { index.close() }
        let graph = SourceGraphBuilder.build(index: index, workspaceRoot: resolved.rootURL)
        try write(graph, to: defaultKnowledgeURL(workspaceID: resolved.workspaceID))
        return graph
    }

    public static func write(_ graph: SourceGraph, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try SourceGraphJSON.encode(graph)
        try data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> SourceGraph {
        guard let data = try? Data(contentsOf: url) else {
            throw SourceGraphStoreError.unreadableGraph(url.path)
        }
        return try SourceGraphJSON.decode(data)
    }

    public static func defaultKnowledgeURL(workspaceID: String) -> URL {
        applicationSupportURL()
            .appendingPathComponent("Sourcepad/SourceGraph", isDirectory: true)
            .appendingPathComponent("\(workspaceID).sourcegraph.json", isDirectory: false)
    }

    private static func resolveIndexedWorkspace(containing path: String) throws -> (workspaceID: String, rootURL: URL, databaseURL: URL) {
        let support = applicationSupportURL()
        let workspacesDir = support.appendingPathComponent("Sourcepad/Workspaces", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(at: workspacesDir,
                                                                    includingPropertiesForKeys: nil,
                                                                    options: [.skipsHiddenFiles])) ?? []
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        var matches: [(id: String, root: URL)] = []
        for entry in entries where entry.pathExtension == "json" {
            guard let data = try? Data(contentsOf: entry),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String,
                  let roots = object["roots"] as? [String] else { continue }
            for rawRoot in roots {
                // Workspace roots are persisted as file:// URL strings
                // (e.g. "file:///Users/me/proj/"), not bare paths — parse them
                // as URLs first, falling back to a path only if that fails.
                let root = (URL(string: rawRoot).flatMap { $0.isFileURL ? $0 : nil }
                            ?? URL(fileURLWithPath: rawRoot)).standardizedFileURL
                let rootPath = root.path
                if target == rootPath || target.hasPrefix(rootPath + "/") {
                    matches.append((id, root))
                }
            }
        }
        matches.sort {
            if $0.root.path.count != $1.root.path.count {
                return $0.root.path.count > $1.root.path.count
            }
            return $0.id < $1.id
        }
        guard let match = matches.first else {
            throw SourceGraphStoreError.workspaceNotIndexed(path)
        }
        return (match.id,
                match.root,
                workspacesDir.appendingPathComponent("\(match.id).db", isDirectory: false))
    }

    private static func applicationSupportURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }
}
