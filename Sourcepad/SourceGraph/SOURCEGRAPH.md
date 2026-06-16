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

## Test Harness

The query layer can be compiled without the app:

```sh
swiftc Sourcepad/SourceGraph/SourceGraphModel.swift \
  Sourcepad/SourceGraph/SourceGraphQueries.swift \
  Sourcepad/SourceGraph/Tests/SourceGraphQueriesHarness.swift \
  -o /tmp/sourcegraph-query-harness
/tmp/sourcegraph-query-harness
```

## Complete vs Stubbed

Complete in this vertical slice:

- Deterministic graph model and JSON encoding.
- File, directory/module, and indexed symbol nodes.
- `contains` edges for module-to-module, module-to-file, and file-to-symbol.
- File `references` edges derived from existing `ProjectIndex` backlinks.
- MCP stdio server with the eight requested tools.
- Pure query layer and standalone smoke harness.

Intentionally shallow for now:

- Symbol-to-symbol relationships are limited to containment; no call graph or inheritance graph is inferred yet.
- Link coverage depends on what Sourcepad has already indexed into `ProjectIndex.links`.
- The MCP server serves an in-memory snapshot loaded at process startup; it does not live-refresh while the app indexer changes.
