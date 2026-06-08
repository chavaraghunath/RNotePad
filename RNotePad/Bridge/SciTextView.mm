// SPDX-License-Identifier: MIT
// RNotePad — Obj-C++ implementation. The only file that includes Scintilla's
// C++-leaky headers. Swift never sees these.

#import "SciTextView.h"

#import <Scintilla/ScintillaView.h>
#import <Scintilla/Scintilla.h>
#import <Scintilla/ILexer.h>

// SciLexer.h (style index constants) and Lexilla.h (CreateLexerFn) live in
// lexilla/include/ — added to clang's include path by build.sh.
#import "SciLexer.h"
#import "Lexilla.h"

#import <dlfcn.h>
#import <objc/runtime.h>

// MARK: - View lifecycle

NSView *SciMakeView(NSRect frame) {
    ScintillaView *v = [[ScintillaView alloc] initWithFrame:frame];
    [v setEditable:YES];
    return v;
}

void SciSetText(NSView *view, NSString *text) {
    [(ScintillaView *)view setString:text];
}

NSString *SciGetText(NSView *view) {
    return [(ScintillaView *)view string];
}

void SciSetFont(NSView *view, NSString *name, CGFloat size) {
    [(ScintillaView *)view setFontName:name size:(int)size bold:NO italic:NO];
}

// MARK: - Lexilla loader

static Lexilla::CreateLexerFn LoadCreateLexer() {
    static dispatch_once_t once;
    static Lexilla::CreateLexerFn fn = nullptr;
    dispatch_once(&once, ^{
        // First try @rpath (used during dev), then alongside the executable in
        // the .app bundle's Frameworks dir, then the system search path.
        const char *candidates[] = {
            "@rpath/liblexilla.dylib",
            "@executable_path/../Frameworks/liblexilla.dylib",
            "liblexilla.dylib",
            nullptr,
        };
        void *dl = nullptr;
        for (int i = 0; candidates[i]; i++) {
            dl = dlopen(candidates[i], RTLD_LAZY);
            if (dl) break;
        }
        if (!dl) {
            NSLog(@"[RNotePad] dlopen liblexilla failed: %s", dlerror());
            return;
        }
        fn = reinterpret_cast<Lexilla::CreateLexerFn>(dlsym(dl, LEXILLA_CREATELEXER));
        if (!fn) {
            NSLog(@"[RNotePad] dlsym CreateLexer failed: %s", dlerror());
        }
    });
    return fn;
}

BOOL SciApplyLexer(NSView *view, NSString *lexerName) {
    ScintillaView *v = (ScintillaView *)view;
    if (!lexerName || lexerName.length == 0) {
        // Detach lexer → plain text mode.
        [v setReferenceProperty:SCI_SETILEXER parameter:0 value:nullptr];
        return YES;
    }
    Lexilla::CreateLexerFn create = LoadCreateLexer();
    if (!create) return NO;
    Scintilla::ILexer5 *lexer = create([lexerName UTF8String]);
    if (!lexer) {
        NSLog(@"[RNotePad] CreateLexer(\"%@\") returned null", lexerName);
        return NO;
    }
    [v setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];
    return YES;
}

void SciApplyPalette(NSView *view,
                     NSDictionary<NSNumber *, NSDictionary *> *palette,
                     NSColor *defaultFg,
                     NSColor *defaultBg,
                     NSColor *lineNumberFg,
                     NSColor *lineNumberBg) {
    ScintillaView *v = (ScintillaView *)view;

    // STYLE_DEFAULT first; then STYLECLEARALL propagates it to all other slots.
    [v setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:@"Menlo"];
    [v setGeneralProperty:SCI_STYLESETSIZE parameter:STYLE_DEFAULT value:13];
    [v setColorProperty:SCI_STYLESETFORE parameter:STYLE_DEFAULT value:defaultFg];
    [v setColorProperty:SCI_STYLESETBACK parameter:STYLE_DEFAULT value:defaultBg];
    [v setGeneralProperty:SCI_STYLECLEARALL parameter:0 value:0];

    // Per-token styles.
    [palette enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSDictionary *attrs, BOOL *stop) {
        int style = key.intValue;
        if (NSColor *fg = attrs[@"fg"]) {
            [v setColorProperty:SCI_STYLESETFORE parameter:style value:fg];
        }
        if (NSColor *bg = attrs[@"bg"]) {
            [v setColorProperty:SCI_STYLESETBACK parameter:style value:bg];
        }
        if (NSNumber *bold = attrs[@"bold"]) {
            [v setGeneralProperty:SCI_STYLESETBOLD parameter:style value:bold.intValue];
        }
    }];

    // Line-number margin style.
    [v setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER value:lineNumberFg];
    [v setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER value:lineNumberBg];

    // Caret + selection that match the theme.
    [v setColorProperty:SCI_SETCARETFORE parameter:0 value:defaultFg];
}

void SciShowLineNumbers(NSView *view, BOOL show) {
    ScintillaView *v = (ScintillaView *)view;
    [v setGeneralProperty:SCI_SETMARGINTYPEN parameter:0 value:SC_MARGIN_NUMBER];
    [v setGeneralProperty:SCI_SETMARGINWIDTHN parameter:0 value:show ? 48 : 0];
}

void SciSetKeywords(NSView *view, int slot, NSString *words) {
    [(ScintillaView *)view setReferenceProperty:SCI_SETKEYWORDS
                                       parameter:slot
                                           value:[words UTF8String]];
}

// MARK: - Save / dirty

void SciSetSavePoint(NSView *view) {
    [(ScintillaView *)view message:SCI_SETSAVEPOINT];
}

BOOL SciIsModified(NSView *view) {
    return [(ScintillaView *)view message:SCI_GETMODIFY] != 0;
}

// MARK: - Notifications

// One small ObjC class per view holds the block. We store it via associated
// objects so we don't subclass ScintillaView.

@interface RNPSciDelegate : NSObject <ScintillaNotificationProtocol>
@property (nonatomic, copy, nullable) void (^handler)(SciNotification);
@end

@implementation RNPSciDelegate
- (void)notification:(SCNotification *)scn {
    if (!self.handler) return;
    int code = scn->nmhdr.code;
    if (code == SCN_MODIFIED || code == SCN_SAVEPOINTREACHED || code == SCN_SAVEPOINTLEFT
        || code == SCN_FOCUSIN || code == SCN_FOCUSOUT) {
        SciNotification typed = (SciNotification)code;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.handler) self.handler(typed);
        });
    }
}
@end

static const char kRNPSciDelegateKey = 0;

void SciSetNotificationHandler(NSView *view, void (^handler)(SciNotification type)) {
    ScintillaView *v = (ScintillaView *)view;
    if (!handler) {
        v.delegate = nil;
        objc_setAssociatedObject(v, &kRNPSciDelegateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    RNPSciDelegate *d = [[RNPSciDelegate alloc] init];
    d.handler = handler;
    objc_setAssociatedObject(v, &kRNPSciDelegateKey, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    v.delegate = d;
}
