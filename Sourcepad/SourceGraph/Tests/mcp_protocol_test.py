#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Black-box test of the SourceGraph MCP server: spawns the real Sourcepad binary
# with --sourcegraph-mcp <graph.json> and drives it over JSON-RPC stdio.
import json, os, subprocess, sys, tempfile

BIN = os.environ.get("SOURCEPAD_BIN",
    os.path.join(os.path.dirname(__file__), "../../dist/Sourcepad.app/Contents/MacOS/Sourcepad"))
BIN = os.path.abspath(BIN)

passed = 0; failed = 0; failures = []
def check(name, cond):
    global passed, failed
    if cond: passed += 1
    else: failed += 1; failures.append(name)

def node(nid, kind, name, **kw):
    n = {"id": nid, "kind": kind, "name": name, "summary": kw.get("summary", f"{kind} {name}"), "metadata": []}
    for k in ("path", "language", "line", "column"):
        if k in kw: n[k] = kw[k]
    return n
def edge(kind, frm, to):
    return {"id": f"{kind}:{frm}->{to}", "kind": kind, "from": frm, "to": to, "summary": f"{frm}->{to}"}

def write_graph(nodes, edges):
    g = {"schemaVersion": 1, "workspaceRoot": "/ws", "nodes": nodes, "edges": edges}
    fd, path = tempfile.mkstemp(suffix=".json"); os.write(fd, json.dumps(g).encode()); os.close(fd)
    return path

def run(graph_path, requests):
    """Send each request dict as one JSON line; return parsed response lines."""
    payload = "".join(json.dumps(r) + "\n" for r in requests)
    p = subprocess.run([BIN, "--sourcegraph-mcp", graph_path],
                       input=payload, capture_output=True, text=True, timeout=30)
    out = []
    for line in p.stdout.splitlines():
        line = line.strip()
        if line:
            try: out.append(json.loads(line))
            except json.JSONDecodeError: failures.append(f"non-JSON stdout: {line[:80]}")
    return out

# ---- Fixture graph ----
NODES = [
    node("module:.", "module", "root", path="."),
    node("file:a", "file", "a.swift", path="a.swift", language="swift"),
    node("file:b", "file", "b.swift", path="b.swift", language="swift"),
    node("file:c", "file", "c.py", path="c.py", language="python"),
    node("sym:Foo", "type", "Foo", path="a.swift", summary="type Foo in a.swift"),
    node("sym:bar", "function", "bar", path="b.swift", summary="function bar in b.swift"),
]
EDGES = [
    edge("contains", "module:.", "file:a"), edge("contains", "module:.", "file:b"),
    edge("contains", "module:.", "file:c"), edge("contains", "file:a", "sym:Foo"),
    edge("contains", "file:b", "sym:bar"), edge("references", "file:a", "file:b"),
]
G = write_graph(NODES, EDGES)
EMPTY = write_graph([], [])

def call(graph, tool, args, rid=1):
    reqs = [{"jsonrpc":"2.0","id":rid,"method":"tools/call","params":{"name":tool,"arguments":args}}]
    resp = run(graph, reqs)
    return resp[0] if resp else None

def tool_json(resp):
    """Extract the JSON payload from a tools/call text result."""
    try: return json.loads(resp["result"]["content"][0]["text"])
    except Exception: return None

# ---- 1. Handshake ----
r = run(G, [{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}])
check("initialize returns result", r and "result" in r[0])
check("initialize protocolVersion", r and r[0]["result"].get("protocolVersion") == "2024-11-05")
check("initialize serverInfo name", r and r[0]["result"]["serverInfo"]["name"] == "sourcegraph")

r = run(G, [{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}])
tools = {t["name"] for t in r[0]["result"]["tools"]} if r else set()
expected = {"knowledge_stats","core_concepts","query_knowledge","get_node","peek",
            "get_neighbors","get_collection","shortest_path"}
check("tools/list returns all 8 tools", tools == expected)
check("each tool has inputSchema", r and all("inputSchema" in t for t in r[0]["result"]["tools"]))

# ---- 2. knowledge_stats ----
s = tool_json(call(G, "knowledge_stats", {}))
check("stats nodes=6", s and s["nodes"] == 6)
check("stats edges=6", s and s["edges"] == 6)
check("stats files=3", s and s["files"] == 3)
check("stats symbols=2", s and s["symbols"] == 2)
check("stats languages swift top", s and s["languages"][0]["name"] == "swift" and s["languages"][0]["count"] == 2)

# ---- 3. core_concepts ----
c = tool_json(call(G, "core_concepts", {"limit": 3}))
check("core_concepts limited to 3", c and len(c) == 3)
check("core_concepts ranked by score desc", c and all(c[i]["score"] >= c[i+1]["score"] for i in range(len(c)-1)))

# ---- 4. query_knowledge ----
q = tool_json(call(G, "query_knowledge", {"query": "Foo", "limit": 10}))
check("query Foo finds Foo first", q and q[0]["name"] == "Foo")
qe = tool_json(call(G, "query_knowledge", {"query": "zzz_none", "limit": 10}))
check("query no-match → []", qe == [])
qb = tool_json(call(G, "query_knowledge", {"query": "", "limit": 10}))
check("query empty → []", qb == [])

# ---- 5. get_node / peek ----
gn = tool_json(call(G, "get_node", {"id": "file:a"}))
check("get_node existing", gn and gn["id"] == "file:a")
gnm = call(G, "get_node", {"id": "nope"})
check("get_node missing → null text", gnm and gnm["result"]["content"][0]["text"] == "null")
pk = tool_json(call(G, "peek", {"id": "module:."}))
check("peek score = degree(3)", pk and pk["score"] == 3)

# ---- 6. get_neighbors ----
nb = tool_json(call(G, "get_neighbors", {"id": "file:a", "direction": "out"}))
check("neighbors out of file:a", nb and {x["node"]["id"] for x in nb} == {"sym:Foo","file:b"})
nbi = tool_json(call(G, "get_neighbors", {"id": "file:a", "direction": "in"}))
check("neighbors in of file:a is module", nbi and [x["node"]["id"] for x in nbi] == ["module:."])
nbm = tool_json(call(G, "get_neighbors", {"id": "nope"}))
check("neighbors missing → []", nbm == [])

# ---- 7. get_collection ----
col = tool_json(call(G, "get_collection", {"kind": "file"}))
check("collection file count 3", col and len(col) == 3)
colp = tool_json(call(G, "get_collection", {"kind": "file", "limit": 1, "offset": 1}))
check("collection pagination", colp and len(colp) == 1)
cols = tool_json(call(G, "get_collection", {"kind": "symbols"}))
check("collection symbols alias = 2", cols and len(cols) == 2)

# ---- 8. shortest_path ----
sp = tool_json(call(G, "shortest_path", {"from": "module:.", "to": "sym:Foo"}))
check("path module→sym:Foo 3 nodes", sp and len(sp["nodes"]) == 3)
spn = call(G, "shortest_path", {"from": "file:c", "to": "sym:Foo"})
# file:c connects only to module:. which connects to file:a→sym:Foo, so a path EXISTS (undirected)
spnj = tool_json(spn)
check("path file:c→sym:Foo exists (undirected)", spnj and len(spnj["nodes"]) >= 1)
sp_self = tool_json(call(G, "shortest_path", {"from": "file:a", "to": "file:a"}))
check("path self = 1 node", sp_self and len(sp_self["nodes"]) == 1)

# ---- 9. Empty graph ----
es = tool_json(call(EMPTY, "knowledge_stats", {}))
check("empty graph stats all 0", es and es["nodes"]==0 and es["edges"]==0)
ec = tool_json(call(EMPTY, "core_concepts", {"limit": 5}))
check("empty graph core_concepts []", ec == [])

# ---- 10. Protocol error handling ----
# unknown method
um = run(G, [{"jsonrpc":"2.0","id":9,"method":"no_such_method","params":{}}])
check("unknown method → -32601", um and um[0].get("error",{}).get("code") == -32601)
# unknown tool
ut = call(G, "no_such_tool", {})
check("unknown tool → error code -32602", ut and ut.get("error",{}).get("code") == -32602)
# missing required arg (query_knowledge needs 'query')
mr = call(G, "query_knowledge", {"limit": 5})
check("missing required arg → isError result", mr and mr.get("result",{}).get("isError") == True)
# malformed JSON line → parse error with null id
mf = run(G, [])  # send a raw bad line manually below instead
p = subprocess.run([BIN, "--sourcegraph-mcp", G], input="{not json}\n",
                   capture_output=True, text=True, timeout=30)
mlines = [json.loads(l) for l in p.stdout.splitlines() if l.strip()]
check("malformed line → parse error -32700", mlines and mlines[0].get("error",{}).get("code") == -32700)
# notification (no id) → no response
p2 = subprocess.run([BIN, "--sourcegraph-mcp", G],
                    input=json.dumps({"jsonrpc":"2.0","method":"initialize","params":{}})+"\n",
                    capture_output=True, text=True, timeout=30)
check("notification (no id) → no response", p2.stdout.strip() == "")
# missing argument to --sourcegraph-mcp handled (no path) → nonzero exit, stderr msg
p3 = subprocess.run([BIN, "--sourcegraph-mcp"], capture_output=True, text=True, timeout=30)
check("missing graph arg → nonzero exit", p3.returncode != 0)

# ---- 11. Determinism: same request twice = identical bytes ----
a1 = call(G, "core_concepts", {"limit": 10})["result"]["content"][0]["text"]
a2 = call(G, "core_concepts", {"limit": 10})["result"]["content"][0]["text"]
check("MCP output deterministic", a1 == a2)

# ---- 12. No stderr noise on the happy path ----
p4 = subprocess.run([BIN, "--sourcegraph-mcp", G],
                    input=json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}})+"\n",
                    capture_output=True, text=True, timeout=30)
check("clean run has empty stderr", p4.stderr.strip() == "")

print(f"MCP protocol tests: {passed} passed, {failed} failed")
for f in failures: print("  FAIL:", f)
sys.exit(0 if failed == 0 else 1)
