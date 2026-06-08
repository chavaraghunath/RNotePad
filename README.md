# Sourcepad

Native macOS code editor. Scintilla engine, AppKit/Swift shell. MIT.

## Status

Phase 0 + Phase 1 vertical slice — usable as a daily-driver text editor for ~150+ languages with automatic light/dark theme adaptation.

## Features

- Native macOS app (Apple Silicon, macOS 13+)
- Opens any text file via `File → Open…`, drag-drop, or `open` from terminal
- Syntax highlighting for ~150 languages, auto-selected by file extension
- Light/dark theme follows the system, with manual override under `View → Theme`
- Native macOS document tabs (`Window → Merge All Windows`)
- Standard macOS undo/redo, cut/copy/paste, save/save-as
- Dirty marker in the close box; reverts and unsaved-changes prompts

## Build & run

Requires Xcode 16+ (or any Xcode that ships an arm64 macOS SDK).

```bash
./Sourcepad/Build/build.sh
open Sourcepad/build/Sourcepad.app
```

The script builds Scintilla + Lexilla via `xcodebuild`, compiles the Obj-C++ bridge with `clang++`, compiles Swift sources with `swiftc`, then assembles a code-signed (ad-hoc) `.app` bundle in `Sourcepad/build/`.

## Architecture

| Layer | Implementation |
|---|---|
| Editor engine | [Scintilla](https://www.scintilla.org/) (vendored at `scintilla/`) |
| Syntax highlighting | [Lexilla](https://www.scintilla.org/Lexilla.html) (vendored at `lexilla/`) |
| Regex backend | Boost.Regex (vendored at `boostregex/`) |
| App shell | AppKit + Swift (`Sourcepad/`) |
| Swift ↔ Scintilla bridge | Obj-C++ shim (`Sourcepad/Bridge/`) |

The editor engine is the same one that powers Notepad++ on Windows. It's been cross-platform from day one — Scintilla ships a Cocoa backend (`scintilla/cocoa/`). Sourcepad reuses that, and writes everything else fresh under MIT.

## License

[MIT](LICENSE). Vendored Scintilla/Lexilla/Boost.Regex keep their own permissive licenses (all MIT-compatible). Sourcepad does **not** derive from Notepad++'s GPL-licensed code.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
