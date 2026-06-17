#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Tests the Tree-sitter symbol extractor across all vendored languages by driving
# the real binary's --extract-symbols diagnostic on known sources.
import os, subprocess, sys, tempfile

BIN = os.environ.get("SOURCEPAD_BIN",
    os.path.join(os.path.dirname(__file__), "../../dist/Sourcepad.app/Contents/MacOS/Sourcepad"))
BIN = os.path.abspath(BIN)

passed = 0; failed = 0; failures = []
def check(name, cond):
    global passed, failed
    if cond: passed += 1
    else: failed += 1; failures.append(name)

def extract(ext, source):
    fd, path = tempfile.mkstemp(suffix="." + ext)
    os.write(fd, source.encode()); os.close(fd)
    out = subprocess.run([BIN, "--extract-symbols", path], capture_output=True, text=True, timeout=30).stdout
    os.unlink(path)
    syms = set()
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2: syms.add((parts[0], parts[1]))
    return syms

CASES = {
  "py":  ("class Foo:\n    def m(self): pass\ndef top(): pass\n",
          {("class","Foo"),("method","m"),("function","top")}),
  "c":   ("struct Node { int v; };\nenum Color { RED };\nint add(int a){ return a; }\n",
          {("struct","Node"),("enum","Color"),("function","add")}),
  "cpp": ("class W { public: void r(); };\nvoid W::r() {}\nstruct P { int x; };\nint main(){return 0;}\n",
          {("class","W"),("struct","P"),("function","main"),("method","W::r")}),
  "js":  ("function greet(n){return n;}\nclass A { speak(){} }\n",
          {("function","greet"),("class","A"),("method","speak")}),
  "ts":  ("interface S { area(): number; }\ntype ID = string;\nclass C implements S { area(){return 1;} }\nenum D { Up }\n",
          {("interface","S"),("type","ID"),("class","C"),("method","area"),("enum","D")}),
  "go":  ("package m\nfunc Add(a int) int { return a }\ntype P struct { X int }\nfunc (p P) Mag() int { return p.X }\n",
          {("function","Add"),("type","P"),("method","Mag")}),
  "rs":  ("struct P { x: i32 }\nenum C { R }\ntrait D { fn d(&self); }\nfn area()->i32{1}\nimpl P { fn mag(&self)->i32{self.x} }\n",
          {("struct","P"),("enum","C"),("interface","D"),("function","area"),("method","mag")}),
  "java":("public class H {\n  interface G { String hi(); }\n  public void run() {}\n}\n",
          {("class","H"),("interface","G"),("method","hi"),("method","run")}),
}

for ext, (src, expected) in CASES.items():
    got = extract(ext, src)
    missing = expected - got
    check(f"{ext}: extracts expected symbols", not missing)
    if missing: failures[-1] += f"  missing={missing} got={got}"

# Unsupported language returns gracefully (no grammar)
out = subprocess.run([BIN, "--extract-symbols", "/tmp/x.unknownext"], capture_output=True, text=True, timeout=30)
check("unsupported extension handled gracefully", out.returncode == 0)

print(f"Symbol extraction tests: {passed} passed, {failed} failed")
for f in failures: print("  FAIL:", f)
sys.exit(0 if failed == 0 else 1)
