// Obj-C++ implementation — the only file that includes the C++-leaky
// Scintilla headers. Swift never sees these.

#import "SciTextView.h"

#import <Scintilla/ScintillaView.h>
#import <Scintilla/Scintilla.h>
#import <Scintilla/ILexer.h>

// SciLexer.h (style index constants) and Lexilla.h (CreateLexerFn) live in
// lexilla/include/ — added to clang's include path by build.sh.
#import "SciLexer.h"
#import "Lexilla.h"

#import <dlfcn.h>

NSView *SciMakeView(NSRect frame) {
    ScintillaView *v = [[ScintillaView alloc] initWithFrame:frame];
    [v setEditable:YES];
    return v;
}

void SciSetText(NSView *view, NSString *text) {
    ScintillaView *v = (ScintillaView *)view;
    [v setString:text];
}

NSString *SciGetText(NSView *view) {
    ScintillaView *v = (ScintillaView *)view;
    return [v string];
}

void SciSetFont(NSView *view, NSString *name, CGFloat size) {
    ScintillaView *v = (ScintillaView *)view;
    [v setFontName:name size:(int)size bold:NO italic:NO];
}

#pragma mark - Lexilla

// Resolve `CreateLexer` from liblexilla.dylib once; cache on first use.
// Build script adds the framework dir to rpath, so @rpath/liblexilla.dylib
// resolves at runtime without DYLD_LIBRARY_PATH.
static Lexilla::CreateLexerFn LoadCreateLexer() {
    static dispatch_once_t once;
    static Lexilla::CreateLexerFn fn = nullptr;
    dispatch_once(&once, ^{
        void *dl = dlopen("@rpath/liblexilla.dylib", RTLD_LAZY);
        if (!dl) {
            NSLog(@"dlopen liblexilla failed: %s", dlerror());
            return;
        }
        fn = reinterpret_cast<Lexilla::CreateLexerFn>(dlsym(dl, LEXILLA_CREATELEXER));
        if (!fn) {
            NSLog(@"dlsym CreateLexer failed: %s", dlerror());
        }
    });
    return fn;
}

// C/C++ keywords (subset; enough to demonstrate). Kept brief on purpose.
static const char *kCppKeywords =
    "alignas alignof and and_eq asm auto bitand bitor bool break case catch "
    "char char8_t char16_t char32_t class compl concept const consteval constexpr "
    "constinit const_cast continue co_await co_return co_yield decltype default "
    "delete do double dynamic_cast else enum explicit export extern false float "
    "for friend goto if inline int long mutable namespace new noexcept not not_eq "
    "nullptr operator or or_eq private protected public register reinterpret_cast "
    "requires return short signed sizeof static static_assert static_cast struct "
    "switch template this thread_local throw true try typedef typeid typename "
    "union unsigned using virtual void volatile wchar_t while xor xor_eq";

static void StyleCpp(ScintillaView *v) {
    // Base font/size for STYLE_DEFAULT, then propagate to all styles.
    [v setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:@"Menlo"];
    [v setGeneralProperty:SCI_STYLESETSIZE parameter:STYLE_DEFAULT value:14];
    [v setColorProperty:SCI_STYLESETFORE parameter:STYLE_DEFAULT value:[NSColor textColor]];
    [v setColorProperty:SCI_STYLESETBACK parameter:STYLE_DEFAULT value:[NSColor textBackgroundColor]];
    [v setGeneralProperty:SCI_STYLECLEARALL parameter:0 value:0];

    // Per-token colours (a calm light-mode palette; ignore for dark mode).
    [v setColorProperty:SCI_STYLESETFORE parameter:SCE_C_COMMENT     fromHTML:@"#5C6370"];
    [v setColorProperty:SCI_STYLESETFORE parameter:SCE_C_COMMENTLINE fromHTML:@"#5C6370"];
    [v setColorProperty:SCI_STYLESETFORE parameter:SCE_C_COMMENTDOC  fromHTML:@"#5C6370"];
    [v setColorProperty:SCI_STYLESETFORE parameter:SCE_C_NUMBER      fromHTML:@"#986801"];
    [v setColorProperty:SCI_STYLESETFORE parameter:SCE_C_WORD        fromHTML:@"#A626A4"];
    [v setGeneralProperty:SCI_STYLESETBOLD parameter:SCE_C_WORD value:1];
    [v setColorProperty:SCI_STYLESETFORE parameter:SCE_C_STRING      fromHTML:@"#50A14F"];
    [v setColorProperty:SCI_STYLESETFORE parameter:SCE_C_CHARACTER   fromHTML:@"#50A14F"];
    [v setColorProperty:SCI_STYLESETFORE parameter:SCE_C_PREPROCESSOR fromHTML:@"#4078F2"];
    [v setColorProperty:SCI_STYLESETFORE parameter:SCE_C_OPERATOR    fromHTML:@"#383A42"];
    [v setColorProperty:SCI_STYLESETFORE parameter:SCE_C_IDENTIFIER  fromHTML:@"#383A42"];

    // Keywords in slot 0.
    [v setReferenceProperty:SCI_SETKEYWORDS parameter:0 value:kCppKeywords];

    // Line numbers in margin 0.
    [v setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER fromHTML:@"#9E9E9E"];
    [v setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER fromHTML:@"#FAFAFA"];
    [v setGeneralProperty:SCI_SETMARGINTYPEN parameter:0 value:SC_MARGIN_NUMBER];
    [v setGeneralProperty:SCI_SETMARGINWIDTHN parameter:0 value:42];
}

BOOL SciApplyLexer(NSView *view, NSString *lexerName) {
    ScintillaView *v = (ScintillaView *)view;

    Lexilla::CreateLexerFn create = LoadCreateLexer();
    if (!create) return NO;

    Scintilla::ILexer5 *lexer = create([lexerName UTF8String]);
    if (!lexer) {
        NSLog(@"CreateLexer(\"%@\") returned null", lexerName);
        return NO;
    }
    [v setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];

    if ([lexerName isEqualToString:@"cpp"]) {
        StyleCpp(v);
    }
    return YES;
}
