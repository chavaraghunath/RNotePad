// SPDX-License-Identifier: MIT
// RNotePad — Color schemes for the editor.
//
// Palettes are derived from VS Code's "Default Light+" and "Default Dark+"
// (MIT, microsoft/vscode). Each scheme maps Scintilla style indices to
// NSColor + bold flag. Different lexer families use different style index
// ranges, so we ship one palette per family (cpp-family, web, generic).

import AppKit

public enum ThemeMode {
    case light
    case dark

    static func from(_ appearance: NSAppearance) -> ThemeMode {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? .dark : .light
    }
}

public struct ColorScheme {
    public let defaultFg: NSColor
    public let defaultBg: NSColor
    public let lineNumberFg: NSColor
    public let lineNumberBg: NSColor
    /// Map of Scintilla style index → (fg, bg, bold)
    public let styles: [Int: StyleAttrs]

    public struct StyleAttrs {
        public let fg: NSColor?
        public let bg: NSColor?
        public let bold: Bool
        public init(fg: NSColor? = nil, bg: NSColor? = nil, bold: Bool = false) {
            self.fg = fg
            self.bg = bg
            self.bold = bold
        }
    }

    /// Convert to the dictionary form that SciApplyPalette expects.
    public func bridgePalette() -> [NSNumber: [String: Any]] {
        var out: [NSNumber: [String: Any]] = [:]
        for (idx, attrs) in styles {
            var dict: [String: Any] = [:]
            if let fg = attrs.fg { dict["fg"] = fg }
            if let bg = attrs.bg { dict["bg"] = bg }
            dict["bold"] = attrs.bold
            out[NSNumber(value: idx)] = dict
        }
        return out
    }
}

extension NSColor {
    fileprivate static func hex(_ rgb: UInt32) -> NSColor {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Style index constants (mirrored from SciLexer.h, kept tiny)
// We avoid exposing SciLexer.h to Swift; these are the ones we color.
private enum SCE {
    // C/C++/Java/Swift/Go/JS/TS (Lexilla "cpp" family)
    static let cDefault     = 0
    static let cComment     = 1
    static let cCommentLine = 2
    static let cCommentDoc  = 3
    static let cNumber      = 4
    static let cWord        = 5    // primary keywords
    static let cString      = 6
    static let cCharacter   = 7
    static let cPreprocessor = 9
    static let cOperator    = 10
    static let cIdentifier  = 11
    static let cStringEol   = 12
    static let cVerbatim    = 13
    static let cRegex       = 14
    static let cCommentLineDoc = 15
    static let cWord2       = 16
    static let cCommentDocKeyword = 17

    // Python (Lexilla "python")
    static let pyDefault = 0
    static let pyCommentLine = 1
    static let pyNumber = 2
    static let pyString = 3
    static let pyCharacter = 4
    static let pyWord = 5
    static let pyTriple = 6
    static let pyTripleDouble = 7
    static let pyClassName = 8
    static let pyFuncName = 9
    static let pyOperator = 10
    static let pyIdentifier = 11
    static let pyCommentBlock = 12
    static let pyStringEol = 13
    static let pyWord2 = 14
    static let pyDecorator = 15

    // JSON (Lexilla "json")
    static let jsonDefault = 0
    static let jsonNumber = 1
    static let jsonString = 2
    static let jsonStringEol = 3
    static let jsonPropertyName = 4
    static let jsonEscape = 5
    static let jsonOperator = 6
    static let jsonUri = 7
    static let jsonCompactIRI = 8
    static let jsonKeyword = 9
    static let jsonLdKeyword = 10
    static let jsonError = 11
}

public enum SchemeLibrary {

    public static func scheme(for lexer: String?, mode: ThemeMode) -> ColorScheme {
        switch (lexer, mode) {
        case ("cpp", .light):    return cppLight
        case ("cpp", .dark):     return cppDark
        case ("python", .light): return pythonLight
        case ("python", .dark):  return pythonDark
        case ("json", .light):   return jsonLight
        case ("json", .dark):    return jsonDark
        default:
            // Fallback: just neutral fg/bg, no per-token coloring.
            return mode == .dark ? genericDark : genericLight
        }
    }

    // MARK: cpp family (covers C, C++, Java, Swift, Go, JS, TS, C#, Kotlin, Rust, etc.)

    static let cppLight: ColorScheme = {
        var s: [Int: ColorScheme.StyleAttrs] = [:]
        s[SCE.cComment]      = .init(fg: .hex(0x008000))
        s[SCE.cCommentLine]  = .init(fg: .hex(0x008000))
        s[SCE.cCommentDoc]   = .init(fg: .hex(0x008000))
        s[SCE.cCommentLineDoc] = .init(fg: .hex(0x008000))
        s[SCE.cCommentDocKeyword] = .init(fg: .hex(0x008000), bold: true)
        s[SCE.cNumber]       = .init(fg: .hex(0x098658))
        s[SCE.cWord]         = .init(fg: .hex(0x0000FF), bold: false)  // keywords
        s[SCE.cWord2]        = .init(fg: .hex(0x267F99))               // secondary
        s[SCE.cString]       = .init(fg: .hex(0xA31515))
        s[SCE.cCharacter]    = .init(fg: .hex(0xA31515))
        s[SCE.cVerbatim]     = .init(fg: .hex(0xA31515))
        s[SCE.cRegex]        = .init(fg: .hex(0x811F3F))
        s[SCE.cPreprocessor] = .init(fg: .hex(0x808080))
        s[SCE.cOperator]     = .init(fg: .hex(0x000000))
        s[SCE.cIdentifier]   = .init(fg: .hex(0x001080))
        return .init(
            defaultFg: .hex(0x000000),
            defaultBg: .hex(0xFFFFFF),
            lineNumberFg: .hex(0x237893),
            lineNumberBg: .hex(0xFFFFFF),
            styles: s
        )
    }()

    static let cppDark: ColorScheme = {
        var s: [Int: ColorScheme.StyleAttrs] = [:]
        s[SCE.cComment]      = .init(fg: .hex(0x6A9955))
        s[SCE.cCommentLine]  = .init(fg: .hex(0x6A9955))
        s[SCE.cCommentDoc]   = .init(fg: .hex(0x6A9955))
        s[SCE.cCommentLineDoc] = .init(fg: .hex(0x6A9955))
        s[SCE.cCommentDocKeyword] = .init(fg: .hex(0x6A9955), bold: true)
        s[SCE.cNumber]       = .init(fg: .hex(0xB5CEA8))
        s[SCE.cWord]         = .init(fg: .hex(0x569CD6))
        s[SCE.cWord2]        = .init(fg: .hex(0x4EC9B0))
        s[SCE.cString]       = .init(fg: .hex(0xCE9178))
        s[SCE.cCharacter]    = .init(fg: .hex(0xCE9178))
        s[SCE.cVerbatim]     = .init(fg: .hex(0xCE9178))
        s[SCE.cRegex]        = .init(fg: .hex(0xD16969))
        s[SCE.cPreprocessor] = .init(fg: .hex(0x808080))
        s[SCE.cOperator]     = .init(fg: .hex(0xD4D4D4))
        s[SCE.cIdentifier]   = .init(fg: .hex(0x9CDCFE))
        return .init(
            defaultFg: .hex(0xD4D4D4),
            defaultBg: .hex(0x1E1E1E),
            lineNumberFg: .hex(0x858585),
            lineNumberBg: .hex(0x1E1E1E),
            styles: s
        )
    }()

    // MARK: python

    static let pythonLight: ColorScheme = {
        var s: [Int: ColorScheme.StyleAttrs] = [:]
        s[SCE.pyCommentLine] = .init(fg: .hex(0x008000))
        s[SCE.pyCommentBlock] = .init(fg: .hex(0x008000))
        s[SCE.pyNumber]      = .init(fg: .hex(0x098658))
        s[SCE.pyString]      = .init(fg: .hex(0xA31515))
        s[SCE.pyCharacter]   = .init(fg: .hex(0xA31515))
        s[SCE.pyTriple]      = .init(fg: .hex(0xA31515))
        s[SCE.pyTripleDouble] = .init(fg: .hex(0xA31515))
        s[SCE.pyWord]        = .init(fg: .hex(0x0000FF))
        s[SCE.pyWord2]       = .init(fg: .hex(0x267F99))
        s[SCE.pyClassName]   = .init(fg: .hex(0x267F99), bold: true)
        s[SCE.pyFuncName]    = .init(fg: .hex(0x795E26))
        s[SCE.pyOperator]    = .init(fg: .hex(0x000000))
        s[SCE.pyIdentifier]  = .init(fg: .hex(0x001080))
        s[SCE.pyDecorator]   = .init(fg: .hex(0xAF00DB))
        return .init(
            defaultFg: .hex(0x000000),
            defaultBg: .hex(0xFFFFFF),
            lineNumberFg: .hex(0x237893),
            lineNumberBg: .hex(0xFFFFFF),
            styles: s
        )
    }()

    static let pythonDark: ColorScheme = {
        var s: [Int: ColorScheme.StyleAttrs] = [:]
        s[SCE.pyCommentLine] = .init(fg: .hex(0x6A9955))
        s[SCE.pyCommentBlock] = .init(fg: .hex(0x6A9955))
        s[SCE.pyNumber]      = .init(fg: .hex(0xB5CEA8))
        s[SCE.pyString]      = .init(fg: .hex(0xCE9178))
        s[SCE.pyCharacter]   = .init(fg: .hex(0xCE9178))
        s[SCE.pyTriple]      = .init(fg: .hex(0xCE9178))
        s[SCE.pyTripleDouble] = .init(fg: .hex(0xCE9178))
        s[SCE.pyWord]        = .init(fg: .hex(0x569CD6))
        s[SCE.pyWord2]       = .init(fg: .hex(0x4EC9B0))
        s[SCE.pyClassName]   = .init(fg: .hex(0x4EC9B0), bold: true)
        s[SCE.pyFuncName]    = .init(fg: .hex(0xDCDCAA))
        s[SCE.pyOperator]    = .init(fg: .hex(0xD4D4D4))
        s[SCE.pyIdentifier]  = .init(fg: .hex(0x9CDCFE))
        s[SCE.pyDecorator]   = .init(fg: .hex(0xC586C0))
        return .init(
            defaultFg: .hex(0xD4D4D4),
            defaultBg: .hex(0x1E1E1E),
            lineNumberFg: .hex(0x858585),
            lineNumberBg: .hex(0x1E1E1E),
            styles: s
        )
    }()

    // MARK: json

    static let jsonLight: ColorScheme = {
        var s: [Int: ColorScheme.StyleAttrs] = [:]
        s[SCE.jsonNumber]       = .init(fg: .hex(0x098658))
        s[SCE.jsonString]       = .init(fg: .hex(0xA31515))
        s[SCE.jsonPropertyName] = .init(fg: .hex(0x0451A5))
        s[SCE.jsonOperator]     = .init(fg: .hex(0x000000))
        s[SCE.jsonKeyword]      = .init(fg: .hex(0x0000FF))
        s[SCE.jsonEscape]       = .init(fg: .hex(0xEE0000))
        s[SCE.jsonError]        = .init(fg: .hex(0xFFFFFF), bg: .hex(0xCC0000))
        return .init(
            defaultFg: .hex(0x000000),
            defaultBg: .hex(0xFFFFFF),
            lineNumberFg: .hex(0x237893),
            lineNumberBg: .hex(0xFFFFFF),
            styles: s
        )
    }()

    static let jsonDark: ColorScheme = {
        var s: [Int: ColorScheme.StyleAttrs] = [:]
        s[SCE.jsonNumber]       = .init(fg: .hex(0xB5CEA8))
        s[SCE.jsonString]       = .init(fg: .hex(0xCE9178))
        s[SCE.jsonPropertyName] = .init(fg: .hex(0x9CDCFE))
        s[SCE.jsonOperator]     = .init(fg: .hex(0xD4D4D4))
        s[SCE.jsonKeyword]      = .init(fg: .hex(0x569CD6))
        s[SCE.jsonEscape]       = .init(fg: .hex(0xD7BA7D))
        s[SCE.jsonError]        = .init(fg: .hex(0xFFFFFF), bg: .hex(0x800000))
        return .init(
            defaultFg: .hex(0xD4D4D4),
            defaultBg: .hex(0x1E1E1E),
            lineNumberFg: .hex(0x858585),
            lineNumberBg: .hex(0x1E1E1E),
            styles: s
        )
    }()

    // MARK: generic fallback

    static let genericLight = ColorScheme(
        defaultFg: .hex(0x000000),
        defaultBg: .hex(0xFFFFFF),
        lineNumberFg: .hex(0x237893),
        lineNumberBg: .hex(0xFFFFFF),
        styles: [:]
    )

    static let genericDark = ColorScheme(
        defaultFg: .hex(0xD4D4D4),
        defaultBg: .hex(0x1E1E1E),
        lineNumberFg: .hex(0x858585),
        lineNumberBg: .hex(0x1E1E1E),
        styles: [:]
    )
}
