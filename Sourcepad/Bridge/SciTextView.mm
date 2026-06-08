// SPDX-License-Identifier: MIT
// Sourcepad — Obj-C++ implementation. The only file that includes Scintilla's
// C++-leaky headers. Swift never sees these.

#import "SciTextView.h"

#import <Scintilla/ScintillaView.h>
#import <Scintilla/Scintilla.h>
#import <Scintilla/ILexer.h>

// SciLexer.h (style index constants) and Lexilla.h (CreateLexerFn) live in
// lexilla/include/ — added to clang's include path by build.sh.
#import "SciLexer.h"
#import "Lexilla.h"
#import "KeywordSetsGenerated.h"

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
            NSLog(@"[Sourcepad] dlopen liblexilla failed: %s", dlerror());
            return;
        }
        fn = reinterpret_cast<Lexilla::CreateLexerFn>(dlsym(dl, LEXILLA_CREATELEXER));
        if (!fn) {
            NSLog(@"[Sourcepad] dlsym CreateLexer failed: %s", dlerror());
        }
    });
    return fn;
}

// Per-lexer default keyword sets. The full ~25k keywords across 65 lexers
// come from the generated KeywordSetsGenerated.m (extracted from NPP's
// langs.model.xml — language-spec facts, not GPL code). This wrapper is
// kept only as a fallback for the few lexers NPP doesn't cover.
static NSDictionary<NSString *, NSArray<NSString *> *> *FallbackKeywords() {
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
        NSLog(@"[Sourcepad] CreateLexer(\"%@\") returned null", lexerName);
        return NO;
    }
    [v setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];

    // Register keyword sets per lexer. Prefer the comprehensive generated
    // table (extracted from NPP's langs.model.xml — ~25k keywords across
    // 65 lexers); fall back to our hand-rolled shortlist if unavailable.
    NSArray<NSString *> *sets = SPKeywordSetsForLexer(lexerName);
    if (!sets) sets = FallbackKeywords()[lexerName];
    if (sets) {
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
    // Caller is expected to have set the editor font via SciSetEditorFont().
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

void SciSetEditorFont(NSView *view, NSString *fontName, CGFloat fontSize) {
    ScintillaView *v = (ScintillaView *)view;
    NSString *resolved = (fontName.length > 0) ? fontName : @"Menlo";
    int size = (int)(fontSize > 0 ? fontSize : 13);
    [v setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:resolved];
    [v setGeneralProperty:SCI_STYLESETSIZE parameter:STYLE_DEFAULT value:size];
}

void SciSetTabWidth(NSView *view, NSInteger width) {
    [(ScintillaView *)view message:SCI_SETTABWIDTH wParam:(uptr_t)MAX(1, width) lParam:0];
}

void SciSetUseTabs(NSView *view, BOOL useTabs) {
    [(ScintillaView *)view message:SCI_SETUSETABS wParam:(uptr_t)(useTabs ? 1 : 0) lParam:0];
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

@interface SPSciDelegate : NSObject <ScintillaNotificationProtocol>
@property (nonatomic, copy, nullable) void (^handler)(SciNotification);
@end

@implementation SPSciDelegate
- (void)notification:(SCNotification *)scn {
    if (!self.handler) return;
    int code = scn->nmhdr.code;
    if (code == SCN_MODIFIED || code == SCN_SAVEPOINTREACHED || code == SCN_SAVEPOINTLEFT
        || code == SCN_FOCUSIN || code == SCN_FOCUSOUT
        || code == SCN_UPDATEUI || code == SCN_MARGINCLICK) {
        SciNotification typed = (SciNotification)code;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.handler) self.handler(typed);
        });
    }
}
@end

static const char kSPSciDelegateKey = 0;

void SciSetNotificationHandler(NSView *view, void (^handler)(SciNotification type)) {
    ScintillaView *v = (ScintillaView *)view;
    if (!handler) {
        v.delegate = nil;
        objc_setAssociatedObject(v, &kSPSciDelegateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    SPSciDelegate *d = [[SPSciDelegate alloc] init];
    d.handler = handler;
    objc_setAssociatedObject(v, &kSPSciDelegateKey, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

// MARK: - Manual styling

// MARK: - Find / Replace

NSRange SciFind(NSView *view,
                NSString *pattern,
                SciFindFlags flags,
                NSInteger startByte,
                NSInteger endByte) {
    if (pattern.length == 0) return NSMakeRange(NSNotFound, 0);
    ScintillaView *v = (ScintillaView *)view;
    sptr_t docLen = [v message:SCI_GETLENGTH];
    if (endByte < 0 || endByte > docLen) endByte = docLen;
    if (startByte < 0) startByte = 0;
    if (startByte > endByte) return NSMakeRange(NSNotFound, 0);

    const char *utf8 = [pattern UTF8String];
    sptr_t patLen = (sptr_t)strlen(utf8);

    [v message:SCI_SETSEARCHFLAGS wParam:(uptr_t)flags lParam:0];
    [v message:SCI_SETTARGETSTART wParam:(uptr_t)startByte lParam:0];
    [v message:SCI_SETTARGETEND   wParam:(uptr_t)endByte   lParam:0];
    sptr_t found = [v message:SCI_SEARCHINTARGET wParam:(uptr_t)patLen lParam:(sptr_t)utf8];
    if (found < 0) return NSMakeRange(NSNotFound, 0);

    sptr_t matchStart = [v message:SCI_GETTARGETSTART];
    sptr_t matchEnd   = [v message:SCI_GETTARGETEND];
    if (matchEnd < matchStart) return NSMakeRange(NSNotFound, 0);
    return NSMakeRange((NSUInteger)matchStart, (NSUInteger)(matchEnd - matchStart));
}

NSRange SciGetSelectionBytes(NSView *view) {
    ScintillaView *v = (ScintillaView *)view;
    sptr_t s = [v message:SCI_GETSELECTIONSTART];
    sptr_t e = [v message:SCI_GETSELECTIONEND];
    if (e < s) e = s;
    return NSMakeRange((NSUInteger)s, (NSUInteger)(e - s));
}

void SciSetSelectionBytes(NSView *view, NSInteger startByte, NSInteger endByte) {
    ScintillaView *v = (ScintillaView *)view;
    if (startByte < 0) startByte = 0;
    if (endByte < startByte) endByte = startByte;
    [v message:SCI_SETSEL wParam:(uptr_t)startByte lParam:(sptr_t)endByte];
    [v message:SCI_SCROLLCARET];
}

NSInteger SciTextLengthBytes(NSView *view) {
    return (NSInteger)[(ScintillaView *)view message:SCI_GETLENGTH];
}

NSInteger SciReplaceBytesRange(NSView *view,
                               NSInteger startByte,
                               NSInteger endByte,
                               NSString *replacement) {
    ScintillaView *v = (ScintillaView *)view;
    if (startByte < 0) startByte = 0;
    if (endByte < startByte) endByte = startByte;
    const char *utf8 = [replacement UTF8String] ?: "";
    sptr_t repLen = (sptr_t)strlen(utf8);
    [v message:SCI_SETTARGETSTART wParam:(uptr_t)startByte lParam:0];
    [v message:SCI_SETTARGETEND   wParam:(uptr_t)endByte   lParam:0];
    [v message:SCI_REPLACETARGET  wParam:(uptr_t)repLen   lParam:(sptr_t)utf8];
    return startByte + (NSInteger)repLen;
}

void SciBeginUndoAction(NSView *view) {
    [(ScintillaView *)view message:SCI_BEGINUNDOACTION];
}

void SciEndUndoAction(NSView *view) {
    [(ScintillaView *)view message:SCI_ENDUNDOACTION];
}

void SciSetCustomStyleUTF16(NSView *view, NSInteger utf16Start, NSInteger utf16Length, int style) {
    if (utf16Length <= 0) return;
    ScintillaView *v = (ScintillaView *)view;
    NSString *text = [v string];
    if (utf16Start < 0 || utf16Start + utf16Length > (NSInteger)text.length) return;

    NSString *prefix    = (utf16Start > 0) ? [text substringWithRange:NSMakeRange(0, utf16Start)] : @"";
    NSString *substring = [text substringWithRange:NSMakeRange(utf16Start, utf16Length)];
    NSUInteger byteStart  = [prefix lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSUInteger byteLength = [substring lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    [v message:SCI_STARTSTYLING wParam:(uptr_t)byteStart lParam:0];
    [v message:SCI_SETSTYLING   wParam:(uptr_t)byteLength lParam:(sptr_t)style];
}

// MARK: - View options

void SciSetWrapMode(NSView *view, SciWrapMode mode) {
    [(ScintillaView *)view message:SCI_SETWRAPMODE wParam:(uptr_t)mode lParam:0];
}

void SciZoomIn(NSView *view) {
    [(ScintillaView *)view message:SCI_ZOOMIN];
}

void SciZoomOut(NSView *view) {
    [(ScintillaView *)view message:SCI_ZOOMOUT];
}

void SciSetZoom(NSView *view, NSInteger level) {
    // Scintilla clamps to roughly [-10, +50] internally.
    [(ScintillaView *)view message:SCI_SETZOOM wParam:(uptr_t)level lParam:0];
}

NSInteger SciGetZoom(NSView *view) {
    return (NSInteger)[(ScintillaView *)view message:SCI_GETZOOM];
}

void SciSetIndentGuides(NSView *view, SciIndentGuides mode) {
    [(ScintillaView *)view message:SCI_SETINDENTATIONGUIDES wParam:(uptr_t)mode lParam:0];
}

void SciSetIndentGuideColor(NSView *view, NSColor *color) {
    [(ScintillaView *)view setColorProperty:SCI_STYLESETFORE parameter:STYLE_INDENTGUIDE value:color];
}

void SciSetViewWhitespace(NSView *view, SciWhitespaceMode mode) {
    [(ScintillaView *)view message:SCI_SETVIEWWS wParam:(uptr_t)mode lParam:0];
}

void SciSetViewEOL(NSView *view, BOOL visible) {
    [(ScintillaView *)view message:SCI_SETVIEWEOL wParam:(uptr_t)(visible ? 1 : 0) lParam:0];
}

void SciSetWhitespaceColors(NSView *view, NSColor *fg, NSColor *bg) {
    ScintillaView *v = (ScintillaView *)view;
    if (fg) [v setColorProperty:SCI_SETWHITESPACEFORE parameter:1 value:fg];
    if (bg) [v setColorProperty:SCI_SETWHITESPACEBACK parameter:1 value:bg];
}

void SciSetBraceStyles(NSView *view, NSColor *goodFg, NSColor *goodBg, NSColor *badFg) {
    ScintillaView *v = (ScintillaView *)view;
    if (goodFg) [v setColorProperty:SCI_STYLESETFORE parameter:STYLE_BRACELIGHT value:goodFg];
    if (goodBg) [v setColorProperty:SCI_STYLESETBACK parameter:STYLE_BRACELIGHT value:goodBg];
    if (badFg)  [v setColorProperty:SCI_STYLESETFORE parameter:STYLE_BRACEBAD  value:badFg];
    // Bold for emphasis at the match.
    [v setGeneralProperty:SCI_STYLESETBOLD parameter:STYLE_BRACELIGHT value:1];
    [v setGeneralProperty:SCI_STYLESETBOLD parameter:STYLE_BRACEBAD  value:1];
}

static BOOL isBraceChar(int ch) {
    return ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}';
}

void SciUpdateBraceMatch(NSView *view) {
    ScintillaView *v = (ScintillaView *)view;
    sptr_t pos = [v message:SCI_GETCURRENTPOS];
    sptr_t len = [v message:SCI_GETLENGTH];

    // Check the character at caret AND the one before — we want braces on
    // either side to highlight (matches Notepad++ behaviour).
    sptr_t bracePos = -1;
    if (pos < len) {
        int ch = (int)[v message:SCI_GETCHARAT wParam:(uptr_t)pos lParam:0];
        if (isBraceChar(ch)) bracePos = pos;
    }
    if (bracePos < 0 && pos > 0) {
        int ch = (int)[v message:SCI_GETCHARAT wParam:(uptr_t)(pos - 1) lParam:0];
        if (isBraceChar(ch)) bracePos = pos - 1;
    }

    if (bracePos < 0) {
        [v message:SCI_BRACEHIGHLIGHT wParam:(uptr_t)-1 lParam:-1];
        return;
    }
    sptr_t match = [v message:SCI_BRACEMATCH wParam:(uptr_t)bracePos lParam:0];
    if (match < 0) {
        [v message:SCI_BRACEBADLIGHT wParam:(uptr_t)bracePos lParam:0];
    } else {
        [v message:SCI_BRACEHIGHLIGHT wParam:(uptr_t)bracePos lParam:(sptr_t)match];
    }
}

// MARK: - Cursor / line info

NSInteger SciGetCurrentLine(NSView *view) {
    ScintillaView *v = (ScintillaView *)view;
    sptr_t pos = [v message:SCI_GETCURRENTPOS];
    return (NSInteger)[v message:SCI_LINEFROMPOSITION wParam:(uptr_t)pos lParam:0];
}

NSInteger SciGetCurrentColumn(NSView *view) {
    ScintillaView *v = (ScintillaView *)view;
    sptr_t pos = [v message:SCI_GETCURRENTPOS];
    return (NSInteger)[v message:SCI_GETCOLUMN wParam:(uptr_t)pos lParam:0];
}

NSInteger SciGetLineCount(NSView *view) {
    return (NSInteger)[(ScintillaView *)view message:SCI_GETLINECOUNT];
}

void SciGoToLine(NSView *view, NSInteger line1Based) {
    ScintillaView *v = (ScintillaView *)view;
    NSInteger total = (NSInteger)[v message:SCI_GETLINECOUNT];
    if (total <= 0) return;
    NSInteger line = line1Based - 1;        // convert to 0-based
    if (line < 0) line = 0;
    if (line >= total) line = total - 1;
    sptr_t pos = [v message:SCI_POSITIONFROMLINE wParam:(uptr_t)line lParam:0];
    [v message:SCI_GOTOPOS wParam:(uptr_t)pos lParam:0];
    [v message:SCI_SCROLLCARET];
}

// MARK: - Multi-selection

void SciSetMultipleSelectionEnabled(NSView *view, BOOL enabled) {
    ScintillaView *v = (ScintillaView *)view;
    [v message:SCI_SETMULTIPLESELECTION wParam:(uptr_t)(enabled ? 1 : 0) lParam:0];
    [v message:SCI_SETADDITIONALSELECTIONTYPING wParam:(uptr_t)(enabled ? 1 : 0) lParam:0];
    [v message:SCI_SETMULTIPASTE wParam:(uptr_t)(enabled ? 1 : 0) lParam:0];  // 1 = SC_MULTIPASTE_EACH
}

BOOL SciAddNextOccurrenceToSelection(NSView *view) {
    ScintillaView *v = (ScintillaView *)view;
    sptr_t s = [v message:SCI_GETSELECTIONSTART];
    sptr_t e = [v message:SCI_GETSELECTIONEND];
    if (s == e) {
        // Empty selection — expand to the word under caret first.
        sptr_t wordStart = [v message:SCI_WORDSTARTPOSITION wParam:(uptr_t)s lParam:1];
        sptr_t wordEnd   = [v message:SCI_WORDENDPOSITION   wParam:(uptr_t)s lParam:1];
        if (wordStart == wordEnd) return NO;
        [v message:SCI_SETSEL wParam:(uptr_t)wordStart lParam:(sptr_t)wordEnd];
        return YES;
    }
    sptr_t prior = [v message:SCI_GETSELECTIONS];
    [v message:SCI_MULTIPLESELECTADDNEXT];
    sptr_t now = [v message:SCI_GETSELECTIONS];
    return now > prior;
}

NSInteger SciSelectionCount(NSView *view) {
    return (NSInteger)[(ScintillaView *)view message:SCI_GETSELECTIONS];
}

void SciClearAdditionalSelections(NSView *view) {
    [(ScintillaView *)view message:SCI_CLEARSELECTIONS];
}

// MARK: - Markers

void SciDefineBookmarkMarker(NSView *view, int markerNumber, NSColor *fg, NSColor *bg) {
    ScintillaView *v = (ScintillaView *)view;
    [v setGeneralProperty:SCI_MARKERDEFINE parameter:markerNumber value:SC_MARK_BOOKMARK];
    if (fg) [v setColorProperty:SCI_MARKERSETFORE parameter:markerNumber value:fg];
    if (bg) [v setColorProperty:SCI_MARKERSETBACK parameter:markerNumber value:bg];
}

void SciMarkerAdd(NSView *view, NSInteger line, int markerNumber) {
    [(ScintillaView *)view message:SCI_MARKERADD wParam:(uptr_t)line lParam:(sptr_t)markerNumber];
}

void SciMarkerRemove(NSView *view, NSInteger line, int markerNumber) {
    [(ScintillaView *)view message:SCI_MARKERDELETE wParam:(uptr_t)line lParam:(sptr_t)markerNumber];
}

BOOL SciMarkerExistsOnLine(NSView *view, NSInteger line, int markerNumber) {
    sptr_t mask = [(ScintillaView *)view message:SCI_MARKERGET wParam:(uptr_t)line lParam:0];
    return (mask & (1 << markerNumber)) != 0;
}

NSInteger SciMarkerNext(NSView *view, NSInteger fromLine, int markerNumber) {
    return (NSInteger)[(ScintillaView *)view message:SCI_MARKERNEXT
                                              wParam:(uptr_t)fromLine
                                              lParam:(sptr_t)(1 << markerNumber)];
}

NSInteger SciMarkerPrevious(NSView *view, NSInteger fromLine, int markerNumber) {
    return (NSInteger)[(ScintillaView *)view message:SCI_MARKERPREVIOUS
                                              wParam:(uptr_t)fromLine
                                              lParam:(sptr_t)(1 << markerNumber)];
}

void SciMarkerDeleteAll(NSView *view, int markerNumber) {
    [(ScintillaView *)view message:SCI_MARKERDELETEALL wParam:(uptr_t)markerNumber lParam:0];
}

// MARK: - Per-line helpers

NSString *SciGetLineText(NSView *view, NSInteger line) {
    ScintillaView *v = (ScintillaView *)view;
    sptr_t len = [v message:SCI_LINELENGTH wParam:(uptr_t)line lParam:0];
    if (len <= 0) return @"";
    char *buf = (char *)malloc((size_t)len + 1);
    if (!buf) return @"";
    buf[len] = 0;
    [v message:SCI_GETLINE wParam:(uptr_t)line lParam:(sptr_t)buf];
    NSString *out = [[NSString alloc] initWithBytes:buf length:(NSUInteger)len encoding:NSUTF8StringEncoding];
    free(buf);
    return out ?: @"";
}

NSInteger SciLineStartByte(NSView *view, NSInteger line) {
    return (NSInteger)[(ScintillaView *)view message:SCI_POSITIONFROMLINE wParam:(uptr_t)line lParam:0];
}

NSInteger SciLineEndByte(NSView *view, NSInteger line) {
    return (NSInteger)[(ScintillaView *)view message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line lParam:0];
}

NSInteger SciLineFromByte(NSView *view, NSInteger byte) {
    return (NSInteger)[(ScintillaView *)view message:SCI_LINEFROMPOSITION wParam:(uptr_t)byte lParam:0];
}
