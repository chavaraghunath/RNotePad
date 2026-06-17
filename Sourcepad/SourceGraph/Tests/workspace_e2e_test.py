#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# End-to-end: index a real multi-language fixture folder with the headless
# indexer (--reindex), then confirm files + symbols populate. Proves the full
# pipeline disk -> Tree-sitter extraction -> ProjectIndex.symbols.
import os, subprocess, sys, tempfile, shutil

BIN = os.environ.get("SOURCEPAD_BIN",
    os.path.join(os.path.dirname(__file__), "../../dist/Sourcepad.app/Contents/MacOS/Sourcepad"))
BIN = os.path.abspath(BIN)

passed = 0; failed = 0; failures = []
def check(name, cond):
    global passed, failed
    if cond: passed += 1
    else: failed += 1; failures.append(name)

FIXTURE = {
  "a.py":  "class Foo:\n    def m(self): pass\ndef top(): pass\n",
  "b.go":  "package m\nfunc Add(a int) int { return a }\ntype P struct{ X int }\n",
  "c.ts":  "interface S { area(): number }\nclass C implements S { area(){return 1} }\n",
  "d.rs":  "struct Q { x: i32 }\nfn area()->i32{1}\nimpl Q { fn mag(&self)->i32{1} }\n",
  "readme.md": "# not code, should yield no symbols\n",
}

tmp = tempfile.mkdtemp(prefix="sg_e2e_")
try:
    for name, src in FIXTURE.items():
        with open(os.path.join(tmp, name), "w") as f: f.write(src)
    out = subprocess.run([BIN, "--reindex", tmp], capture_output=True, text=True, timeout=60)
    line = next((l for l in out.stdout.splitlines() if l.startswith("files=")), "")
    nums = dict(p.split("=") for p in line.split() if "=" in p)
    files = int(nums.get("files", 0)); symbols = int(nums.get("symbols", 0))
    print(f"  fixture index: files={files} symbols={symbols}")
    check("indexes the fixture files", files >= 5)
    # Foo, m, top, Add, P, S, C, area, Q, area, mag → well above zero across 4 langs.
    check("extracts symbols across languages (>=10)", symbols >= 10)

    # Re-index is cheap + stable: unchanged files aren't re-parsed, count holds.
    out2 = subprocess.run([BIN, "--reindex", tmp], capture_output=True, text=True, timeout=60)
    line2 = next((l for l in out2.stdout.splitlines() if l.startswith("files=")), "")
    sym2 = int(dict(p.split("=") for p in line2.split() if "=" in p).get("symbols", -1))
    check("re-index is idempotent (symbol count stable)", sym2 == symbols)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# Optional: a real indexed workspace builds a SourceGraph without crashing.
ws = os.environ.get("SOURCEPAD_TEST_WORKSPACE")
if ws and os.path.isdir(ws):
    import json
    req = json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call",
                      "params":{"name":"knowledge_stats","arguments":{}}}) + "\n"
    p = subprocess.run([BIN, "--sourcegraph-mcp", ws], input=req, capture_output=True, text=True, timeout=120)
    got = [json.loads(l) for l in p.stdout.splitlines() if l.strip()]
    s = json.loads(got[0]["result"]["content"][0]["text"]) if got else {}
    check("real workspace builds a graph (nodes>0)", s.get("nodes", 0) > 0)
    print(f"  workspace stats: nodes={s.get('nodes')} files={s.get('files')} symbols={s.get('symbols')}")

print(f"Workspace e2e tests: {passed} passed, {failed} failed")
for f in failures: print("  FAIL:", f)
sys.exit(0 if failed == 0 else 1)
