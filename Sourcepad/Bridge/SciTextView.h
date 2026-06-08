// SPDX-License-Identifier: MIT
// Sourcepad — Obj-C façade over Scintilla's ScintillaView. Plain Obj-C only;
// Swift sees this header but never the C++ guts underneath.

#import <Cocoa/Cocoa.h>
#import "KeywordSetsGenerated.h"
#import "Allocations.h"

// Tree-sitter — surfaced to Swift via the bridging header.
// Repo-relative paths so the importer doesn't need -Xcc -I flags (which
// Swift's bridging-header importer resolves inconsistently across
// macOS SDK versions).
#import "../../tree-sitter/lib/include/tree_sitter/api.h"
#import "../../tree-sitter/grammars/grammars.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Notification codes (mirrored from Scintilla.h to avoid leaking C++)

// Same numeric values as Scintilla's SCN_* constants.
typedef NS_ENUM(int, SciNotification) {
    SciNotificationCharAdded         = 2001,
    SciNotificationSavePointReached  = 2002,
    SciNotificationSavePointLeft     = 2003,
    SciNotificationUpdateUI          = 2007,
    SciNotificationModified          = 2008,
    SciNotificationMarginClick       = 2010,
    SciNotificationDwellStart        = 2016,
    SciNotificationDwellEnd          = 2017,
    SciNotificationZoom              = 2018,
    SciNotificationAutoCSelection    = 2022,
    SciNotificationIndicatorClick    = 2023,
    SciNotificationIndicatorRelease  = 2024,
    SciNotificationFocusIn           = 2028,
    SciNotificationFocusOut          = 2029,
};

// Detail-dictionary keys passed to the notification handler. Not every
// notification has every key; callers should treat lookups as optional.
//
// All values are NSNumber unless noted.
//
//   "position"         byte position in the document
//   "modifiers"        Cocoa NSEventModifierFlags subset (Shift/Ctrl/Alt/Cmd)
//   "codePoint"        Unicode code point of the just-added char (CharAdded)
//   "x", "y"           pixel coordinates relative to the editor view (Dwell*)
//   "text"             NSString — selected autocompletion item (AutoCSelection)
//   "listType"         autocompletion list type (AutoCSelection)
//   "linesAdded"       net lines added (>=0) or removed (<0) (Modified)
//   "modificationType" raw SC_MOD_* flags (Modified)
//   "length"           byte length of the modified range (Modified)
//   "updated"          SC_UPDATE_* flag bitmask (UpdateUI)
//   "margin"           margin index (MarginClick)
//
// These are string constants exported for autocompletion of detail lookups.
extern NSString * const SciDetailPosition;
extern NSString * const SciDetailModifiers;
extern NSString * const SciDetailCodePoint;
extern NSString * const SciDetailX;
extern NSString * const SciDetailY;
extern NSString * const SciDetailText;
extern NSString * const SciDetailListType;
extern NSString * const SciDetailLinesAdded;
extern NSString * const SciDetailModificationType;
extern NSString * const SciDetailLength;
extern NSString * const SciDetailUpdated;
extern NSString * const SciDetailMargin;

// MARK: - View

/// Create a ScintillaView (an NSView subclass) at the given frame. Returns it
/// as a plain NSView so Swift never names the underlying class.
NSView *SciMakeView(NSRect frame);

/// Replace the entire buffer contents.
void SciSetText(NSView *view, NSString *text);

/// Read the current buffer contents.
NSString *SciGetText(NSView *view);

/// Set the editor font (e.g. "Menlo", 13).
void SciSetFont(NSView *view, NSString *name, CGFloat size);

/// Set the default editor font + size. Pair this with SciApplyPalette
/// (which propagates STYLE_DEFAULT to all token styles via STYLECLEARALL).
void SciSetEditorFont(NSView *view, NSString *fontName, CGFloat fontSize);

/// Set tab width in columns (default 8 in Scintilla; we prefer 4).
void SciSetTabWidth(NSView *view, NSInteger width);

/// When YES, Tab key inserts a hard tab; when NO, it inserts spaces.
void SciSetUseTabs(NSView *view, BOOL useTabs);

// MARK: - Lexer / styling

/// Load Lexilla, create a lexer by name (e.g. "cpp", "python"), and attach it.
/// Returns YES on success, NO if Lexilla cannot be loaded or the name is unknown.
/// Pass `nil` to detach any lexer (plain text mode).
BOOL SciApplyLexer(NSView *view, NSString * _Nullable lexerName);

/// Apply a color palette to the editor.
/// `palette[@(styleIndex)]` = NSDictionary with keys "fg", "bg" (NSColor) and "bold" (NSNumber/BOOL).
/// Pass `lineNumberFg`/`lineNumberBg` for the line-number margin (style index 33).
void SciApplyPalette(NSView *view,
                     NSDictionary<NSNumber *, NSDictionary *> *palette,
                     NSColor *defaultFg,
                     NSColor *defaultBg,
                     NSColor *lineNumberFg,
                     NSColor *lineNumberBg);

/// Configure a margin to show line numbers.
void SciShowLineNumbers(NSView *view, BOOL show);

/// Set keywords for a slot (0 = main keyword set, 1 = secondary, etc.)
void SciSetKeywords(NSView *view, int slot, NSString *spaceSeparatedKeywords);

// MARK: - Save / dirty state

/// Mark the current state as clean. Scintilla will fire SavePointLeft on the
/// next modification and SavePointReached if the user undoes back to here.
void SciSetSavePoint(NSView *view);

/// YES if the buffer has unsaved modifications relative to the last save point.
BOOL SciIsModified(NSView *view);

// MARK: - Notifications

/// Install a callback invoked on the main thread for select Scintilla events.
/// Pass `nil` to remove. Only one handler at a time per view; calling again
/// replaces the previous handler.
///
/// `detail` carries per-notification payload (see SciDetail* keys above). It
/// is nil for notifications with no useful payload.
void SciSetNotificationHandler(NSView *view,
                               void (^_Nullable handler)(SciNotification type,
                                                          NSDictionary * _Nullable detail));

// MARK: - Debug

/// Return a multi-line string describing each non-default-styled char in the
/// first `maxBytes` of the buffer. Format: "offset[style] char". Useful for
/// diagnosing what the lexer is actually emitting.
NSString *SciDumpStyles(NSView *view, NSInteger maxBytes);

// MARK: - Manual styling (for sub-lexing things Lexilla doesn't natively cover,
//         e.g. CSS embedded in HTML <style> blocks).

/// Apply a single Scintilla style to a UTF-16 character range of the buffer.
/// Indices are NSString-style (UTF-16); we convert to byte positions internally
/// so non-ASCII text works correctly. Safe to call repeatedly.
void SciSetCustomStyleUTF16(NSView *view, NSInteger utf16Start, NSInteger utf16Length, int style);

// MARK: - Find / Replace
//
// All positions in this section are BYTE offsets into the UTF-8 buffer (the
// native Scintilla coordinate system). For pure-ASCII text this is the same as
// character count; for multi-byte UTF-8 it isn't. The find bar passes UTF-8
// patterns via NSString.UTF8String and treats results as opaque byte ranges
// (selection/replacement work uniformly in byte space).

typedef NS_OPTIONS(int, SciFindFlags) {
    SciFindNone       = 0,
    SciFindMatchCase  = 0x4,        // SCFIND_MATCHCASE
    SciFindWholeWord  = 0x2,        // SCFIND_WHOLEWORD
    SciFindWordStart  = 0x100000,   // SCFIND_WORDSTART
    SciFindRegex      = 0x200000,   // SCFIND_REGEXP (Scintilla's basic regex)
};

/// Search for `pattern` (as UTF-8 bytes) within byte range [startByte, endByte).
/// Pass `endByte = -1` to search through end of buffer.
/// Returns `{NSNotFound, 0}` if not found, otherwise `{matchStartByte, matchLengthBytes}`.
NSRange SciFind(NSView *view,
                NSString *pattern,
                SciFindFlags flags,
                NSInteger startByte,
                NSInteger endByte);

/// Current selection as byte range. Empty selection has length 0.
NSRange SciGetSelectionBytes(NSView *view);

/// Set selection by byte positions and ensure caret is visible.
void SciSetSelectionBytes(NSView *view, NSInteger startByte, NSInteger endByte);

/// Total document length in bytes.
NSInteger SciTextLengthBytes(NSView *view);

/// Replace the byte range [startByte, endByte) with `replacement` (UTF-8).
/// Returns the new end-of-replacement byte position (startByte + replacement byte length).
NSInteger SciReplaceBytesRange(NSView *view,
                               NSInteger startByte,
                               NSInteger endByte,
                               NSString *replacement);

/// Group subsequent edits into a single undo step. Must be balanced.
void SciBeginUndoAction(NSView *view);
void SciEndUndoAction(NSView *view);

// MARK: - View options (wrap, zoom, indent guides, whitespace, brace match)

typedef NS_ENUM(int, SciWrapMode) {
    SciWrapNone       = 0,   // SC_WRAP_NONE
    SciWrapWord       = 1,   // SC_WRAP_WORD
    SciWrapChar       = 2,   // SC_WRAP_CHAR
    SciWrapWhitespace = 3,   // SC_WRAP_WHITESPACE
};

typedef NS_ENUM(int, SciIndentGuides) {
    SciIndentGuidesNone        = 0,   // SC_IV_NONE
    SciIndentGuidesReal        = 1,   // SC_IV_REAL
    SciIndentGuidesLookForward = 2,   // SC_IV_LOOKFORWARD
    SciIndentGuidesLookBoth    = 3,   // SC_IV_LOOKBOTH
};

typedef NS_ENUM(int, SciWhitespaceMode) {
    SciWhitespaceInvisible          = 0,   // SCWS_INVISIBLE
    SciWhitespaceVisibleAlways      = 1,   // SCWS_VISIBLEALWAYS
    SciWhitespaceVisibleAfterIndent = 2,   // SCWS_VISIBLEAFTERINDENT
    SciWhitespaceVisibleOnlyInIndent = 3,  // SCWS_VISIBLEONLYININDENT
};

void SciSetWrapMode(NSView *view, SciWrapMode mode);

void SciZoomIn(NSView *view);
void SciZoomOut(NSView *view);
void SciSetZoom(NSView *view, NSInteger level);
NSInteger SciGetZoom(NSView *view);

void SciSetIndentGuides(NSView *view, SciIndentGuides mode);
void SciSetIndentGuideColor(NSView *view, NSColor *color);

void SciSetViewWhitespace(NSView *view, SciWhitespaceMode mode);
void SciSetViewEOL(NSView *view, BOOL visible);
void SciSetWhitespaceColors(NSView *view, NSColor *fg, NSColor * _Nullable bg);

/// Update brace-match highlighting based on the caret position.
/// If caret sits next to a brace, find its match and call SCI_BRACEHIGHLIGHT.
/// If no match, call SCI_BRACEBADLIGHT. Pass -1 to clear.
void SciUpdateBraceMatch(NSView *view);

/// Configure the colors used for STYLE_BRACELIGHT (good match) and
/// STYLE_BRACEBAD (no match). Call once when applying a color scheme.
void SciSetBraceStyles(NSView *view, NSColor *goodFg, NSColor *goodBg, NSColor *badFg);

// MARK: - Cursor / line info (for status bar, go-to-line, etc.)

NSInteger SciGetCurrentLine(NSView *view);   // 0-based
NSInteger SciGetCurrentColumn(NSView *view); // 0-based, columns (tabs expand)
NSInteger SciGetLineCount(NSView *view);
void      SciGoToLine(NSView *view, NSInteger line1Based);

// MARK: - Multi-selection

void SciSetMultipleSelectionEnabled(NSView *view, BOOL enabled);
/// Try to expand selection to include the next occurrence of the current
/// selection. If selection is empty, expand to the surrounding word first.
/// Returns YES if a new selection was added.
BOOL SciAddNextOccurrenceToSelection(NSView *view);
/// Total selection count (1 = single caret; >1 = multi-cursor mode).
NSInteger SciSelectionCount(NSView *view);
void SciClearAdditionalSelections(NSView *view);

// MARK: - Markers (bookmarks, etc.)

void SciDefineBookmarkMarker(NSView *view, int markerNumber, NSColor *fg, NSColor *bg);
void SciMarkerAdd(NSView *view, NSInteger line, int markerNumber);
void SciMarkerRemove(NSView *view, NSInteger line, int markerNumber);
BOOL SciMarkerExistsOnLine(NSView *view, NSInteger line, int markerNumber);
NSInteger SciMarkerNext(NSView *view, NSInteger fromLine, int markerNumber);
NSInteger SciMarkerPrevious(NSView *view, NSInteger fromLine, int markerNumber);
void SciMarkerDeleteAll(NSView *view, int markerNumber);

// MARK: - Per-line read/write helpers

NSString *SciGetLineText(NSView *view, NSInteger line0Based);
NSInteger SciLineStartByte(NSView *view, NSInteger line0Based);
NSInteger SciLineEndByte(NSView *view, NSInteger line0Based);   // before EOL
NSInteger SciLineFromByte(NSView *view, NSInteger byte);

// MARK: - Folding

/// Enable code folding for the current lexer. Configures margin 2 with the
/// SC_MASK_FOLDERS marker set, sets SCI_SETPROPERTY "fold"="1", and defines
/// the seven fold marker glyphs. Call after SciApplyLexer.
void SciEnableFolding(NSView *view, BOOL enabled, NSColor *markerFg, NSColor *markerBg);

void SciToggleFoldAtLine(NSView *view, NSInteger line);
void SciFoldAll(NSView *view);
void SciUnfoldAll(NSView *view);

/// Install a handler for SCN_MARGINCLICK. Called with the byte position and
/// the margin index. Replaces any prior handler.
void SciSetMarginClickHandler(NSView *view,
                              void (^_Nullable handler)(NSInteger bytePos, NSInteger margin));

// MARK: - Autocomplete

void SciAutoCShow(NSView *view, NSInteger lenEntered, NSString *spaceSeparatedItems);
void SciAutoCCancel(NSView *view);
BOOL SciAutoCActive(NSView *view);
void SciAutoCSetIgnoreCase(NSView *view, BOOL ignore);
void SciAutoCSetSeparator(NSView *view, int separatorCharCode);

// MARK: - Git diff gutter markers

void SciSetupGitGutter(NSView *view,
                       int addedMarker,
                       int modifiedMarker,
                       int deletedMarker,
                       NSColor *addedColor,
                       NSColor *modifiedColor,
                       NSColor *deletedColor);
void SciGitGutterClearLines(NSView *view, int addedMarker, int modifiedMarker, int deletedMarker);

// MARK: - Indicators (for AI ghost-text, LSP squiggles, bracket-pair colorize, etc.)
//
// Scintilla supports 32 indicators (0–31). Slots 8–31 are user-defined. The
// canonical allocation lives in Allocations.h — refer to SPIndicator* names,
// never bare integers.

typedef NS_ENUM(int, SciIndicatorStyle) {
    SciIndicatorStylePlain            = 0,
    SciIndicatorStyleSquiggle         = 1,
    SciIndicatorStyleTT               = 2,
    SciIndicatorStyleDiagonal         = 3,
    SciIndicatorStyleStrike           = 4,
    SciIndicatorStyleHidden           = 5,
    SciIndicatorStyleBox              = 6,
    SciIndicatorStyleRoundBox         = 7,
    SciIndicatorStyleStraightBox      = 8,
    SciIndicatorStyleDash             = 9,
    SciIndicatorStyleDots             = 10,
    SciIndicatorStyleSquiggleLow      = 11,
    SciIndicatorStyleDotBox           = 12,
    SciIndicatorStyleCompositionThick = 14,
    SciIndicatorStyleCompositionThin  = 15,
    SciIndicatorStyleFullBox          = 16,
    SciIndicatorStyleTextFore         = 17,
    SciIndicatorStylePoint            = 18,
    SciIndicatorStylePointCharacter   = 19,
    SciIndicatorStyleGradient         = 20,
    SciIndicatorStyleGradientCentre   = 21,
};

/// Configure a single indicator. `alpha` is 0–255 (effective only for
/// box/gradient styles); use 256 to mean "scintilla default".
void SciDefineIndicator(NSView *view,
                        int indicatorNumber,
                        SciIndicatorStyle style,
                        NSColor *foreground,
                        NSInteger alpha);

/// Paint `lengthBytes` bytes starting at `startByte` with `indicatorNumber`.
void SciIndicatorFillRange(NSView *view, int indicatorNumber, NSInteger startByte, NSInteger lengthBytes);

/// Clear `indicatorNumber` from a range.
void SciIndicatorClearRange(NSView *view, int indicatorNumber, NSInteger startByte, NSInteger lengthBytes);

/// YES if `indicatorNumber` is set at the given byte position.
BOOL SciIndicatorAtPosition(NSView *view, int indicatorNumber, NSInteger bytePos);

// MARK: - Annotations (multi-line text bound to a single document line)
//
// Used for: LSP inline error messages, AI multi-line ghost suggestions.
// Visibility is per-view; per-line text + style is per line.

typedef NS_ENUM(int, SciAnnotationVisibility) {
    SciAnnotationHidden   = 0,
    SciAnnotationStandard = 1,
    SciAnnotationBoxed    = 2,
    SciAnnotationIndented = 3,
};

void SciSetAnnotationVisibility(NSView *view, SciAnnotationVisibility mode);
/// Pass nil to clear the annotation on this line.
void SciSetAnnotationText(NSView *view, NSInteger line0Based, NSString * _Nullable text);
void SciSetAnnotationStyle(NSView *view, NSInteger line0Based, int styleIndex);
void SciClearAllAnnotations(NSView *view);

// MARK: - EOL annotations (single-line text appended after the last char of a line)
//
// Used for: LSP inlay hints (parameter names, type hints), inline blame, AI
// single-line ghost suggestions, presence cursors in CRDT collab.

void SciSetEOLAnnotationVisibility(NSView *view, int mode);
void SciSetEOLAnnotationText(NSView *view, NSInteger line0Based, NSString * _Nullable text);
void SciSetEOLAnnotationStyle(NSView *view, NSInteger line0Based, int styleIndex);
void SciClearAllEOLAnnotations(NSView *view);

// MARK: - Mouse dwell (hover) timing
//
// Pass milliseconds idle before SCN_DWELLSTART fires; pass -1 to disable.
void SciSetMouseDwellTime(NSView *view, NSInteger milliseconds);

// MARK: - Document operations
//
// Targeted by-byte mutations that don't move the selection. Edits made via
// these calls participate in undo via SciBeginUndoAction / SciEndUndoAction.

/// Insert UTF-8 text at the given byte position. Selection unchanged.
void SciInsertTextAt(NSView *view, NSInteger bytePos, NSString *text);

/// Delete `lengthBytes` bytes starting at `startByte`. Selection clamped.
void SciDeleteRange(NSView *view, NSInteger startByte, NSInteger lengthBytes);

/// Resolve (line, column) to byte position. Column 0 means start of line.
/// Returns end-of-line byte if column exceeds the line's last column.
NSInteger SciPositionFromLineColumn(NSView *view, NSInteger line0Based, NSInteger column0Based);

// MARK: - Visible-range info (folded-aware)

/// First display line currently visible at the top of the viewport.
NSInteger SciVisibleLineFirst(NSView *view);

/// Number of lines visible on screen (display lines, not document lines).
NSInteger SciVisibleLineCount(NSView *view);

/// Convert visible (display) line → document line. They differ when folds
/// are collapsed.
NSInteger SciDocLineFromVisible(NSView *view, NSInteger visibleLine);

/// Convert document line → visible (display) line.
NSInteger SciVisibleLineFromDoc(NSView *view, NSInteger docLine);

// MARK: - Coordinate conversion (for popovers anchored near caret)

/// Pixel point (in the editor view's coordinate space) of the given byte
/// position. Returns NSZeroPoint if position is off-screen.
NSPoint SciPointFromPosition(NSView *view, NSInteger bytePos);

// MARK: - Margins 1 + 4 setup (breakpoint + diagnostic, allocated in Allocations.h)

/// Configure margin 1 as a sensitive symbol margin showing breakpoint /
/// bookmark markers. Idempotent.
void SciSetupBreakpointMargin(NSView *view, NSColor *foreground, NSColor *background);

/// Configure margin 4 to show LSP diagnostic severity icons. `*Color` args
/// are background colors for the four severity marker numbers; pass nil to
/// keep the existing color.
void SciSetupDiagnosticMargin(NSView *view,
                              NSColor * _Nullable errorColor,
                              NSColor * _Nullable warningColor,
                              NSColor * _Nullable infoColor,
                              NSColor * _Nullable hintColor);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
