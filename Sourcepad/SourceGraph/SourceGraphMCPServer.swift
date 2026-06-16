// SPDX-License-Identifier: MIT
// Sourcepad — MCP stdio server for SourceGraph.

import Foundation

public final class SourceGraphMCPServer {
    private let graph: SourceGraph

    public init(graph: SourceGraph) {
        self.graph = graph.normalized()
    }

    public static func run(argument: String?) -> Int32 {
        guard let argument, !argument.isEmpty else {
            writeError("missing --sourcegraph-mcp argument")
            return 2
        }
        do {
            let graph = try SourceGraphStore.loadOrBuild(argument: argument)
            SourceGraphMCPServer(graph: graph).serve()
            return 0
        } catch {
            writeError("SourceGraph MCP failed: \(error)")
            return 1
        }
    }

    public func serve() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            handleLine(line)
        }
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            write(response: errorResponse(id: nil, code: -32700, message: "Parse error"))
            return
        }
        let id = object["id"]
        guard let method = object["method"] as? String else {
            write(response: errorResponse(id: id, code: -32600, message: "Invalid request"))
            return
        }

        if id == nil {
            return
        }

        switch method {
        case "initialize":
            write(response: successResponse(id: id, result: initializeResult()))
        case "tools/list":
            write(response: successResponse(id: id, result: ["tools": toolDescriptors()]))
        case "tools/call":
            let params = object["params"] as? [String: Any] ?? [:]
            write(response: handleToolCall(id: id, params: params))
        default:
            write(response: errorResponse(id: id, code: -32601, message: "Method not found"))
        }
    }

    private func handleToolCall(id: Any?, params: [String: Any]) -> [String: Any] {
        guard let name = params["name"] as? String else {
            return errorResponse(id: id, code: -32602, message: "Missing tool name")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        do {
            switch name {
            case "knowledge_stats":
                return try toolResponse(id: id, value: SourceGraphQueries.knowledgeStats(graph))
            case "core_concepts":
                return try toolResponse(id: id, value: SourceGraphQueries.coreConcepts(graph, limit: intArg(arguments, "limit", 10)))
            case "query_knowledge":
                return try toolResponse(id: id, value: SourceGraphQueries.queryKnowledge(graph,
                                                                                         query: stringArg(arguments, "query"),
                                                                                         limit: intArg(arguments, "limit", 20)))
            case "get_node":
                return try optionalToolResponse(id: id, value: SourceGraphQueries.getNode(graph, id: stringArg(arguments, "id")))
            case "peek":
                return try optionalToolResponse(id: id, value: SourceGraphQueries.peek(graph, id: stringArg(arguments, "id")))
            case "get_neighbors":
                return try toolResponse(id: id, value: SourceGraphQueries.getNeighbors(graph,
                                                                                       id: stringArg(arguments, "id"),
                                                                                       direction: stringArg(arguments, "direction", "both"),
                                                                                       limit: intArg(arguments, "limit", 50)))
            case "get_collection":
                return try toolResponse(id: id, value: SourceGraphQueries.getCollection(graph,
                                                                                        kind: stringArg(arguments, "kind"),
                                                                                        limit: intArg(arguments, "limit", 100),
                                                                                        offset: intArg(arguments, "offset", 0)))
            case "shortest_path":
                return try optionalToolResponse(id: id, value: SourceGraphQueries.shortestPath(graph,
                                                                                               from: stringArg(arguments, "from"),
                                                                                               to: stringArg(arguments, "to")))
            default:
                return errorResponse(id: id, code: -32602, message: "Unknown tool \(name)")
            }
        } catch {
            return toolErrorResponse(id: id, message: "\(error)")
        }
    }

    private func initializeResult() -> [String: Any] {
        [
            "protocolVersion": "2024-11-05",
            "serverInfo": [
                "name": "sourcegraph",
                "version": "0.1.0",
            ],
            "capabilities": [
                "tools": [:],
            ],
        ]
    }

    private func toolDescriptors() -> [[String: Any]] {
        [
            descriptor("knowledge_stats", "Counts nodes, edges, files, symbols, and languages.", [:]),
            descriptor("core_concepts", "Most connected nodes by graph degree.", ["limit": intSchema()]),
            descriptor("query_knowledge", "Keyword search over node ids, names, paths, languages, and summaries.",
                       ["query": stringSchema(), "limit": intSchema()]),
            descriptor("get_node", "Return the full node record for an id.", ["id": stringSchema()]),
            descriptor("peek", "Return a short summary for a node id.", ["id": stringSchema()]),
            descriptor("get_neighbors", "Return adjacent nodes and connecting edges.",
                       ["id": stringSchema(), "direction": stringSchema(), "limit": intSchema()]),
            descriptor("get_collection", "Return nodes of a kind, for example file, module, function, type, or symbols.",
                       ["kind": stringSchema(), "limit": intSchema(), "offset": intSchema()]),
            descriptor("shortest_path", "Find the shortest undirected path between two node ids.",
                       ["from": stringSchema(), "to": stringSchema()]),
        ]
    }

    private func descriptor(_ name: String, _ description: String, _ properties: [String: Any]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
            ],
        ]
    }

    private func stringSchema() -> [String: Any] {
        ["type": "string"]
    }

    private func intSchema() -> [String: Any] {
        ["type": "integer", "minimum": 0]
    }

    private func toolResponse<T: Encodable>(id: Any?, value: T) throws -> [String: Any] {
        successResponse(id: id, result: ["content": [["type": "text", "text": try jsonText(value)]]])
    }

    private func optionalToolResponse<T: Encodable>(id: Any?, value: T?) throws -> [String: Any] {
        guard let value else {
            return successResponse(id: id, result: ["content": [["type": "text", "text": "null"]]])
        }
        return try toolResponse(id: id, value: value)
    }

    private func toolErrorResponse(id: Any?, message: String) -> [String: Any] {
        successResponse(id: id, result: [
            "isError": true,
            "content": [["type": "text", "text": message]],
        ])
    }

    private func jsonText<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }

    private func stringArg(_ arguments: [String: Any], _ key: String, _ fallback: String? = nil) throws -> String {
        if let value = arguments[key] as? String { return value }
        if let fallback { return fallback }
        throw SourceGraphMCPError.missingArgument(key)
    }

    private func intArg(_ arguments: [String: Any], _ key: String, _ fallback: Int) -> Int {
        if let value = arguments[key] as? Int { return value }
        if let value = arguments[key] as? NSNumber { return value.intValue }
        return fallback
    }

    private func successResponse(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func write(response: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(response),
              let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        FileHandle.standardOutput.write((text + "\n").data(using: .utf8) ?? Data())
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
    }
}

public enum SourceGraphMCPError: Error, CustomStringConvertible {
    case missingArgument(String)

    public var description: String {
        switch self {
        case .missingArgument(let name):
            return "missing required argument '\(name)'"
        }
    }
}
