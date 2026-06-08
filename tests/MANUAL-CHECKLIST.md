# Sourcepad — Adversarial Test Checklist

This file lists every check run during the Phase 1–9 implementation. Tick boxes as you verify.
Fixtures live in `tests/fixtures/`.

## Phase 1 — Scintilla quick-wins

- [ ] Zoom out 20 times then in 20 times — text always legible, never crashes
- [ ] Word wrap toggle on `tests/fixtures/large.txt` — UI stays responsive
- [ ] Open `tests/fixtures/shebang-python-noext` — Python lexer picked despite no extension
- [ ] Indent guides on `tests/fixtures/mixed-indent.py` — guides at logical indent levels
- [ ] Show Invisibles — every space/tab/EOL marked
- [ ] Brace highlight: caret between `(` `)` → both glow; mismatched brace → BAD style

## Phase 2 — Status bar

- [ ] Rapid arrow-key movement — status updates without flicker, no main-thread stall
- [ ] 10K-line file → cursor pos accurate, sub-frame update
- [ ] Click encoding cell → menu opens → switch UTF-8 ↔ UTF-16 → file reloads intact
- [ ] Empty file shows `Ln 1, Col 1` not `Ln 0, Col 0`
- [ ] Convert LF→CRLF on mixed-EOL file → every line consistent after

## Phase 3 — Multi-cursor + go-to-line + auto-pair + reopen tab

- [ ] `foo` repeated 5×, Cmd-D 5× → all `foo` selected; type `bar` → 5× replaced; undo → 5× reverted
- [ ] Multi-select + paste — pastes once per selection
- [ ] Go to line `-5` / `0` / `9999999` on 50-line file → clamps to 1 / 1 / 50
- [ ] Go to line empty input → no-op
- [ ] Auto-pair inside string literal → does NOT pair
- [ ] Type `(` then `)` immediately → exactly one `)` total
- [ ] Auto-pair insert is one undo step
- [ ] Reopen Closed Tab on cold start → menu item disabled

## Phase 4 — Edit commands

- [ ] Toggle comment on blank line → adds prefix, leaves indent
- [ ] Toggle on already-commented → uncomments
- [ ] Mixed-comment selection → normalises to all-commented
- [ ] XML lexer (no line comment) → uses block comment
- [ ] Sort 10K lines under 50 ms
- [ ] Sort preserves trailing newline at EOF
- [ ] Trim trailing whitespace preserves one EOF newline
- [ ] Trim on CRLF file preserves CR
- [ ] Bookmark in unsaved doc works; persists on save+reopen
- [ ] Convert case on `café` / `Größe` handles unicode

## Phase 5 — Code folding

- [ ] Swift/JS/Python file shows fold markers at functions/classes
- [ ] Click `+` collapses, `-` expands
- [ ] Editing inside fold adjusts on next lex
- [ ] `.txt` shows no fold margin
- [ ] Fold All on 10K-line file under 100 ms
- [ ] Save while folded → full file content saved
- [ ] Find finds text in folded block → auto-unfolds

## Phase 6 — External-change watcher

- [ ] `echo hi >> file` while open → exactly one prompt
- [ ] `rm file` → "File no longer exists" alert
- [ ] In-app save → no spurious external prompt
- [ ] `vim :w` (rename-replace) → handled as content change
- [ ] 20 mods in 100 ms → one debounced prompt
- [ ] Open + close 50 docs → FD count stays steady

## Phase 7 — Find in Files

- [ ] 100K-file tree → progress reported, cancel ≤ 100 ms
- [ ] `(a+)+b` regex on `aaaaaa…!` → per-file 1 s timeout aborts
- [ ] Symlink loop → no infinite recurse
- [ ] Binary blob `.png` → skipped silently
- [ ] Permission-denied file → logged + continue
- [ ] Click result for now-deleted file → "File not found" alert
- [ ] Folder with `.gitignore node_modules/` → those files skipped

## Phase 8 — Color schemes for 48 lexers

- [ ] Each lang sample under `tests/fixtures/lang-samples/` opens and every token type is coloured
- [ ] Light → dark theme switch flips all colours
- [ ] Switching lexer at runtime via Language menu rewrites colours

## Phase 9 — Sidebar menu + autocomplete + git gutter + outline

- [ ] Sidebar rename to existing name → error toast, no overwrite
- [ ] Sidebar delete read-only → alert, file remains
- [ ] Sidebar root set to non-existent path → empty state
- [ ] Autocomplete at 10 chars/s → no lag, no stale list
- [ ] Autocomplete on unicode word → no crash, no popup (ASCII-only by design)
- [ ] Escape during autocomplete → popup closes, text unchanged
- [ ] Git gutter: file outside repo → no markers, no error
- [ ] Git gutter: detached HEAD → markers from HEAD commit
- [ ] Git gutter on 50K-line diff → completes < 1 s
- [ ] Outline empty file → empty list, no crash
- [ ] Outline 10K-function file → virtualises (NSOutlineView native)
- [ ] Outline lexer switch mid-file → re-extracts
