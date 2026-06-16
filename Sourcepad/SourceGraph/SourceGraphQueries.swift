// SPDX-License-Identifier: MIT
// Sourcepad — pure SourceGraph query functions.

import Foundation

public struct SourceGraphStats: Codable, Equatable {
    public var nodes: Int
    public var edges: Int
    public var files: Int
    public var symbols: Int
    public var languages: [SourceGraphCount]
}

public struct SourceGraphCount: Codable, Equatable, Comparable {
    public var name: String
    public var count: Int

    public static func < (lhs: SourceGraphCount, rhs: SourceGraphCount) -> Bool {
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.name < rhs.name
    }
}

public struct SourceGraphNodeRef: Codable, Equatable {
    public var id: String
    public var kind: String
    public var name: String
    public var path: String?
    public var summary: String
    public var score: Int
}

public struct SourceGraphNeighbor: Codable, Equatable {
    public var direction: String
    public var edge: SourceGraphEdge
    public var node: SourceGraphNode
}

public struct SourceGraphPath: Codable, Equatable {
    public var nodes: [SourceGraphNode]
    public var edges: [SourceGraphEdge]
}

public enum SourceGraphQueries {
    public static func knowledgeStats(_ graph: SourceGraph) -> SourceGraphStats {
        var languageCounts: [String: Int] = [:]
        for node in graph.nodes where node.kind == "file" {
            if let language = node.language, !language.isEmpty {
                languageCounts[language, default: 0] += 1
            }
        }
        let languages = languageCounts
            .map { SourceGraphCount(name: $0.key, count: $0.value) }
            .sorted()
        return SourceGraphStats(nodes: graph.nodes.count,
                                edges: graph.edges.count,
                                files: graph.nodes.filter { $0.kind == "file" }.count,
                                symbols: graph.nodes.filter { isSymbolKind($0.kind) }.count,
                                languages: languages)
    }

    public static func coreConcepts(_ graph: SourceGraph, limit: Int = 10) -> [SourceGraphNodeRef] {
        let degree = degrees(graph)
        return graph.nodes
            .map { node in
                SourceGraphNodeRef(id: node.id,
                                   kind: node.kind,
                                   name: node.name,
                                   path: node.path,
                                   summary: node.summary,
                                   score: degree[node.id, default: 0])
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.id < $1.id
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public static func queryKnowledge(_ graph: SourceGraph, query: String, limit: Int = 20) -> [SourceGraphNodeRef] {
        let terms = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !terms.isEmpty else { return [] }
        let degree = degrees(graph)
        return graph.nodes.compactMap { node in
            let haystack = [node.id, node.kind, node.name, node.path ?? "", node.summary, node.language ?? ""]
                .joined(separator: " ")
                .lowercased()
            var score = 0
            for term in terms {
                if node.name.lowercased() == term { score += 30 }
                if node.name.lowercased().contains(term) { score += 15 }
                if (node.path ?? "").lowercased().contains(term) { score += 10 }
                if node.summary.lowercased().contains(term) { score += 5 }
                if haystack.contains(term) { score += 1 }
            }
            guard score > 0 else { return nil }
            return SourceGraphNodeRef(id: node.id,
                                      kind: node.kind,
                                      name: node.name,
                                      path: node.path,
                                      summary: node.summary,
                                      score: score + min(degree[node.id, default: 0], 20))
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.id < $1.id
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    public static func getNode(_ graph: SourceGraph, id: String) -> SourceGraphNode? {
        graph.nodes.first { $0.id == id }
    }

    public static func peek(_ graph: SourceGraph, id: String) -> SourceGraphNodeRef? {
        guard let node = getNode(graph, id: id) else { return nil }
        return SourceGraphNodeRef(id: node.id,
                                  kind: node.kind,
                                  name: node.name,
                                  path: node.path,
                                  summary: node.summary,
                                  score: degrees(graph)[node.id, default: 0])
    }

    public static func getNeighbors(_ graph: SourceGraph, id: String, direction: String = "both", limit: Int = 50) -> [SourceGraphNeighbor] {
        let nodes = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [SourceGraphNeighbor] = []
        let wantIn = direction == "both" || direction == "in"
        let wantOut = direction == "both" || direction == "out"
        for edge in graph.edges {
            if wantOut && edge.from == id, let node = nodes[edge.to] {
                out.append(SourceGraphNeighbor(direction: "out", edge: edge, node: node))
            }
            if wantIn && edge.to == id, let node = nodes[edge.from] {
                out.append(SourceGraphNeighbor(direction: "in", edge: edge, node: node))
            }
        }
        return out.sorted {
            if $0.direction != $1.direction { return $0.direction < $1.direction }
            if $0.edge.kind != $1.edge.kind { return $0.edge.kind < $1.edge.kind }
            return $0.node.id < $1.node.id
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    public static func getCollection(_ graph: SourceGraph, kind: String, limit: Int = 100, offset: Int = 0) -> [SourceGraphNode] {
        let normalized = kind.lowercased()
        let nodes = graph.nodes.filter { node in
            normalized == "symbols" ? isSymbolKind(node.kind) : node.kind == normalized || node.kind + "s" == normalized
        }
        let start = max(0, offset)
        guard start < nodes.count else { return [] }
        return Array(nodes[start..<min(nodes.count, start + max(0, limit))])
    }

    public static func shortestPath(_ graph: SourceGraph, from start: String, to goal: String) -> SourceGraphPath? {
        if start == goal, let node = getNode(graph, id: start) {
            return SourceGraphPath(nodes: [node], edges: [])
        }
        let nodes = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard nodes[start] != nil, nodes[goal] != nil else { return nil }
        var adjacency: [String: [SourceGraphEdge]] = [:]
        for edge in graph.edges {
            adjacency[edge.from, default: []].append(edge)
            adjacency[edge.to, default: []].append(SourceGraphEdge(kind: edge.kind, from: edge.to, to: edge.from, summary: edge.summary))
        }
        for key in adjacency.keys {
            adjacency[key]?.sort()
        }

        var queue = [start]
        var visited: Set<String> = [start]
        var previous: [String: (node: String, edge: SourceGraphEdge)] = [:]
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for edge in adjacency[current] ?? [] {
                let next = edge.to
                if visited.contains(next) { continue }
                visited.insert(next)
                previous[next] = (current, edge)
                if next == goal {
                    return buildPath(nodes: nodes, previous: previous, start: start, goal: goal)
                }
                queue.append(next)
            }
        }
        return nil
    }

    private static func buildPath(nodes: [String: SourceGraphNode],
                                  previous: [String: (node: String, edge: SourceGraphEdge)],
                                  start: String,
                                  goal: String) -> SourceGraphPath? {
        var nodeIDs = [goal]
        var edges: [SourceGraphEdge] = []
        var current = goal
        while current != start {
            guard let step = previous[current] else { return nil }
            edges.append(step.edge)
            current = step.node
            nodeIDs.append(current)
        }
        nodeIDs.reverse()
        edges.reverse()
        let pathNodes = nodeIDs.compactMap { nodes[$0] }
        return pathNodes.count == nodeIDs.count ? SourceGraphPath(nodes: pathNodes, edges: edges) : nil
    }

    private static func degrees(_ graph: SourceGraph) -> [String: Int] {
        var out: [String: Int] = [:]
        for edge in graph.edges {
            out[edge.from, default: 0] += 1
            out[edge.to, default: 0] += 1
        }
        return out
    }

    private static func isSymbolKind(_ kind: String) -> Bool {
        kind != "file" && kind != "module"
    }
}
