# Sourcepad — Operations Guide

The authoritative reference for **how Sourcepad is built, tested, and shipped**.
Follow this exactly. Its companion, [DESIGN.md](DESIGN.md), covers architecture
and design principles.

---

## 1. The golden loop (every change)

1. **Make the change.** Match the design (DESIGN.md), match the neighboring code.
2. **Build** — `bash Sourcepad/Build/build.sh`. Must finish with
   **`** BUILD SUCCEEDED **` and 0 warnings / 0 errors.**
3. **Update the installed app** — copy the fresh bundle to
   `/Applications/Sourcepad.app` so the user's launcher runs the new build.
4. **Commit** with the correct identity (see §4) and a clear message.
5. **Push** to `main` after every build.

```bash
bash Sourcepad/Build/build.sh \
  && rm -rf /Applications/Sourcepad.app \
  && cp -R Sourcepad/dist/Sourcepad.app /Applications/Sourcepad.app
```

The bar is **perfection and correctness** — never ship a build that warns,
errors, or regresses. If tests exist for the area, run them (§5).

---

## 2. Build system

`Sourcepad/Build/build.sh` is a hand-rolled pipeline (no Xcode project for the
app, no SwiftPM):

1. Builds `Scintilla.framework` + `liblexilla.dylib` (via `xcodebuild`).
2. Compiles the Obj-C++ bridge (`clang++`).
3. Compiles the Tree-sitter C core + vendored grammars.
4. Compiles **all** Swift sources in **one whole-module `swiftc -O`** invocation,
   targeting `arm64-apple-macos13.0`.
5. Assembles `Sourcepad/dist/Sourcepad.app`, ad-hoc codesigns it, and re-registers
   it with LaunchServices.

### Source lists — explicit vs globbed (important)
- **Auto-globbed** (drop a new `.swift` in and it's compiled, no build.sh edit):
  `Agent/`, `Terminal/`, `SourceGraph/` (excluding `Tests/`),
  `ThirdParty/SwiftTerm/`.
- **Explicit lists** (you MUST add the new file's path to `build.sh`):
  `App/`, `Editor/`, `Document/`, `Workspace/`, `Palette/`, `Search/`, `Views/`,
  `Languages/TreeSitter/`, and the rest.
- Tip: when a class would otherwise need a new file in an explicit dir, consider
  adding it to an existing file there to avoid a build.sh edit — but prefer
  clarity; edit build.sh when a new file is the right call.

### Build output locations
- App bundle: `Sourcepad/dist/Sourcepad.app`
- Intermediate objects: `Sourcepad/dist/DerivedData/`, `Sourcepad/build/` (do not
  commit; they're gitignored / transient).

---

## 3. Diagnostic / headless flags

The binary exposes hidden flags (see `Sourcepad/App/main.swift`) for scripting and
tests — they run without the GUI:

```bash
APP=Sourcepad/dist/Sourcepad.app/Contents/MacOS/Sourcepad
"$APP" --reindex <folder>          # headless full index pass; prints files=… symbols=…
"$APP" --extract-symbols <file>    # print Tree-sitter symbols (kind, name, line:col)
"$APP" --mcp-preview [root]        # show the MCP merge each CLI WOULD receive (no writes)
"$APP" --sourcegraph-mcp <root>    # run the SourceGraph MCP server on stdio
```

Use `--mcp-preview` to verify MCP sync non-destructively, and `--extract-symbols`
to validate grammar/extractor changes against known sources.

---

## 4. Git identity & commits (strict)

- **Author/committer MUST be:**
  `Raghunath Chava <258775071+chavaraghunath@users.noreply.github.com>`
- **NEVER** add a `Co-Authored-By: Claude` (or any Claude) trailer.
- **NEVER** use `raghunath.chava@gmail.com` — it links to the wrong GitHub
  account. Always the `258775071+chavaraghunath@users.noreply.github.com` no-reply
  address.

```bash
git -c user.name='Raghunath Chava' \
    -c user.email='258775071+chavaraghunath@users.noreply.github.com' \
    commit -m "type(scope): summary

Body explaining the why."
git push origin main
```

- Commit message style: `type(scope): imperative summary`, then a body that
  explains the problem and the fix (Conventional-Commits-ish). Reference files by
  path when useful.
- Commit/push only the work for the task at hand; keep the tree clean.

### Concurrent agents (be careful)
More than one agent may operate in this repo at once. Symptoms:
- `swiftc` aborts with **"input file modified during build"** (a file changed
  mid-compile) → just **rebuild**; it clears once edits settle.
- `git commit` reports **"nothing to commit"** because another agent already
  committed your working-tree files.
Before committing, run `git status` + `git log --oneline -5`. If your work is
already committed by another agent, **verify the author identity and that HEAD
builds**, then continue — don't duplicate the commit.

---

## 5. Tests

- **SourceGraph** has a real suite: `Sourcepad/SourceGraph/Tests/run-all.sh`
  (Swift unit tests + Python MCP/protocol/symbol/e2e tiers — ~119 assertions).
  Run it after touching indexing, symbols, the MCP server, or sync.
- **Symbol extraction** per-language: `symbol_extraction_test.py` drives the real
  binary's `--extract-symbols` across all vendored grammars.
- Prove behavior on real inputs (a fixture repo, `--reindex` on a known folder),
  not just unit asserts. "We cannot ship untested product."

---

## 6. Independent expert review (codex)

For deep reviews / gap-finding, engage an independent **codex `gpt-5.5`** agent.
Run it with **full access — no sandbox — and no timeout**:

```bash
codex exec -m gpt-5.5 \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check -C <dir>
```

Feed the prompt on stdin, run it in the background, and act on every real finding
(fix P1s before proceeding). Pause your own edits/builds while a concurrent codex
pass runs, to avoid "modified during build" collisions.

---

## 7. Release / distribution

- Build is **arm64-only, macOS 13+, ad-hoc signed**.
- **Notarization is blocked**: the machine has **0 codesigning identities**
  (`security find-identity -v -p codesigning`). Notarizing needs a paid Apple
  Developer ID Application certificate. Until then, releases ship ad-hoc and users
  right-click → Open (or `xattr -dr com.apple.quarantine /Applications/Sourcepad.app`).
- Package + publish a release:

```bash
ditto -c -k --sequesterRsrc --keepParent Sourcepad/dist/Sourcepad.app /tmp/Sourcepad-X.Y.Z-macOS-arm64.zip
git -c user.name='Raghunath Chava' \
    -c user.email='258775071+chavaraghunath@users.noreply.github.com' \
    tag vX.Y.Z
git push origin vX.Y.Z
gh release create vX.Y.Z /tmp/Sourcepad-X.Y.Z-macOS-arm64.zip \
  --title "Sourcepad vX.Y.Z" --notes-file <notes> --latest
```

When a Developer ID is available, add: `codesign` with the Developer ID →
`notarytool submit --wait` → `stapler staple` for a Gatekeeper-clean build.

---

## 8. Common gotchas

- **Finder-launched PATH is minimal.** Resolve CLIs with
  `AgentExecutable.locate`; spawn with `AgentProcessRunner.inheritedEnvironment()`
  or a login shell (`-lc`). Don't assume `/opt/homebrew/bin` is on PATH.
- **`Hasher` is process-seeded.** Never use it for an on-disk change gate — use a
  deterministic hash (FNV-1a). A seeded hash refires the whole index every launch.
- **Layer color baked at load.** Use `updateLayer()` + `viewDidChangeEffectiveAppearance`
  for appearance-correct fills, not a one-shot `layer.backgroundColor`.
- **Sheets need a window.** Present via `presentAsSheet` / `beginSheetModal(for:
  view.window)` so it works standalone and inside Settings.
- **Drain subprocess output through EOF** before declaring completion, or you drop
  the last progress line.
- **Don't block app launch** on any probe (CLI availability, model lists,
  package-manager detection) — do it off the main thread and update the UI when it
  lands.
- **brew/npm headless** need non-interactive env (`NONINTERACTIVE=1`,
  `HOMEBREW_NO_AUTO_UPDATE=1`, `CI=1`) or they hang/prompt. `CLIInstaller` already
  sets these.

---

Follow the golden loop, keep the build green, commit as the right author, and
leave the tree clean. Operational discipline is part of the product's quality.
