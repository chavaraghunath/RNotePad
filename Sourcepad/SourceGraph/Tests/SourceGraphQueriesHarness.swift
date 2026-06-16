// SPDX-License-Identifier: MIT
// Standalone smoke test:
// swiftc Sourcepad/SourceGraph/SourceGraphModel.swift \
//   Sourcepad/SourceGraph/SourceGraphQueries.swift \
//   Sourcepad/SourceGraph/Tests/SourceGraphQueriesHarness.swift -o /tmp/sourcegraph-query-harness

import Foundation

@main
private enum SourceGraphQueriesHarness {
    static func main() {
        let graph = SourceGraph(
            workspaceRoot: "/tmp/example",
            nodes: [
                SourceGraphNode(id: "module:_", kind: "module", name: "example", path: ".", summary: "Workspace root"),
                SourceGraphNode(id: "file:sources-app-swift", kind: "file", name: "App.swift", path: "Sources/App.swift", language: "swift", summary: "Swift app file"),
                SourceGraphNode(id: "symbol:sources-app-swift-run-3-1", kind: "function", name: "run", path: "Sources/App.swift", line: 3, column: 1, summary: "function run"),
            ],
            edges: [
                SourceGraphEdge(kind: "contains", from: "module:_", to: "file:sources-app-swift", summary: "module contains file"),
                SourceGraphEdge(kind: "contains", from: "file:sources-app-swift", to: "symbol:sources-app-swift-run-3-1", summary: "file contains run"),
            ])

        let stats = SourceGraphQueries.knowledgeStats(graph)
        precondition(stats.files == 1)
        precondition(stats.symbols == 1)
        precondition(SourceGraphQueries.queryKnowledge(graph, query: "run").first?.id == "symbol:sources-app-swift-run-3-1")
        precondition(SourceGraphQueries.shortestPath(graph, from: "module:_", to: "symbol:sources-app-swift-run-3-1")?.edges.count == 2)
        print("SourceGraphQueriesHarness passed")
    }
}
