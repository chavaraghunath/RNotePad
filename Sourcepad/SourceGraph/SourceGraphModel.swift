// SPDX-License-Identifier: MIT
// Sourcepad — SourceGraph deterministic graph model.

import Foundation

public struct SourceGraph: Codable, Equatable {
    public var schemaVersion: Int
    public var workspaceRoot: String
    public var nodes: [SourceGraphNode]
    public var edges: [SourceGraphEdge]

    public init(schemaVersion: Int = 1,
                workspaceRoot: String,
                nodes: [SourceGraphNode],
                edges: [SourceGraphEdge]) {
        self.schemaVersion = schemaVersion
        self.workspaceRoot = workspaceRoot
        self.nodes = nodes.sorted()
        self.edges = edges.sorted()
    }

    public func normalized() -> SourceGraph {
        SourceGraph(schemaVersion: schemaVersion,
                    workspaceRoot: workspaceRoot,
                    nodes: nodes,
                    edges: edges)
    }
}

public struct SourceGraphNode: Codable, Equatable, Comparable {
    public var id: String
    public var kind: String
    public var name: String
    public var path: String?
    public var line: Int?
    public var column: Int?
    public var language: String?
    public var summary: String
    public var metadata: [SourceGraphMetadata]

    public init(id: String,
                kind: String,
                name: String,
                path: String?,
                line: Int? = nil,
                column: Int? = nil,
                language: String? = nil,
                summary: String,
                metadata: [SourceGraphMetadata] = []) {
        self.id = id
        self.kind = kind
        self.name = name
        self.path = path
        self.line = line
        self.column = column
        self.language = language
        self.summary = summary
        self.metadata = metadata.sorted()
    }

    public static func < (lhs: SourceGraphNode, rhs: SourceGraphNode) -> Bool {
        lhs.id < rhs.id
    }
}

public struct SourceGraphEdge: Codable, Equatable, Comparable {
    public var id: String
    public var kind: String
    public var from: String
    public var to: String
    public var summary: String

    public init(kind: String, from: String, to: String, summary: String) {
        self.kind = kind
        self.from = from
        self.to = to
        self.summary = summary
        self.id = "\(kind):\(from)->\(to)"
    }

    public static func < (lhs: SourceGraphEdge, rhs: SourceGraphEdge) -> Bool {
        lhs.id < rhs.id
    }
}

public struct SourceGraphMetadata: Codable, Equatable, Comparable {
    public var key: String
    public var value: String

    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    public static func < (lhs: SourceGraphMetadata, rhs: SourceGraphMetadata) -> Bool {
        if lhs.key != rhs.key { return lhs.key < rhs.key }
        return lhs.value < rhs.value
    }
}

public enum SourceGraphJSON {
    public static func encode(_ graph: SourceGraph) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(graph.normalized())
    }

    public static func decode(_ data: Data) throws -> SourceGraph {
        try JSONDecoder().decode(SourceGraph.self, from: data).normalized()
    }
}

public enum SourceGraphID {
    public static func module(_ relativePath: String) -> String {
        "module:\(slug(relativePath.isEmpty ? "." : relativePath))"
    }

    public static func file(_ relativePath: String) -> String {
        "file:\(slug(relativePath))"
    }

    public static func symbol(relativeFile: String, name: String, line: Int, column: Int) -> String {
        "symbol:\(slug(relativeFile)):\(slug(name)):\(line):\(column)"
    }

    public static func slug(_ raw: String) -> String {
        let lower = raw.lowercased()
        var out = ""
        var lastWasDash = false
        for scalar in lower.unicodeScalars {
            let v = scalar.value
            let isAlphaNum = (v >= 48 && v <= 57) || (v >= 97 && v <= 122)
            if isAlphaNum {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "_" : trimmed
    }
}
