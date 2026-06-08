// Plain-ObjC façade over Scintilla's ScintillaView so Swift can use it
// without seeing the C++ underneath. No <vector>, no SCNotification in the
// public API.

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// Returns a configured ScintillaView (an NSView subclass) at the given frame.
/// Swift sees this as a plain NSView and can add it to a window's contentView.
NSView *SciMakeView(NSRect frame);

/// Replace the buffer contents.
void SciSetText(NSView *view, NSString *text);

/// Read the current buffer contents.
NSString *SciGetText(NSView *view);

/// Set the editor font (e.g. "Menlo", 13).
void SciSetFont(NSView *view, NSString *name, CGFloat size);

/// Load Lexilla, create a lexer by name (e.g. "cpp", "python"), attach it
/// to the view, and apply a minimal default colour scheme + keywords for it.
/// Returns YES on success. Currently only "cpp" has a built-in colour scheme;
/// other names will set the lexer but leave styles at defaults.
BOOL SciApplyLexer(NSView *view, NSString *lexerName);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
