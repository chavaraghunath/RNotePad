# Agentic CLI Knowledge Base

Research notes for Sourcepad's **Agent conversation** feature: an in-app chat that
drives an external agentic coding CLI as a subprocess. The agent can read/write
files and run commands in the workspace. The user can switch CLI + model
mid-conversation and continue.

> Scope note: this is **separate** from `Sourcepad/AI/` (the strictly-local MLX
> backend used for inline ghost-text, ⌘K rewrite, AI commit, etc.). Those never
> touch the cloud. The Agent feature *does* — it shells out to the user's own
> already-authenticated CLIs.

Probed on: **macOS arm64, 2026-06-15**. Re-run the probe commands below when a CLI
updates; versions and flags move fast.

---

## TL;DR — what's installed here & how usable

| CLI | Version | Non-interactive mode | Streaming JSON | Resume/session | List models | Verdict |
|-----|---------|----------------------|----------------|----------------|-------------|---------|
| **claude** (Claude Code) | 2.1.153 | `claude -p` | ✅ `--output-format stream-json` (+ `--input-format stream-json` = bidirectional) | ✅ `--resume <id>` / `--session-id <uuid>` | ➖ no subcommand; pass `--model opus\|sonnet\|haiku\|<id>` | **Tier 1 — best embed surface** |
| **codex** (Codex CLI) | 0.139.0 | `codex exec` | ✅ `codex exec --json` (JSONL events) | ✅ `codex exec resume <id>` / `--last` | ➖ pass `-m <model>`; `codex features list` for flags | **Tier 1** |
| **opencode** | 1.17.4 | `opencode run` | ✅ `opencode run --format json` | ✅ `--session <id>` / `--continue` / `--fork`; `opencode export <id>` | ✅ `opencode models` | **Tier 1 — richest API (also `serve`/`acp`)** |
| **cursor-agent** | 2026.06.04 | (broken here) | ? | ? | ? | **Tier 3 — currently dumps bundled JS on `--help`/`--version` in this env; defer until reliable** |

All three Tier-1 CLIs share the same embed-friendly shape: **one-shot exec per
turn, stream JSON events to stdout, resume by session id for continuity.**

---

## Probe commands (re-run to refresh this doc)

```bash
for c in claude codex opencode cursor-agent aider gemini goose; do command -v "$c"; done
claude --version; claude --help
codex --version; codex --help; codex exec --help; codex features list
opencode --version; opencode --help; opencode run --help; opencode models
cursor-agent --version            # currently errors (see Gotchas)
```

---

## 1. claude (Claude Code) — Tier 1

- **Binary:** `/opt/homebrew/bin/claude` · **Version:** 2.1.153
- **One-shot:** `claude -p "<prompt>"` (`-p`/`--print` = print response and exit).
- **Streaming:** `--output-format stream-json` emits newline-delimited JSON events
  (init, assistant text deltas, tool_use, tool_result, result). Add
  `--include-partial-messages` for token-level deltas. `--verbose` for full event
  detail.
- **Bidirectional (best for a long-lived chat):**
  `claude -p --input-format stream-json --output-format stream-json --include-partial-messages`
  — keep the process alive and write JSON user-message objects to stdin; read JSON
  events from stdout. One process can serve a whole multi-turn conversation.
- **Continuity:** `-c/--continue` (most recent in cwd), `-r/--resume <session-id>`,
  `--session-id <uuid>` (pin a session id we generate), `--fork-session`.
- **Model:** `--model <opus|sonnet|haiku|full-model-id>`,
  `--fallback-model <m>` (only with `--print`), `--effort low|medium|high|xhigh|max`.
- **Permissions / file CRUD:**
  - Default: tool-use requires permission. With bidirectional stream-json, permission
    requests surface as events we can render as approve/deny UI (best UX).
  - `--allowedTools "Edit Bash(git *)"` / `--disallowedTools ...` to scope.
  - `--dangerously-skip-permissions` (a.k.a. yolo) — no prompts. Use only with
    explicit user opt-in.
  - `--add-dir <dirs...>` to widen tool file access beyond cwd.
- **Other useful:** `--agent <name>`, `--agents <json>` (custom agents),
  `--append-system-prompt`, `--mcp-config`, `--bare` (minimal mode),
  `--settings <json>`.
- **No `list-models` subcommand.** Model set is known/curated; we pass aliases.
  Discover availability indirectly (auth state, config) or ship a curated list.

## 2. codex (Codex CLI) — Tier 1

- **Binary:** `/opt/homebrew/bin/codex` · **Version:** 0.139.0 (Rust)
- **One-shot:** `codex exec [OPTIONS] [PROMPT]` (alias `codex e`). Prompt via arg or
  stdin (`-` or piped). `codex exec resume <id>` / `codex exec resume --last`.
- **Streaming:** `codex exec --json` → JSONL events on stdout.
  `--output-schema <file>` to constrain the final response shape;
  `--output-last-message <file>` to capture the final message.
- **Model:** `-m/--model <model>`; `--oss` + `--local-provider lmstudio|ollama` for
  local models; `-c model="o3"` style config overrides; profiles via `-p <profile>`.
- **Permissions / sandbox (granular — good for safety UX):**
  - `-s/--sandbox read-only | workspace-write | danger-full-access`
  - approval policy `-c approval_policy=...` (`untrusted`/`on-request`/`on-failure`/`never`)
  - `--dangerously-bypass-approvals-and-sandbox` (full yolo)
  - `-C/--cd <dir>` working root; `--add-dir <dir>` extra writable dirs.
- **Other surfaces worth knowing:**
  - `codex mcp-server` — run Codex itself as an MCP server (stdio).
  - `codex app-server` / `remote-control` — experimental persistent server.
  - `codex review` — non-interactive code review.
  - `codex apply` — apply the last agent diff as `git apply`.
  - `codex fork` / `archive` / `unarchive` session management.
  - `codex features list` — feature flags (closest thing to capability discovery).
- **Config home:** `~/.codex/` (`config.toml`, `auth.json` → already authenticated here).

## 3. opencode — Tier 1 (richest programmatic surface)

- **Binary:** `/opt/homebrew/bin/opencode` · **Version:** 1.17.4 (Node)
- **One-shot:** `opencode run [message..] --format default|json` (`json` = raw JSON
  events). `--agent <name>`, `--command <name>`, `--share`.
- **Continuity:** `-c/--continue`, `-s/--session <id>`, `--fork`.
  `opencode session` (manage), `opencode export <id>` (conversation → JSON),
  `opencode import <file>`.
- **Model:** `-m/--model provider/model` (e.g. `anthropic/claude-...`).
- **Model discovery:** ✅ **`opencode models [provider]`** lists available models.
  *Output depends on which providers are authenticated.* Here, only the built-in
  `opencode` provider is logged in → 5 free models:
  `opencode/big-pickle`, `opencode/deepseek-v4-flash-free`, `opencode/mimo-v2.5-free`,
  `opencode/nemotron-3-ultra-free`, `opencode/north-mini-code-free`. Authenticating
  more providers (`opencode auth`/`providers`) expands this list dramatically.
- **Long-lived servers (alternative to exec-per-turn):**
  - `opencode serve` — headless HTTP server (REST + SSE); `--port`, `--hostname`.
  - `opencode acp` — **Agent Client Protocol** server (an emerging standard for
    editor↔agent integration; worth tracking as the "right" long-term protocol).
  - `opencode attach <url>` — attach to a running server.
- **Providers/auth:** `opencode providers` (alias `auth`). Config in
  `~/.config/opencode/opencode.jsonc`.

## 4. cursor-agent — Tier 3 (deferred)

- **Binary:** `/opt/homebrew/bin/cursor-agent` → Cursor CLI cask `2026.06.04`.
- **Status in this environment:** `cursor-agent --help` / `--version` **crash and
  dump ~15 MB of bundled minified JS** (error at `dist-package/index.js:8`), even
  through a PTY (`script`). Likely a Node/runtime mismatch in the cask build.
- **Action:** do not integrate until it runs cleanly. Keep the adapter interface
  generic so cursor-agent slots in later if/when fixed. Re-probe on cask updates.

---

## Other agentic CLIs to consider (not installed here)

Worth supporting via the same adapter pattern if the user installs them:

- **aider** (`aider`) — Python; `--message`/`--yes`; strong git-diff workflow.
- **gemini** (Google Gemini CLI) — `gemini -p`, JSON output.
- **goose** (Block) — `goose run`/`goose session`; recipe-based.
- **amp** (Sourcegraph) — `amp -x` non-interactive.
- **q** (Amazon Q Developer CLI) — `q chat`.
- **llm** (Simon Willison) — generic multi-provider one-shot; not agentic (no file
  CRUD) but a useful fallback for plain Q&A.
- **ollama** — local models; not agentic on its own but a model source for codex
  `--oss`/opencode.

---

## Design implications for Sourcepad

1. **Common embed pattern = exec-per-turn + stream-json + resume-by-id.** All three
   Tier-1 CLIs fit one adapter interface:
   `sendTurn(prompt, model, sessionId?) -> AsyncStream<AgentEvent>` where the adapter
   knows how to (a) build argv, (b) parse that CLI's JSON event schema into a common
   `AgentEvent` enum (text delta, tool-call, tool-result, permission-request, usage,
   done/error), (c) extract+persist the native session id for resume.

2. **Discovery on launch.** Probe `command -v` for each known CLI; for model lists,
   call the CLI's own command (`opencode models`; curated list for claude; config for
   codex). Cache results. Degrade gracefully when a CLI is missing or, like
   cursor-agent here, misbehaves — never block app launch on a CLI probe.

3. **Cross-CLI continuity is OURS to own.** Native resume only works *within one CLI*
   (a claude session id means nothing to codex). To "switch CLI/model and continue,"
   Sourcepad must keep a canonical transcript and, on switch, seed the new CLI's fresh
   session with prior context. Within one CLI, prefer native resume for fidelity.

4. **Safety is a first-class UX decision.** These agents write files and run shell
   commands. Each CLI exposes both an approval-prompt mode (surface as in-app
   approve/deny) and a yolo/skip mode. Default should be safe; yolo only on explicit
   opt-in. codex's `--sandbox` and claude's `--allowedTools` give granular control.

5. **Edits hit disk directly.** Unlike an API chat, these CLIs modify files on disk.
   Sourcepad already has on-disk-change detection ("File changed on disk") and the
   workspace indexer — the Agent panel should integrate with those to reload/diff
   touched files rather than reinvent an edit-application layer.

---

## Phase 0 spike results (verified 2026-06-15, live calls)

All three Tier-1 CLIs drove successfully from a subprocess in a temp dir.

**claude** `-p --output-format stream-json --verbose`:
- Event stream: `{type:system,subtype:init}` (carries `session_id`, `model`,
  `tools`, `permissionMode`, `cwd`) → `rate_limit_event` → `assistant` messages with
  content blocks (`thinking` w/ signature, `text`, `tool_use`) → `user`/`tool_result`
  → `{type:result,subtype:success,is_error,result,...}`. Per-message `usage` tokens.
- **Resume verified**: `--resume <session_id>` recalled prior context exactly.
- **Approval finding (decisive):** in one-shot `-p` mode the agent **auto-executes**
  tools (asked it to write a file under `--permission-mode default` → file created, no
  gate). Interactive approve/deny therefore needs the **bidirectional persistent**
  mode: `claude -p --input-format stream-json --output-format stream-json`, where the
  CLI emits a `control_request`/`can_use_tool` and the host writes a `control_response`
  allow/deny to stdin (Claude Agent SDK control protocol). Thinking blocks stream too —
  render them collapsed.

**codex** `exec --json --skip-git-repo-check --sandbox read-only -C <dir>`:
- Event stream: `{type:thread.started, thread_id}` → `turn.started` →
  `{type:item.completed, item:{type:agent_message|command_execution|file_change|reasoning, ...}}`
  → `{type:turn.completed, usage}`.
- **Resume**: `codex exec resume <thread_id>`. Needs a trusted/git dir or
  `--skip-git-repo-check`; close stdin (`</dev/null`) or it waits for piped input.
- **Approval**: coarse via `--sandbox read-only|workspace-write|danger-full-access` +
  `approval_policy`. Mid-turn per-action approval needs `codex app-server` (experimental).

**opencode** `run --format json -m <provider/model>`:
- Event stream: `{type:step_start, sessionID, part}` → `{type:text, part:{text,...}}`
  (incl. tool parts) → `{type:step_finish, part:{tokens, cost}}`. Every event carries
  `sessionID` (`ses_...`).
- **Resume**: `--session <ses_...>` / `--continue`. `opencode export <id>` → full JSON.
- **Approval**: cleanest via `opencode acp` (Agent Client Protocol — built for
  editor↔agent permission flows).

**Architecture conclusion:** the normalized `AgentEvent` model holds (`sessionStarted`,
`textDelta`, `thinking`, `toolCall`, `toolResult`, `permissionRequest`, `usage`,
`turnFinished`, `error`).

**Transport = one-shot exec per turn** (NOT a persistent bidirectional process).
Verified follow-up: even `claude -p --input-format stream-json --output-format stream-json
--permission-mode default` **auto-executes** tools headlessly — it emits NO
`control_request`; the Write just ran. So the persistent bidirectional process buys
nothing for approval, and one-shot exec already gives streaming + resume + usage. Switching
CLI/model between turns is then trivially a new process.

**Approval mechanism — Phase 3 spike result (DEFINITIVE):** the `--permission-prompt-tool`
path does **NOT** work for headless `claude -p`. Verified by hosting a real stdio MCP
server and registering it as the permission tool: claude completes the MCP handshake
(`initialize` → `notifications/initialized` → `tools/list`) but **never calls the approve
tool**, and executes the Write unconditionally. This holds with `--permission-mode default`
AND `--strict-mcp-config` (to exclude the user's 8 global MCP servers, which otherwise
pollute and destabilize the run). Root cause: `-p` mode reports `permissionMode:
bypassPermissions` and bypasses per-action prompting entirely. The only headless controls
are `--permission-mode plan` (proposes, makes NO edits) vs execute-everything. True
mid-turn per-action approval would require the Agent-SDK bidirectional control protocol
(`can_use_tool` after a `control_request: initialize` handshake), which is undocumented at
the CLI layer and out of scope.

**Chosen approval model (reliable, CLI-agnostic):** *Plan vs Auto*, with full tool-call
visibility.
- **Ask/Plan (default):** claude `--permission-mode plan` · codex `--sandbox read-only` ·
  opencode read-only. The agent reads + reasons + **proposes** edits/commands, which the
  panel renders as tool-call cards. Nothing touches disk → the user reviews and approves by
  switching to Auto / "apply".
- **Auto:** full access; the agent edits/runs; every tool call still renders as a card, and
  on-disk edits flow through the existing `Document/ExternalChangeWatcher` reload path.
This honors the user's "approve/deny" intent as closely as the headless tools reliably
allow: you see exactly what the agent wants to do before letting it act.

---

## Persistence — SQLite + brute-force vector

- **SQLite is already linked** (`-lsqlite3` in `Build/build.sh`) and used via the raw
  C API in `Workspace/ProjectIndex.swift` and `Views/SQLiteBrowserContent.swift`.
  Mirror `ProjectIndex.swift` for the agent store (open/migrate/prepare/step pattern).
- **Single DB** at the app-support dir, e.g. `agent.db`. Tables:
  - `conversation(id, title, created_at, updated_at, current_cli, current_model)`
  - `conversation_session(conversation_id, cli, native_session_id)` — per-CLI resume ids
  - `message(id, conversation_id, role, content_json, created_at)`
  - `tool_call(id, message_id, kind, target, payload_json, status)`
  - `conversation_vec(conversation_id, embedding BLOB, dims, embed_model)` — metadata
    for semantic recall over past conversations.
- **Vector search without an extension:** macOS system SQLite typically ships with
  `SQLITE_OMIT_LOAD_EXTENSION`, so `sqlite-vec`/`vec0` can't just be `.load`-ed.
  Store embeddings as `Float32` BLOBs and compute cosine similarity in Swift
  (brute force over N conversations is trivially fast at this scale). Keep
  `sqlite-vec` as a future drop-in if we vendor+build the extension.
- **Embeddings source:** reuse the local embedding path behind the stubbed
  `AI/AISemanticSearch` (strictly local, no cloud). Populate lazily; if no embedding
  model is available, semantic recall degrades to plain-text history search — never
  blocks saving or loading a conversation.
