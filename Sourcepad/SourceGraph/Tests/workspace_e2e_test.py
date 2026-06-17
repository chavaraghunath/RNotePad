import json, subprocess, sys, os
BIN = os.path.abspath("Sourcepad/dist/Sourcepad.app/Contents/MacOS/Sourcepad")
import os
WS = os.environ.get("SOURCEPAD_TEST_WORKSPACE", "/Users/raghunath/code/career-ops")
passed=failed=0; fails=[]
def check(n,c):
    global passed,failed
    if c: passed+=1
    else: failed+=1; fails.append(n)
def call(tool,args):
    req=json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":tool,"arguments":args}})+"\n"
    p=subprocess.run([BIN,"--sourcegraph-mcp",WS],input=req,capture_output=True,text=True,timeout=120)
    for l in p.stdout.splitlines():
        if l.strip():
            try: return json.loads(json.loads(l)["result"]["content"][0]["text"])
            except: pass
    return None
s=call("knowledge_stats",{})
check("builds graph from real index (nodes>0)", s and s["nodes"]>0)
check("has files", s and s["files"]>0)
check("has languages", s and len(s.get("languages",[]))>0)
print("  career-ops stats:", {k:s.get(k) for k in ("nodes","edges","files","symbols")} if s else None)
print("  top languages:", [(l["name"],l["count"]) for l in (s["languages"][:5] if s else [])])
c=call("core_concepts",{"limit":5})
check("core_concepts non-empty on real data", c and len(c)>0)
q=call("query_knowledge",{"query":"agents","limit":10})
check("query returns ranked results on real data", q is not None and len(q)>0)
print("  query 'agents' top:", [r["name"] for r in (q[:5] if q else [])])
col=call("get_collection",{"kind":"file","limit":5})
check("get_collection file on real data", col and len(col)>0)
print(f"Tier 3 (real workspace) tests: {passed} passed, {failed} failed")
for f in fails: print("  FAIL:",f)
sys.exit(0 if failed==0 else 1)
