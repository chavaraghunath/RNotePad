# Contributing to Rnotepad

Thanks for your interest!

## Ground rules

- **License**: Rnotepad is MIT. By contributing, you agree your contribution is offered under MIT.
- **No GPL code**: do not copy or closely translate code from GPL-licensed projects (including Notepad++). Reading them for *understanding* is fine; copying expression is not.
- **Engine code is upstream**: `scintilla/`, `lexilla/`, and `boostregex/` are vendored from their upstreams. Don't make local edits except for build-config tweaks. Submit fixes to upstream instead.

## How to set up

```bash
git clone https://github.com/chavaraghunath/Rnotepad.git
cd Rnotepad
./Rnotepad/Build/build.sh
open Rnotepad/build/Rnotepad.app
```

## Style

- **Swift**: no global state. View controllers own their state. Use `final class` unless inheritance is needed.
- **Obj-C++ bridge**: only `Rnotepad/Bridge/SciTextView.{h,mm}` may include Scintilla C++ headers. Everything else stays Swift-pure.
- **No silent failures**: if something can't be done, throw or surface a user-visible error.
- **Tests**: not required for v0; will be required when we add the test target in a later phase.

## What needs doing

See open issues. Common categories:

- New language support (extend `LexerRegistry.swift` + add a `ColorScheme` palette)
- Find/Replace UI
- Sidebar file browser
- Preferences UI
- Session save/restore
- Accessibility improvements
- Localization

## Reporting bugs

Open an issue with:
1. macOS version
2. Steps to reproduce
3. Expected vs actual behavior
4. A minimal sample file if relevant
