// SPDX-License-Identifier: MIT
// Sourcepad — build SourceGraph from ProjectIndex.

import Foundation

public enum SourceGraphBuilder {
    public static func build(index: ProjectIndex, workspaceRoot: URL) -> SourceGraph {
        let rootPath = workspaceRoot.standardizedFileURL.path
        let files = index.allFiles()
            .map { (absolutePath: $0.absolutePath.standardizedPath, language: $0.language) }
            .sorted { $0.absolutePath < $1.absolutePath }
        let symbols = index.allSymbols()
            .map {
                (name: $0.name,
                 kind: $0.kind,
                 absolutePath: $0.absolutePath.standardizedPath,
                 line: $0.line,
                 col: $0.col)
            }
            .sorted {
                if $0.absolutePath != $1.absolutePath { return $0.absolutePath < $1.absolutePath }
                if $0.line != $1.line { return $0.line < $1.line }
                if $0.col != $1.col { return $0.col < $1.col }
                return $0.name < $1.name
            }

        var nodesByID: [String: SourceGraphNode] = [:]
        var edgesByID: [String: SourceGraphEdge] = [:]

        func addNode(_ node: SourceGraphNode) {
            nodesByID[node.id] = node
        }

        func addEdge(_ edge: SourceGraphEdge) {
            if edge.from != edge.to {
                edgesByID[edge.id] = edge
            }
        }

        addNode(SourceGraphNode(id: SourceGraphID.module("."),
                                kind: "module",
                                name: workspaceRoot.lastPathComponent.isEmpty ? rootPath : workspaceRoot.lastPathComponent,
                                path: ".",
                                summary: "Workspace root \(rootPath)"))

        for file in files {
            let relative = relativePath(file.absolutePath, rootPath: rootPath)
            let dir = directoryPart(relative)
            let moduleID = ensureModule(dir, rootPath: rootPath, nodesByID: &nodesByID, edgesByID: &edgesByID)
            let fileID = SourceGraphID.file(relative)
            addNode(SourceGraphNode(id: fileID,
                                    kind: "file",
                                    name: (relative as NSString).lastPathComponent,
                                    path: relative,
                                    language: file.language,
                                    summary: file.language.map { "\($0) file at \(relative)" } ?? "File at \(relative)"))
            addEdge(SourceGraphEdge(kind: "contains",
                                    from: moduleID,
                                    to: fileID,
                                    summary: "\(moduleID) contains \(relative)"))
        }

        for symbol in symbols {
            let relative = relativePath(symbol.absolutePath, rootPath: rootPath)
            let fileID = SourceGraphID.file(relative)
            guard nodesByID[fileID] != nil else { continue }
            let kind = normalizedSymbolKind(symbol.kind)
            let symbolID = SourceGraphID.symbol(relativeFile: relative,
                                                name: symbol.name,
                                                line: symbol.line,
                                                column: symbol.col)
            addNode(SourceGraphNode(id: symbolID,
                                    kind: kind,
                                    name: symbol.name,
                                    path: relative,
                                    line: symbol.line,
                                    column: symbol.col,
                                    summary: "\(kind) \(symbol.name) in \(relative):\(symbol.line)",
                                    metadata: symbol.kind.map { [SourceGraphMetadata("sourceKind", $0)] } ?? []))
            addEdge(SourceGraphEdge(kind: "contains",
                                    from: fileID,
                                    to: symbolID,
                                    summary: "\(relative) contains \(symbol.name)"))
        }

        // The index can contain the same absolute path more than once (e.g.
        // overlapping roots), so dedupe rather than trapping on duplicate keys.
        let fileIDByAbsolute = Dictionary(files.map {
            ($0.absolutePath, SourceGraphID.file(relativePath($0.absolutePath, rootPath: rootPath)))
        }, uniquingKeysWith: { first, _ in first })
        for target in files {
            guard let targetID = fileIDByAbsolute[target.absolutePath] else { continue }
            for source in index.backlinks(toAbsolute: target.absolutePath).map({ $0.standardizedPath }).sorted() {
                guard let sourceID = fileIDByAbsolute[source] else { continue }
                addEdge(SourceGraphEdge(kind: "references",
                                        from: sourceID,
                                        to: targetID,
                                        summary: "\(sourceID) references \(targetID)"))
            }
        }

        return SourceGraph(workspaceRoot: rootPath,
                           nodes: Array(nodesByID.values),
                           edges: Array(edgesByID.values))
    }

    private static func ensureModule(_ relativeDir: String,
                                     rootPath: String,
                                     nodesByID: inout [String: SourceGraphNode],
                                     edgesByID: inout [String: SourceGraphEdge]) -> String {
        let normalized = relativeDir.isEmpty ? "." : relativeDir
        let id = SourceGraphID.module(normalized)
        if nodesByID[id] != nil { return id }

        let parent = directoryPart(normalized)
        let parentID = ensureModule(parent, rootPath: rootPath, nodesByID: &nodesByID, edgesByID: &edgesByID)
        nodesByID[id] = SourceGraphNode(id: id,
                                        kind: "module",
                                        name: (normalized as NSString).lastPathComponent,
                                        path: normalized,
                                        summary: "Directory \(normalized)")
        let edge = SourceGraphEdge(kind: "contains",
                                   from: parentID,
                                   to: id,
                                   summary: "\(parentID) contains \(normalized)")
        edgesByID[edge.id] = edge
        return id
    }

    private static func relativePath(_ absolutePath: String, rootPath: String) -> String {
        if absolutePath == rootPath { return "." }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if absolutePath.hasPrefix(prefix) {
            return String(absolutePath.dropFirst(prefix.count))
        }
        return absolutePath
    }

    private static func directoryPart(_ relativePath: String) -> String {
        if relativePath == "." || relativePath.isEmpty { return "" }
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir == "." ? "" : dir
    }

    private static func normalizedSymbolKind(_ kind: String?) -> String {
        let lowered = (kind ?? "symbol").lowercased()
        if lowered.contains("function") || lowered == "func" { return "function" }
        if lowered.contains("method") { return "method" }
        if lowered.contains("class") || lowered.contains("struct") ||
            lowered.contains("enum") || lowered.contains("type") {
            return "type"
        }
        return lowered.isEmpty ? "symbol" : SourceGraphID.slug(lowered)
    }
}

private extension String {
    var standardizedPath: String {
        URL(fileURLWithPath: self).standardizedFileURL.path
    }
}
