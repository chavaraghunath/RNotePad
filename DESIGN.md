# Sourcepad — Design Guide

The authoritative reference for **how Sourcepad is designed**. Read this before
adding a feature so new work matches the grain of the existing code. Its
companion, [OPERATIONS.md](OPERATIONS.md), covers how to build, test, and ship.

> Sourcepad is a native macOS code editor with a built-in agentic coding
> assistant. AppKit + Swift shell, Scintilla/Lexilla editor engine, Tree-sitter
> symbols, an embedded terminal, MLX for strictly-local AI, and adapters that
> drive the user's own agent CLIs (Claude Code, Codex, opencode, …).

---

## 1. First principles (non-negotiable)

1. **Perfection and correctness are non-negotiable.** No half-built features, no
   silent failures, no "good enough." If something can't be done, surface a
   clear, user-visible error — never swallow it. Every change builds with
   **0 warnings / 0 errors**.
2. **Native macOS, hand-built.** AppKit + Swift, compiled by a hand-rolled
   `swiftc` script — no Xcode project, no SwiftPM for the app, no SwiftUI. Match
   the platform's conventions (System Settings layout, SF Symbols, sheets,
   light/dark correctness).
3. **Ask before assuming.** When a requirement is ambiguous or a decision is the
   user's to make, ask — don't guess. Use the question tool for genuine forks;
   pick the obvious default and state it for the rest.
4. **Headless-testable core, thin UI.** Put logic in pure, `Foundation`-only
   types that can be exercised without a UI; keep view controllers thin. AppKit
   imports live only in files that actually draw.
5. **Never frame features as borrowed from a named competitor.** Describe what a
   feature *does*, not which product it resembles. (See [§8](#8-guardrails).)
6. **Degrade gracefully, never block launch.** Missing CLI, absent package
   manager, no model — the app stays usable and says what's missing.

---

## 2. Technology stack

| Layer | Implementation | Location |
|---|---|---|
| Editor engine | Scintilla (Cocoa backend) | `scintilla/` (vendored) |
| Syntax highlighting | Lexilla lexers | `lexilla/` (vendored) |
| Regex backend | Boost.Regex | `boostregex/` (vendored) |
| App shell | AppKit + Swift | `Sourcepad/` |
| Swift ↔ Scintilla bridge | Obj-C++ shim (the **only** file that sees Scintilla C++ headers) | `Sourcepad/Bridge/SciTextView.{h,mm}` |
| Symbols | Tree-sitter C core + vendored grammars | `tree-sitter/`, `Sourcepad/Languages/TreeSitter/` |
| Persistence | SQLite (raw C API, `-lsqlite3`) | `Sourcepad/Workspace/ProjectIndex.swift` |
| Terminal | SwiftTerm (vendored, compiled into the module) | `Sourcepad/ThirdParty/SwiftTerm/`, `Sourcepad/Terminal/` |
| Local AI | MLX (Python venv: `mlx_lm.server`, `hf`) | `Sourcepad/Agent/MLX*.swift`, `Sourcepad/AI/` |
| Agent CLIs | subprocess adapters, one-shot exec per turn | `Sourcepad/Agent/` |

Target: **arm64-apple-macos13.0**, ad-hoc signed.

---

## 3. Module map

Each directory under `Sourcepad/` owns one concern. Put new code where its
neighbors already live.

- **`App/`** — entry point (`main.swift`), `AppDelegate`, `MainMenu`, the unified
  `SettingsWindowController` + panes, `Preferences`, session restore.
- **`Editor/`** — Scintilla-backed editor: pane/window controllers, the file
  **sidebar** (`SidebarViewController`), `FindBar`, document tab bar,
  autocomplete, bookmarks.
- **`Document/`** — `TextDocument`, `DocumentController`, external-change
  watcher, git diff gutter, three-way merge.
- **`Workspace/`** — `Workspace`/`WorkspaceManager`, the SQLite `ProjectIndex`,
  `IndexerCoordinator` (FSEvents-driven background indexer), `TodoAggregator`.
- **`Languages/TreeSitter/`** — Swift wrappers (`TreeSitterParser/Tree/Node`),
  the `TreeSitterLanguage` enum, and `SymbolExtractor`.
- **`Agent/`** — the agentic assistant: `AgentCLI` protocol + `AgentRegistry`,
  per-CLI adapters, `CLISpec`/`CLIProbe` (drive any CLI from its `--help`),
  `CLICatalog`/`CLIInstaller`/`PackageManagers`/`CLIAuthStatus` (install + manage),
  the chat panel, normalized `AgentEvent`s, `AgentPolicy` (risk classifier), MLX.
- **`Terminal/`** — embedded PTY terminal (`TerminalSession`, panel, tab bar).
- **`SourceGraph/`** — the knowledge-graph **MCP server** Sourcepad exposes
  (branded "SourceGraph" in-app); `Tests/` holds its 4-tier suite.
- **`LSP/`** — language-server client + manager.
- **`Search/`** — find-in-files engine + window.
- **`Palette/`** — command/file/symbol fuzzy palettes.
- **`Views/`** — specialized content views (CSV grid, SQLite browser, image/PDF
  preview).
- **`AI/`** — strictly-local MLX features (ghost text, ⌘K rewrite, AI commit).
  **Never** touches the cloud; distinct from `Agent/`, which drives the user's
  already-authenticated CLIs.
- **`Bridge/`** — the Obj-C++ Scintilla shim. Nothing else includes Scintilla
  headers.
- **`Build/`** — `build.sh`, `Info.plist.template`.

---

## 4. Core architectural patterns

These are the load-bearing patterns. Reuse them; don't reinvent.

### 4.1 Settings = one row per pane
The unified Settings window (`SettingsWindowController`) is a sidebar split view.
Adding a pane is **one `SettingsSection` entry** in `SettingsSplitViewController.sections`
whose `make` closure vends an `NSViewController`. Simple form panes subclass
`SettingsPaneViewController` and return `(label, control)` rows; richer panes
(Agent CLIs, MLX) are full controllers. Panes are cached and reused.

### 4.2 Agent CLIs: protocol + registry + declarative specs
- `AgentCLI` is the adapter protocol: locate the executable, list models, run one
  turn. `AgentRegistry.shared` discovers installed CLIs off the main thread and
  caches availability + models (`warmUp`). **Never block launch on a probe.**
- Tier-1 CLIs (claude/codex/opencode) hand-roll their invocation + JSON parsing
  for fidelity. Everything else is driven by a **declarative `CLISpec`** (prompt
  flag, model flag, plan/auto args, output mode). `CLIProbe` builds a draft spec
  by reading a CLI's `--help` — **add a CLI with no new Swift**.
- **Transport = one-shot exec per turn**, stream JSON events to a normalized
  `AgentEvent` vocabulary (`sessionStarted`, `textDelta`, `thinking`, `toolCall`,
  `toolResult`, `usage`, `turnFinished`, `error`), resume by the CLI's native
  session id. Switching CLI/model between turns is then trivial. See
  [`Sourcepad/Agent/AGENT-CLI-KNOWLEDGE-BASE.md`](Sourcepad/Agent/AGENT-CLI-KNOWLEDGE-BASE.md).

### 4.3 Agent CLI install/manage (the catalog)
- `CLICatalog` is **pure data**: per-CLI install methods (brew/npm/pipx/script,
  in priority order), auth spec, docs URL, config dir.
- `PackageManagers` detects brew/npm/pipx; only methods whose manager is present
  are offered.
- `CLIInstaller` runs a command **headlessly through the login shell** (`-lc`)
  with streamed, line-by-line progress and cancel — same shape as
  `MLXModelManager.pull`.
- `CLIAuthStatus` is **best-effort and conservative**: it reports `.ready` only
  when it positively finds the CLI's own auth artifact, otherwise `.unknown` — it
  **never asserts "signed out."** Auth is always deferred to the CLI's own login.

### 4.4 Permission model: Plan vs Auto
Headless agent CLIs don't expose a reliable mid-turn per-action approval hook. So
the model is **Plan (read-only, proposes) vs Auto (full access, acts)**, with
every tool call rendered as a card. `AgentPolicy` is a pure risk classifier that
badges each action (allow/caution/high) for visibility + governance.

### 4.5 Indexing: SQLite + FSEvents + Tree-sitter
`IndexerCoordinator` walks a workspace, watches roots via **FSEvents**, and writes
files + symbols into the SQLite `ProjectIndex`. Symbols come from
`SymbolExtractor` (Tree-sitter). The change-gate uses a **deterministic** content
hash (FNV-1a — never a process-seeded `Hasher`, which would refire every launch).
On change, always `replaceSymbols` (clears stale rows).

### 4.6 MCP: managed-only, atomic, backed-up
Sourcepad exposes its knowledge graph as an MCP server (`SourceGraph/`) and syncs
managed servers into each CLI's config. Sync writes are **change-detected,
backed-up (`.sourcepad.bak`), atomic, and managed-only** — never clobber the
user's own MCP entries.

### 4.7 Live filesystem reflection
UI that mirrors disk watches it. The sidebar uses a `SidebarFileWatcher`
(FSEvents) and refreshes while **preserving expansion + selection**. FSEvents'
latency window coalesces bursts. The same instinct applies anywhere on-disk state
is shown.

### 4.8 Appearance-correct, layer-backed views
Light/dark must be correct. A view that sets `layer.backgroundColor` to a concrete
`CGColor` once will bake in load-time appearance. Instead drive fills through
`wantsUpdateLayer`/`updateLayer()` and invalidate on
`viewDidChangeEffectiveAppearance()`. Resolve colors at draw time. (See
`SidebarRootView`, `CLICard`.)

### 4.9 Subprocess hygiene
- GUI apps launched from Finder inherit a **minimal PATH**. Always resolve
  executables with `AgentExecutable.locate(_:)` (PATH + Homebrew/asdf/volta/bun/
  cargo roots) and spawn with `AgentProcessRunner.inheritedEnvironment()` or a
  login shell so the user's real PATH applies.
- Stream stdout/stderr through a `readabilityHandler`, **drain through EOF** with
  a semaphore before reporting completion (don't lose the final line).
- Hold a lock around any buffer a readability handler mutates.

---

## 5. UI / UX conventions

- **macOS Settings idiom** for forms: trailing-aligned labels, leading controls,
  `NSGridView` (`SettingsPaneViewController`).
- **SF Symbols** for iconography; tint with `controlAccentColor`.
- **Sheets attach to `view.window`** (`presentAsSheet` / `beginSheetModal`), so a
  controller behaves correctly whether hosted standalone or inside Settings.
- **Never let controls clip or bleed.** Pack toolbars left behind a flexible
  trailing spacer; set `clipsToBounds` where a view can collapse to zero.
- **Cards** for stateful lists (`CLICard`): icon + title + blurb + status badges +
  state-dependent action buttons, rounded, appearance-correct.
- **Progress is visible and cancellable** (`CLIProgressSheetController`): spinner +
  live monospaced log + Cancel→Done.
- **Honesty over theater.** If an action can't truly be performed headlessly (a
  TUI/OAuth login), show the exact command to run — don't pretend to drive it.

---

## 6. Data & persistence

- **SQLite** via the raw C API, mirroring `ProjectIndex.swift` (open → migrate →
  prepare → step), one serial queue per connection. Per-workspace DBs live under
  `~/Library/Application Support/Sourcepad/Workspaces/<id>.db`.
- **`Preferences`** wraps `UserDefaults` with typed accessors and posts a change
  notification; per-CLI maps (e.g. default model) are stored as dictionaries.
- **User-added CLI specs** persist as JSON (`CLISpecStore`).
- **Memory/embeddings**: store `Float32` BLOBs, brute-force cosine in Swift (macOS
  system SQLite omits loadable extensions).

---

## 7. Adding things — quick recipes

- **A settings pane** → add one `SettingsSection` row; subclass
  `SettingsPaneViewController` for a form.
- **Support a new agent CLI** → add a `CLICatalogEntry` (install/auth/docs). If it
  needs driving and isn't Tier-1, it's auto-probed into a `CLISpec` on install; or
  the user adds it via "Add custom CLI…". No new Swift for the common case.
- **A new language's symbols** → vendor its Tree-sitter grammar (ABI-14), wire an
  entry point in `tree-sitter/grammars/grammars.h`, extend `TreeSitterLanguage`
  and `SymbolExtractor`.
- **A new editor file in `Editor/`** → it is an **explicit** source list in
  `build.sh`; add the path there. Files under `Agent/`, `Terminal/`,
  `SourceGraph/`, `ThirdParty/SwiftTerm/` are auto-globbed (no build.sh edit).
  (See OPERATIONS.md §Build.)

---

## 8. Guardrails

- **No competitor-borrow framing.** Never describe a feature as taken/borrowed
  from a named product (e.g. "like VSCode's X"). Describe the capability itself.
- **No GPL code.** Reading for understanding is fine; copying expression is not.
  Engine dirs (`scintilla/`, `lexilla/`, `boostregex/`, `tree-sitter/`) are
  vendored upstream — only build-config tweaks locally.
- **Strictly-local stays local.** `AI/` (MLX) must never reach the cloud. `Agent/`
  may, but only via the user's own already-authenticated CLIs — Sourcepad stores
  no provider credentials.
- **Privacy of secrets.** Auth is the CLI's responsibility. Detect state; never
  persist keys in Sourcepad.

---

When in doubt, read the nearest existing module and match its structure, naming,
comment density, and error handling. Consistency is a feature.
