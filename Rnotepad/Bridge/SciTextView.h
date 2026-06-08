// SPDX-License-Identifier: MIT
// Rnotepad — Obj-C façade over Scintilla's ScintillaView. Plain Obj-C only;
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

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
