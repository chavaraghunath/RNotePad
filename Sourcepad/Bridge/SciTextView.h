// SPDX-License-Identifier: MIT
// Sourcepad — Obj-C façade over Scintilla's ScintillaView. Plain Obj-C only;
// Swift sees this header but never the C++ guts underneath.

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Notification codes (mirrored from Scintilla.h to avoid leaking C++)

// Same numeric values as Scintilla's SCN_* constants.
typedef NS_ENUM(int, SciNotification) {
    SciNotificationModified        = 2008,
    SciNotificationSavePointReached = 2002,
    SciNotificationSavePointLeft   = 2003,
    SciNotificationFocusIn         = 2028,
    SciNotificationFocusOut        = 2029,
    SciNotificationUpdateUI        = 2007,
    SciNotificationMarginClick     = 2010,
};

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
void SciSetNotificationHandler(NSView *view, void (^_Nullable handler)(SciNotification type));

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

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
