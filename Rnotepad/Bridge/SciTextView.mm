// SPDX-License-Identifier: MIT
// Rnotepad — Obj-C++ implementation. The only file that includes Scintilla's
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
            NSLog(@"[Rnotepad] dlopen liblexilla failed: %s", dlerror());
            return;
        }
        fn = reinterpret_cast<Lexilla::CreateLexerFn>(dlsym(dl, LEXILLA_CREATELEXER));
        if (!fn) {
            NSLog(@"[Rnotepad] dlsym CreateLexer failed: %s", dlerror());
        }
    });
    return fn;
}

// Per-lexer default keyword sets. Lexilla doesn't ship with hard-coded
// keyword lists — the host app must register them via SCI_SETKEYWORDS, or
// lexers can't distinguish keywords from identifiers.
//
// Keys are Lexilla lexer names. Values are arrays indexed by keyword-set slot
// (0 = primary, 1 = secondary, etc.). Empty strings skip a slot.
static NSDictionary<NSString *, NSArray<NSString *> *> *DefaultKeywords() {
    static NSDictionary *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *cppKw =
            @"alignas alignof and and_eq asm auto bitand bitor bool break case "
            @"catch char char8_t char16_t char32_t class compl concept const "
            @"consteval constexpr constinit const_cast continue co_await "
            @"co_return co_yield decltype default delete do double dynamic_cast "
            @"else enum explicit export extern false float for friend goto if "
            @"inline int long mutable namespace new noexcept not not_eq nullptr "
            @"operator or or_eq private protected public register "
            @"reinterpret_cast requires return short signed sizeof static "
            @"static_assert static_cast struct switch template this thread_local "
            @"throw true try typedef typeid typename union unsigned using "
            @"virtual void volatile wchar_t while xor xor_eq "
            @"abstract async await debugger declare extends finally function "
            @"implements import in instanceof interface let module of package "
            @"super throws transient yield from as is keyof readonly never "
            @"any undefined "
            @"defer fallthrough func go guard map mut pub repeat rune select "
            @"trait type var where with";

        NSString *htmlTags =
            @"a abbr acronym address applet area article aside audio b base "
            @"basefont bdi bdo big blockquote body br button canvas caption "
            @"center cite code col colgroup data datalist dd del details dfn "
            @"dialog dir div dl dt em embed fieldset figcaption figure font "
            @"footer form frame frameset h1 h2 h3 h4 h5 h6 head header hr html "
            @"i iframe img input ins kbd label legend li link main map mark "
            @"menu meta meter nav noframes noscript object ol optgroup option "
            @"output p param picture pre progress q rp rt ruby s samp script "
            @"section select small source span strike strong style sub summary "
            @"sup svg table tbody td template textarea tfoot th thead time "
            @"title tr track tt u ul var video wbr";

        NSString *jsKw =
            @"abstract arguments async await boolean break byte case catch char "
            @"class const continue debugger default delete do double else enum "
            @"eval export extends false final finally float for function goto "
            @"if implements import in instanceof int interface let long native "
            @"new null of package private protected public return short static "
            @"super switch synchronized this throw throws transient true try "
            @"typeof undefined var void volatile while with yield";

        NSString *pyKw =
            @"False None True and as assert async await break class continue "
            @"def del elif else except finally for from global if import in is "
            @"lambda nonlocal not or pass raise return try while with yield "
            @"match case self";

        NSString *sqlKw =
            @"add all alter and any as asc backup between by case check column "
            @"constraint create database default delete desc distinct drop "
            @"exec exists foreign from full group having if in index inner "
            @"insert into is join key left like limit not null on or order "
            @"outer primary procedure right select set table top truncate "
            @"union unique update values view where";

        NSString *bashKw =
            @"alias bg bind break builtin case cd command compgen complete "
            @"continue declare dirs disown do done echo elif else esac eval "
            @"exec exit export false fc fg fi for function getopts hash help "
            @"history if in jobs kill let local logout popd printf pushd pwd "
            @"read readonly return select set shift shopt source suspend test "
            @"then time times trap true type typeset ulimit umask unalias "
            @"unset until wait while";

        NSString *rubyKw =
            @"BEGIN END alias and begin break case class def defined do else "
            @"elsif end ensure false for if in module next nil not or redo "
            @"rescue retry return self super then true undef unless until "
            @"when while yield";

        NSString *luaKw =
            @"and break do else elseif end false for function goto if in "
            @"local nil not or repeat return then true until while";

        table = @{
            @"cpp":       @[ cppKw ],
            @"hypertext": @[ htmlTags, jsKw ],
            @"xml":       @[ htmlTags ],
            @"python":    @[ pyKw ],
            @"sql":       @[ sqlKw ],
            @"mssql":     @[ sqlKw ],
            @"bash":      @[ bashKw ],
            @"ruby":      @[ rubyKw ],
            @"lua":       @[ luaKw ],
        };
    });
    return table;
}

BOOL SciApplyLexer(NSView *view, NSString *lexerName) {
    ScintillaView *v = (ScintillaView *)view;
    if (!lexerName || lexerName.length == 0) {
        // Detach lexer → plain text mode.
        [v setReferenceProperty:SCI_SETILEXER parameter:0 value:nullptr];
        [v message:SCI_COLOURISE wParam:0 lParam:-1];
        return YES;
    }
    Lexilla::CreateLexerFn create = LoadCreateLexer();
    if (!create) return NO;
    Scintilla::ILexer5 *lexer = create([lexerName UTF8String]);
    if (!lexer) {
        NSLog(@"[Rnotepad] CreateLexer(\"%@\") returned null", lexerName);
        return NO;
    }
    [v setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];

    // Register default keyword sets per lexer so it can distinguish keywords
    // from identifiers (otherwise everything ends up as IDENTIFIER tokens).
    if (NSArray<NSString *> *sets = DefaultKeywords()[lexerName]) {
        for (NSInteger slot = 0; slot < (NSInteger)sets.count; slot++) {
            NSString *kw = sets[slot];
            if (kw.length > 0) {
                [v setReferenceProperty:SCI_SETKEYWORDS parameter:(int)slot value:[kw UTF8String]];
            }
        }
    }

    // Force a full re-tokenization so existing buffer text picks up the new
    // lexer's style assignments + freshly-registered keywords.
    [v message:SCI_COLOURISE wParam:0 lParam:-1];
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

// MARK: - Debug

NSString *SciDumpStyles(NSView *view, NSInteger maxBytes) {
    ScintillaView *v = (ScintillaView *)view;
    sptr_t length = [v message:SCI_GETLENGTH];
    sptr_t limit = MIN(length, (sptr_t)maxBytes);
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"buffer length=%ld; dumping first %ld bytes\n", (long)length, (long)limit];
    int lastStyle = -1;
    NSMutableString *run = [NSMutableString string];
    for (sptr_t i = 0; i < limit; i++) {
        int ch = (int)[v message:SCI_GETCHARAT wParam:(uptr_t)i lParam:0];
        int st = (int)[v message:SCI_GETSTYLEAT wParam:(uptr_t)i lParam:0];
        if (st != lastStyle) {
            if (lastStyle >= 0) {
                [out appendFormat:@"  [style %3d] %@\n", lastStyle, run];
            }
            [run setString:@""];
            lastStyle = st;
        }
        // Show printable ASCII + escape newlines/tabs.
        if (ch == '\n') { [run appendString:@"\\n"]; }
        else if (ch == '\t') { [run appendString:@"\\t"]; }
        else if (ch == '\r') { [run appendString:@"\\r"]; }
        else if (ch >= 32 && ch < 127) { [run appendFormat:@"%c", (char)ch]; }
        else { [run appendFormat:@"\\x%02x", ch & 0xff]; }
    }
    if (lastStyle >= 0) {
        [out appendFormat:@"  [style %3d] %@\n", lastStyle, run];
    }
    return out;
}
