# SourceGraph

SourceGraph is Sourcepad's native code-knowledge graph and MCP stdio server. It is a clean-room Swift implementation built on Sourcepad's existing `ProjectIndex` SQLite data.

## Architecture

- `SourceGraphModel.swift`: deterministic Codable graph model.
- `SourceGraphBuilder.swift`: builds nodes and edges from `ProjectIndex.allFiles()`, `ProjectIndex.allSymbols()`, and `ProjectIndex.backlinks(toAbsolute:)`.
- `SourceGraphStore.swift`: reads existing knowledge JSON or builds from a Sourcepad indexed workspace, then writes a cached JSON file under `~/Library/Application Support/Sourcepad/SourceGraph/`.
- `SourceGraphQueries.swift`: pure Foundation query functions for the MCP tools and test harness.
- `SourceGraphMCPServer.swift`: newline-delimited JSON-RPC 2.0 over stdio for `initialize`, `tools/list`, and `tools/call`.

## JSON Schema

Top-level graph:

```json
{
  "schemaVersion": 1,
  "workspaceRoot": "/absolute/workspace/root",
  "nodes": [],
  "edges": []
}
```

Node fields:

- `id`: stable lowercase ASCII id.
- `kind`: `module`, `file`, `function`, `method`, `type`, or another normalized symbol kind from the index.
- `name`: display name.
- `path`: workspace-relative file or directory path when available.
- `line`, `column`: symbol location when available.
- `language`: file language from `ProjectIndex`.
- `summary`: short deterministic summary.
- `metadata`: sorted key/value metadata.

Edge fields:

- `id`: `<kind>:<from>-><to>`.
- `kind`: currently `contains` or `references`.
- `from`, `to`: node ids.
- `summary`: short deterministic summary.

Serialization uses `JSONEncoder` with `prettyPrinted`, `sortedKeys`, and `withoutEscapingSlashes`; nodes and edges are sorted by id before encoding.

## ID Scheme

IDs are lowercase and ASCII-safe. Non-alphanumeric runs become `-`.

- Workspace root module: `module:_`.
- Directory module: `module:<relative-directory-slug>`.
- File: `file:<relative-file-slug>`.
- Symbol: `symbol:<relative-file-slug>:<symbol-name-slug>:<line>:<column>`.

The line and column suffix disambiguates repeated local symbols while remaining stable for a fixed index.

## MCP Mode

The normal Sourcepad app binary also serves SourceGraph over stdio:

```sh
/path/to/Sourcepad.app/Contents/MacOS/Sourcepad --sourcegraph-mcp /path/to/workspace
```

The argument may be:

- A SourceGraph JSON file, which is loaded directly.
- A workspace path inside a Sourcepad indexed workspace. SourceGraph resolves the matching workspace metadata in Application Support, opens its `<workspace-id>.db`, builds the graph, and writes the cached JSON.

The stdio transport expects one JSON-RPC request per line and writes one JSON-RPC response per line.

## Tools

- `knowledge_stats`: counts nodes, edges, files, symbols, and languages.
- `core_concepts`: returns the most connected nodes by graph degree.
- `query_knowledge`: keyword search over ids, names, paths, languages, and summaries.
- `get_node`: full node record for an id.
- `peek`: short node preview for an id.
- `get_neighbors`: adjacent nodes and connecting edges; supports `direction` as `in`, `out`, or `both`.
- `get_collection`: nodes by kind, for example `file`, `module`, `function`, `type`, or `symbols`.
- `shortest_path`: shortest undirected path between two node ids.

## Tests

A three-tier suite lives in `Tests/`. Run all of it with:

```sh
bash Sourcepad/SourceGraph/Tests/run-all.sh
```

- **Tier 1 — unit** (`SourceGraphTests.swift`, via `run-tests.sh`): compiles the
  model + query layer standalone and asserts ~70 properties — encoding
  determinism, the slug/ID scheme, stats aggregation, degree-centrality ranking,
  query scoring, neighbor directions, collection pagination, BFS shortest-path,
  and the duplicate-node-id regression.
- **Tier 2 — protocol** (`mcp_protocol_test.py`): drives the real binary over
  JSON-RPC stdio — all eight tools on a crafted graph, plus error paths (unknown
  method/tool, missing args, malformed JSON, notifications), output determinism,
  and clean stderr (~37 assertions).
- **Tier 3 — end-to-end** (`workspace_e2e_test.py`): builds the graph from a real
  indexed workspace and sanity-checks the results.

## Capability & known limits (measured)

What is real and tested:

- Deterministic graph model and JSON encoding.
- File and directory/module nodes; `contains` edges (module→module, module→file)
  and file `references` edges from `ProjectIndex` backlinks.
- MCP stdio server with the eight tools, validated end-to-end.

Honest limitation, **confirmed by Tier 3 on a 96k-file workspace** (118,517 nodes
but `symbols: 0`):

- **The graph is currently file/module-level only.** `SourceGraphBuilder` reads
  `ProjectIndex.allSymbols()`, but the background indexer does not yet run a
  symbol-extraction pass, so the symbols table is empty and no `function` /
  `type` / `method` nodes are produced on real data. Making the graph genuinely
  symbol-aware requires wiring a tree-sitter symbol-extraction pass into
  `IndexerCoordinator` (calling `ProjectIndex.replaceSymbols`). Until then,
  `query_knowledge` / `core_concepts` operate over files and directories.
- No symbol-to-symbol relationships (call/inheritance graph) are inferred.
- The MCP server serves a startup snapshot; it does not live-refresh while the
  indexer changes.
