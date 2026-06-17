// SPDX-License-Identifier: MIT
// Sourcepad — standalone unit tests for the SourceGraph model + query logic.
//
// Excluded from the app build (Tests/ is pruned). Run directly:
//     bash Sourcepad/SourceGraph/Tests/run-tests.sh
// which compiles this with SourceGraphModel.swift + SourceGraphQueries.swift and
// executes every scenario below. Exits non-zero on any failure.

import Foundation

// MARK: - Tiny assertion harness

final class T {
    static var passed = 0
    static var failed = 0
    static var failures: [String] = []

    static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() { passed += 1 }
        else { failed += 1; failures.append(name) }
    }

    static func eq<V: Equatable>(_ name: String, _ a: V, _ b: V) {
        if a == b { passed += 1 }
        else { failed += 1; failures.append("\(name)  (got \(a), expected \(b))") }
    }

    static func finish() -> Never {
        print("SourceGraph unit tests: \(passed) passed, \(failed) failed")
        for f in failures { print("  FAIL: \(f)") }
        exit(failed == 0 ? 0 : 1)
    }
}

// MARK: - Builders

func node(_ id: String, kind: String, name: String, path: String? = nil,
          language: String? = nil, summary: String = "") -> SourceGraphNode {
    SourceGraphNode(id: id, kind: kind, name: name, path: path, language: language,
                    summary: summary.isEmpty ? "\(kind) \(name)" : summary)
}
func edge(_ kind: String, _ from: String, _ to: String) -> SourceGraphEdge {
    SourceGraphEdge(kind: kind, from: from, to: to, summary: "\(from)->\(to)")
}

// A small but varied fixture graph:
//   module:. ──contains──▶ file:a.swift ──contains──▶ symbol Foo (type)
//                       └─▶ file:b.swift ──contains──▶ symbol bar (function)
//   file:a.swift ──references──▶ file:b.swift
func fixture() -> SourceGraph {
    let nodes = [
        node("module:.", kind: "module", name: "root", path: "."),
        node("file:a", kind: "file", name: "a.swift", path: "a.swift", language: "swift"),
        node("file:b", kind: "file", name: "b.swift", path: "b.swift", language: "swift"),
        node("file:c", kind: "file", name: "c.py", path: "c.py", language: "python"),
        node("sym:Foo", kind: "type", name: "Foo", path: "a.swift", summary: "type Foo in a.swift"),
        node("sym:bar", kind: "function", name: "bar", path: "b.swift", summary: "function bar in b.swift"),
    ]
    let edges = [
        edge("contains", "module:.", "file:a"),
        edge("contains", "module:.", "file:b"),
        edge("contains", "module:.", "file:c"),
        edge("contains", "file:a", "sym:Foo"),
        edge("contains", "file:b", "sym:bar"),
        edge("references", "file:a", "file:b"),
    ]
    return SourceGraph(workspaceRoot: "/ws", nodes: nodes, edges: edges)
}

// MARK: - Scenarios

func testModelAndEncoding() {
    let g = fixture()
    // Determinism: init sorts nodes/edges.
    T.check("nodes sorted by id", g.nodes == g.nodes.sorted())
    T.check("edges sorted by id", g.edges == g.edges.sorted())
    // Shuffled input → identical normalized graph.
    let shuffled = SourceGraph(workspaceRoot: "/ws", nodes: g.nodes.reversed(), edges: g.edges.reversed())
    T.eq("shuffle-invariant nodes", shuffled.nodes, g.nodes)
    T.eq("shuffle-invariant edges", shuffled.edges, g.edges)
    // Round-trip encode/decode.
    let data = try! SourceGraphJSON.encode(g)
    let back = try! SourceGraphJSON.decode(data)
    T.eq("json round-trip", back, g.normalized())
    // Encoding is byte-stable (sorted keys, sorted arrays).
    let data2 = try! SourceGraphJSON.encode(shuffled)
    T.check("encode is deterministic across shuffles", data == data2)
    // Edge id format.
    T.eq("edge id format", edge("references", "x", "y").id, "references:x->y")
}

func testSlugAndIDs() {
    T.eq("slug lowercases", SourceGraphID.slug("FooBar"), "foobar")
    T.eq("slug collapses non-alnum", SourceGraphID.slug("a//b__c"), "a-b-c")
    T.eq("slug trims dashes", SourceGraphID.slug("/leading/"), "leading")
    T.eq("slug empty → underscore", SourceGraphID.slug("!!!"), "_")
    T.eq("slug unicode → dashes", SourceGraphID.slug("café"), "caf")
    T.eq("module id", SourceGraphID.module("src/app"), "module:src-app")
    T.eq("module empty → dot", SourceGraphID.module(""), "module:_") // "." slugs to "_"
    T.eq("file id", SourceGraphID.file("src/App.swift"), "file:src-app-swift")
    T.eq("symbol id", SourceGraphID.symbol(relativeFile: "a.swift", name: "Foo", line: 3, column: 5),
         "symbol:a-swift:foo:3:5")
}

func testKnowledgeStats() {
    let s = SourceGraphQueries.knowledgeStats(fixture())
    T.eq("stats nodes", s.nodes, 6)
    T.eq("stats edges", s.edges, 6)
    T.eq("stats files", s.files, 3)
    T.eq("stats symbols", s.symbols, 2) // Foo + bar (not file/module)
    // Languages: swift=2, python=1, sorted by count desc then name.
    T.eq("stats lang count", s.languages.count, 2)
    T.eq("stats top language", s.languages.first?.name ?? "", "swift")
    T.eq("stats top language count", s.languages.first?.count ?? 0, 2)
    // Empty graph.
    let empty = SourceGraphQueries.knowledgeStats(SourceGraph(workspaceRoot: "/", nodes: [], edges: []))
    T.eq("empty stats zero", empty.nodes + empty.edges + empty.files + empty.symbols, 0)
}

func testCoreConcepts() {
    let c = SourceGraphQueries.coreConcepts(fixture(), limit: 10)
    // module:. has degree 3, file:a has 3 (contains sym:Foo, contains-from-module, references-out),
    // so the top node is the highest-degree one; verify it's module:. or file:a (degree 3).
    T.check("core concept top has max degree", (c.first?.score ?? 0) >= 3)
    // limit
    T.eq("core concepts limit", SourceGraphQueries.coreConcepts(fixture(), limit: 2).count, 2)
    T.eq("core concepts limit 0", SourceGraphQueries.coreConcepts(fixture(), limit: 0).count, 0)
    T.check("core concepts limit > n returns all",
            SourceGraphQueries.coreConcepts(fixture(), limit: 999).count == 6)
    // determinism: equal scores tie-break by id ascending
    let ranks = c.map { $0.id }
    T.check("core concepts deterministic order", ranks == SourceGraphQueries.coreConcepts(fixture(), limit: 10).map { $0.id })
    // empty graph
    T.eq("core concepts empty", SourceGraphQueries.coreConcepts(SourceGraph(workspaceRoot: "/", nodes: [], edges: []), limit: 5).count, 0)
}

func testQueryKnowledge() {
    let g = fixture()
    T.eq("empty query → []", SourceGraphQueries.queryKnowledge(g, query: "", limit: 10).count, 0)
    T.eq("whitespace query → []", SourceGraphQueries.queryKnowledge(g, query: "   ", limit: 10).count, 0)
    // exact name match ranks first
    let foo = SourceGraphQueries.queryKnowledge(g, query: "Foo", limit: 10)
    T.check("exact name match found", foo.contains { $0.name == "Foo" })
    T.eq("exact name match is top", foo.first?.name ?? "", "Foo")
    // case-insensitive
    T.check("case-insensitive", SourceGraphQueries.queryKnowledge(g, query: "foo", limit: 10).contains { $0.name == "Foo" })
    // path match
    T.check("path match", SourceGraphQueries.queryKnowledge(g, query: "b.swift", limit: 10).contains { $0.path == "b.swift" })
    // no match
    T.eq("no match → []", SourceGraphQueries.queryKnowledge(g, query: "zzzznotfound", limit: 10).count, 0)
    // limit
    T.check("query limit respected", SourceGraphQueries.queryKnowledge(g, query: "swift", limit: 2).count <= 2)
    // deterministic
    T.check("query deterministic",
            SourceGraphQueries.queryKnowledge(g, query: "swift", limit: 10).map { $0.id }
            == SourceGraphQueries.queryKnowledge(g, query: "swift", limit: 10).map { $0.id })
}

func testGetNodePeek() {
    let g = fixture()
    T.check("getNode existing", SourceGraphQueries.getNode(g, id: "file:a") != nil)
    T.check("getNode missing", SourceGraphQueries.getNode(g, id: "nope") == nil)
    T.check("peek existing", SourceGraphQueries.peek(g, id: "module:.") != nil)
    T.check("peek missing", SourceGraphQueries.peek(g, id: "nope") == nil)
    // peek score = degree (module:. degree 3)
    T.eq("peek score is degree", SourceGraphQueries.peek(g, id: "module:.")?.score ?? -1, 3)
}

func testGetNeighbors() {
    let g = fixture()
    let outA = SourceGraphQueries.getNeighbors(g, id: "file:a", direction: "out", limit: 50)
    T.check("out neighbors of file:a", outA.allSatisfy { $0.direction == "out" })
    T.check("file:a out includes sym:Foo + file:b", Set(outA.map { $0.node.id }) == Set(["sym:Foo", "file:b"]))
    let inA = SourceGraphQueries.getNeighbors(g, id: "file:a", direction: "in", limit: 50)
    T.check("file:a in is module:.", inA.map { $0.node.id } == ["module:."])
    let both = SourceGraphQueries.getNeighbors(g, id: "file:a", direction: "both", limit: 50)
    T.eq("file:a both count", both.count, 3)
    // missing node
    T.eq("neighbors of missing → []", SourceGraphQueries.getNeighbors(g, id: "nope").count, 0)
    // isolated node
    let iso = SourceGraph(workspaceRoot: "/", nodes: [node("x", kind: "file", name: "x")], edges: [])
    T.eq("isolated node neighbors → []", SourceGraphQueries.getNeighbors(iso, id: "x").count, 0)
    // limit
    T.check("neighbors limit", SourceGraphQueries.getNeighbors(g, id: "module:.", direction: "out", limit: 1).count == 1)
    // duplicate node ids must not crash (regression: Dictionary(uniqueKeysWithValues:))
    let dup = SourceGraph(workspaceRoot: "/", nodes: [node("d", kind: "file", name: "d"), node("d", kind: "file", name: "d2")],
                          edges: [edge("x", "d", "d")])
    _ = SourceGraphQueries.getNeighbors(dup, id: "d")
    T.check("duplicate node ids handled (no crash)", true)
}

func testGetCollection() {
    let g = fixture()
    T.eq("collection file", SourceGraphQueries.getCollection(g, kind: "file").count, 3)
    T.eq("collection plural files", SourceGraphQueries.getCollection(g, kind: "files").count, 3)
    T.eq("collection module", SourceGraphQueries.getCollection(g, kind: "module").count, 1)
    T.eq("collection symbols alias", SourceGraphQueries.getCollection(g, kind: "symbols").count, 2)
    T.eq("collection unknown → []", SourceGraphQueries.getCollection(g, kind: "widget").count, 0)
    // pagination
    T.eq("collection offset", SourceGraphQueries.getCollection(g, kind: "file", limit: 100, offset: 1).count, 2)
    T.eq("collection limit", SourceGraphQueries.getCollection(g, kind: "file", limit: 1, offset: 0).count, 1)
    T.eq("collection offset beyond → []", SourceGraphQueries.getCollection(g, kind: "file", limit: 10, offset: 99).count, 0)
}

func testShortestPath() {
    let g = fixture()
    // same node
    let same = SourceGraphQueries.shortestPath(g, from: "file:a", to: "file:a")
    T.check("same-node path is single node", same?.nodes.count == 1 && same?.edges.isEmpty == true)
    // direct edge
    let direct = SourceGraphQueries.shortestPath(g, from: "module:.", to: "file:a")
    T.check("direct path length 2 nodes", direct?.nodes.count == 2)
    // multi-hop: module:. → file:a → sym:Foo
    let multi = SourceGraphQueries.shortestPath(g, from: "module:.", to: "sym:Foo")
    T.check("multi-hop path found", multi != nil)
    T.eq("multi-hop node count", multi?.nodes.count ?? 0, 3)
    // undirected: sym:Foo → module:. (must traverse edges in reverse)
    T.check("undirected path found", SourceGraphQueries.shortestPath(g, from: "sym:Foo", to: "module:.") != nil)
    // disconnected
    let disc = SourceGraph(workspaceRoot: "/",
                           nodes: [node("a", kind: "file", name: "a"), node("b", kind: "file", name: "b")],
                           edges: [])
    T.check("disconnected → nil", SourceGraphQueries.shortestPath(disc, from: "a", to: "b") == nil)
    // missing endpoints
    T.check("missing from → nil", SourceGraphQueries.shortestPath(g, from: "nope", to: "file:a") == nil)
    T.check("missing to → nil", SourceGraphQueries.shortestPath(g, from: "file:a", to: "nope") == nil)
    // BFS finds the SHORTEST path: add a long detour and a short edge.
    let nodes = [node("s", kind: "file", name: "s"), node("m", kind: "file", name: "m"),
                 node("t", kind: "file", name: "t")]
    let edges = [edge("e", "s", "m"), edge("e", "m", "t"), edge("e", "s", "t")] // s-t direct + s-m-t
    let bfs = SourceGraphQueries.shortestPath(SourceGraph(workspaceRoot: "/", nodes: nodes, edges: edges), from: "s", to: "t")
    T.eq("BFS picks shortest (2 nodes)", bfs?.nodes.count ?? 0, 2)
    // duplicate node ids must not crash
    let dup = SourceGraph(workspaceRoot: "/", nodes: [node("d", kind: "file", name: "d"), node("d", kind: "file", name: "d2")],
                          edges: [edge("x", "d", "d")])
    _ = SourceGraphQueries.shortestPath(dup, from: "d", to: "d")
    T.check("shortestPath duplicate ids handled (no crash)", true)
}

// MARK: - Run

@main
struct SourceGraphTestRunner {
    static func main() {
        testModelAndEncoding()
        testSlugAndIDs()
        testKnowledgeStats()
        testCoreConcepts()
        testQueryKnowledge()
        testGetNodePeek()
        testGetNeighbors()
        testGetCollection()
        testShortestPath()
        T.finish()
    }
}
