// SPDX-License-Identifier: MIT
// Sourcepad — single source of truth for Scintilla resource numbering.
//
// Scintilla has fixed-size pools of margins (5), markers (32), and indicators
// (32). Multiple features want slots in the same pool, and any conflict is a
// silent bug: two features painting the same marker number both "work" until
// the user enables both and one stomps the other. Centralising allocation
// here means a code reviewer can see at a glance whether a new feature has
// claimed an already-used slot.
//
// Rule: any file that uses a numeric margin/marker/indicator must import this
// header and refer to the symbolic name, never a bare integer. New features
// add their entries here in the same PR.

#ifndef SOURCEPAD_ALLOCATIONS_H
#define SOURCEPAD_ALLOCATIONS_H

// MARK: - Margins (Scintilla supports 0..4)

#define SPMarginLineNumber   0   // line numbers
#define SPMarginBreakpoint   1   // DAP breakpoints + bookmarks (shared symbol margin)
#define SPMarginFold         2   // code folding glyphs
#define SPMarginGitDiff      3   // git added/modified/deleted bars
#define SPMarginDiagnostic   4   // LSP diagnostic severity icons

// MARK: - Markers (Scintilla supports 0..31)
//
// 0–4   reserved for future use
// 5–7   git diff (existing — see GitDiffGutter.swift)
// 8–11  DAP breakpoints + current stack frame
// 12–15 LSP diagnostic severity icons
// 16–23 free
// 24    bookmark (existing — see Bookmarks.swift)
// 25–31 fold glyphs (existing — see SciEnableFolding)

#define SPMarkerGitAdded             5
#define SPMarkerGitModified          6
#define SPMarkerGitDeleted           7

#define SPMarkerBreakpoint           8
#define SPMarkerBreakpointDisabled   9
#define SPMarkerBreakpointConditional 10
#define SPMarkerStackFrameCurrent    11

#define SPMarkerDiagError            12
#define SPMarkerDiagWarning          13
#define SPMarkerDiagInfo             14
#define SPMarkerDiagHint             15

#define SPMarkerBookmark             24

// 25–31: fold glyphs (Scintilla's own SC_MARKNUM_FOLDER* constants land here).

// MARK: - Indicators (Scintilla supports 0..31; 8..31 are user-defined)
//
// 0–7   Scintilla / Lexilla reserved
// 8     AI ghost-text overlay (faded foreground hint)
// 9–12  LSP diagnostic squiggles by severity
// 13    LSP "highlight current symbol" (textDocument/documentHighlight)
// 14–19 bracket-pair colorisation depth levels 0..5
// 20    smart-selection scope outline
// 21    wikilink active hover
// 22    find-all matches highlight
// 23    free
// 24–31 free

#define SPIndicatorAIGhost              8

#define SPIndicatorLSPError             9
#define SPIndicatorLSPWarning          10
#define SPIndicatorLSPInfo             11
#define SPIndicatorLSPHint             12
#define SPIndicatorLSPSymbolHighlight  13

#define SPIndicatorBracketPair0        14
#define SPIndicatorBracketPair1        15
#define SPIndicatorBracketPair2        16
#define SPIndicatorBracketPair3        17
#define SPIndicatorBracketPair4        18
#define SPIndicatorBracketPair5        19

#define SPIndicatorSmartSelection      20
#define SPIndicatorWikilink            21
#define SPIndicatorFindAllMatches      22

// MARK: - Style indices (per-lexer, 0..127 user-defined)
//
// Most styles come from the active lexer (Lexilla emits SCE_*_*). The bands
// below are reserved for cross-lexer overlays the editor sets manually via
// SciSetCustomStyleUTF16 (see CSSStyler) or for view-mode markers.
//
// 70–79  CSS-in-HTML overlay (existing)
// 80–95  free (reserved for future view-mode overlays)

#define SPStyleCSSOverlayBase   70

#endif // SOURCEPAD_ALLOCATIONS_H
