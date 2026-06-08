// SPDX-License-Identifier: MIT
// Sourcepad — color schemes for the editor.
//
// Light palette derived from VS Code "Default Light+", dark from
// "Default Dark+" (MIT, microsoft/vscode). Per-lexer style indices come from
// lexilla/include/SciLexer.h.

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
    public let styles: [Int: StyleAttrs]
    public let braceLightFg: NSColor
    public let braceLightBg: NSColor
    public let braceBadFg: NSColor
    public let indentGuideFg: NSColor
    public let whitespaceFg: NSColor

    public struct StyleAttrs {
        public let fg: NSColor?
        public let bg: NSColor?
        public let bold: Bool
        public init(fg: NSColor? = nil, bg: NSColor? = nil, bold: Bool = false) {
            self.fg = fg; self.bg = bg; self.bold = bold
        }
    }

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

private typealias S = ColorScheme.StyleAttrs

// VS Code "Default Light+" / "Default Dark+" color tokens.
private enum Palette {
    // Backgrounds + base fg
    static let bgLight   = NSColor.hex(0xFFFFFF)
    static let fgLight   = NSColor.hex(0x000000)
    static let lnFgLight = NSColor.hex(0x237893)
    static let bgDark    = NSColor.hex(0x1E1E1E)
    static let fgDark    = NSColor.hex(0xD4D4D4)
    static let lnFgDark  = NSColor.hex(0x858585)

    // Token colors
    static let lightComment    = NSColor.hex(0x008000)
    static let lightString     = NSColor.hex(0xA31515)
    static let lightNumber     = NSColor.hex(0x098658)
    static let lightKeyword    = NSColor.hex(0x0000FF)
    static let lightType       = NSColor.hex(0x267F99)
    static let lightFunction   = NSColor.hex(0x795E26)
    static let lightOperator   = NSColor.hex(0x000000)
    static let lightVariable   = NSColor.hex(0x001080)
    static let lightProperty   = NSColor.hex(0x0451A5)
    static let lightTag        = NSColor.hex(0x800000)
    static let lightAttribute  = NSColor.hex(0xE50000)  // red-ish for HTML attrs
    static let lightRegex      = NSColor.hex(0x811F3F)
    static let lightDecorator  = NSColor.hex(0xAF00DB)
    static let lightLink       = NSColor.hex(0x0070C0)
    static let lightHeading    = NSColor.hex(0x800000)

    static let darkComment     = NSColor.hex(0x6A9955)
    static let darkString      = NSColor.hex(0xCE9178)
    static let darkNumber      = NSColor.hex(0xB5CEA8)
    static let darkKeyword     = NSColor.hex(0x569CD6)
    static let darkType        = NSColor.hex(0x4EC9B0)
    static let darkFunction    = NSColor.hex(0xDCDCAA)
    static let darkOperator    = NSColor.hex(0xD4D4D4)
    static let darkVariable    = NSColor.hex(0x9CDCFE)
    static let darkProperty    = NSColor.hex(0x9CDCFE)
    static let darkTag         = NSColor.hex(0x569CD6)
    static let darkAttribute   = NSColor.hex(0x9CDCFE)
    static let darkRegex       = NSColor.hex(0xD16969)
    static let darkDecorator   = NSColor.hex(0xC586C0)
    static let darkLink        = NSColor.hex(0x4FC1FF)
    static let darkHeading     = NSColor.hex(0x569CD6)
}

private func wrap(_ styles: [Int: S], _ mode: ThemeMode) -> ColorScheme {
    switch mode {
    case .light:
        return ColorScheme(defaultFg: Palette.fgLight, defaultBg: Palette.bgLight,
                           lineNumberFg: Palette.lnFgLight, lineNumberBg: Palette.bgLight,
                           styles: styles,
                           braceLightFg: NSColor.hex(0x000000),
                           braceLightBg: NSColor.hex(0xFFE99B),    // soft yellow
                           braceBadFg:   NSColor.hex(0xC00000),
                           indentGuideFg: NSColor.hex(0xD0D0D0),
                           whitespaceFg:  NSColor.hex(0xC0C0C0))
    case .dark:
        return ColorScheme(defaultFg: Palette.fgDark, defaultBg: Palette.bgDark,
                           lineNumberFg: Palette.lnFgDark, lineNumberBg: Palette.bgDark,
                           styles: styles,
                           braceLightFg: NSColor.hex(0xFFFFFF),
                           braceLightBg: NSColor.hex(0x444A3E),    // soft olive
                           braceBadFg:   NSColor.hex(0xFF7070),
                           indentGuideFg: NSColor.hex(0x3A3A3A),
                           whitespaceFg:  NSColor.hex(0x4A4A4A))
    }
}

// MARK: - Per-lexer style maps. Style indices from lexilla/include/SciLexer.h.

private func cppStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENT
        2:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENTLINE
        3:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENTDOC
        4:  S(fg: c ? Palette.lightNumber    : Palette.darkNumber),    // NUMBER
        5:  S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword),   // WORD
        6:  S(fg: c ? Palette.lightString    : Palette.darkString),    // STRING
        7:  S(fg: c ? Palette.lightString    : Palette.darkString),    // CHARACTER
        9:  S(fg: c ? NSColor.hex(0x808080)  : NSColor.hex(0x808080)), // PREPROCESSOR
        10: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),  // OPERATOR
        11: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // IDENTIFIER
        13: S(fg: c ? Palette.lightString    : Palette.darkString),    // VERBATIM
        14: S(fg: c ? Palette.lightRegex     : Palette.darkRegex),     // REGEX
        15: S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENTLINEDOC
        16: S(fg: c ? Palette.lightType      : Palette.darkType),      // WORD2
        17: S(fg: c ? Palette.lightComment   : Palette.darkComment, bold: true), // COMMENTDOCKEYWORD
    ]
}

private func pythonStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment  : Palette.darkComment),  // COMMENTLINE
        2:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),   // NUMBER
        3:  S(fg: c ? Palette.lightString   : Palette.darkString),   // STRING
        4:  S(fg: c ? Palette.lightString   : Palette.darkString),   // CHARACTER
        5:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),  // WORD
        6:  S(fg: c ? Palette.lightString   : Palette.darkString),   // TRIPLE
        7:  S(fg: c ? Palette.lightString   : Palette.darkString),   // TRIPLEDOUBLE
        8:  S(fg: c ? Palette.lightType     : Palette.darkType, bold: true), // CLASSNAME
        9:  S(fg: c ? Palette.lightFunction : Palette.darkFunction), // FUNCNAME
        10: S(fg: c ? Palette.lightOperator : Palette.darkOperator), // OPERATOR
        11: S(fg: c ? Palette.lightVariable : Palette.darkVariable), // IDENTIFIER
        12: S(fg: c ? Palette.lightComment  : Palette.darkComment),  // COMMENTBLOCK
        14: S(fg: c ? Palette.lightType     : Palette.darkType),     // WORD2
        15: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),// DECORATOR
    ]
}

private func jsonStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),   // NUMBER
        2:  S(fg: c ? Palette.lightString   : Palette.darkString),   // STRING
        4:  S(fg: c ? Palette.lightProperty : Palette.darkProperty), // PROPERTYNAME
        5:  S(fg: c ? NSColor.hex(0xEE0000) : NSColor.hex(0xD7BA7D)),// ESCAPESEQUENCE
        6:  S(fg: c ? Palette.lightOperator : Palette.darkOperator), // OPERATOR
        9:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),  // KEYWORD (true/false/null)
        11: S(fg: NSColor.hex(0xFFFFFF), bg: NSColor.hex(c ? 0xCC0000 : 0x800000)), // ERROR
    ]
}

// HTML / XML (Lexilla hypertext + xml use the same SCE_H_* style indices).
// Also covers embedded JavaScript (SCE_HJ_*, 40-53) and embedded PHP (104-127).
private func htmlStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightTag       : Palette.darkTag),       // TAG
        2:  S(fg: c ? Palette.lightTag       : Palette.darkTag),       // TAGUNKNOWN
        3:  S(fg: c ? Palette.lightAttribute : Palette.darkAttribute), // ATTRIBUTE
        4:  S(fg: c ? Palette.lightAttribute : Palette.darkAttribute), // ATTRIBUTEUNKNOWN
        5:  S(fg: c ? Palette.lightNumber    : Palette.darkNumber),    // NUMBER
        6:  S(fg: c ? Palette.lightString    : Palette.darkString),    // DOUBLESTRING
        7:  S(fg: c ? Palette.lightString    : Palette.darkString),    // SINGLESTRING
        8:  S(fg: c ? Palette.lightOperator  : Palette.darkOperator),  // OTHER
        9:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENT
        10: S(fg: c ? Palette.lightNumber    : Palette.darkNumber),    // ENTITY
        11: S(fg: c ? Palette.lightTag       : Palette.darkTag),       // TAGEND
        12: S(fg: c ? Palette.lightTag       : Palette.darkTag),       // XMLSTART
        13: S(fg: c ? Palette.lightTag       : Palette.darkTag),       // XMLEND
        14: S(fg: c ? Palette.lightString    : Palette.darkString),    // SCRIPT
        17: S(fg: c ? Palette.lightString    : Palette.darkString),    // CDATA
        18: S(fg: c ? Palette.lightTag       : Palette.darkTag),       // QUESTION
        19: S(fg: c ? Palette.lightString    : Palette.darkString),    // VALUE
        20: S(fg: c ? Palette.lightComment   : Palette.darkComment),   // XCCOMMENT
        // SGML inside HTML
        21: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),
        22: S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword),
        23: S(fg: c ? Palette.lightProperty  : Palette.darkProperty),
        24: S(fg: c ? Palette.lightString    : Palette.darkString),
        25: S(fg: c ? Palette.lightString    : Palette.darkString),
        29: S(fg: c ? Palette.lightComment   : Palette.darkComment),
        // Embedded JavaScript (SCE_HJ_*)
        40: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),  // HJ_START
        41: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),  // HJ_DEFAULT
        42: S(fg: c ? Palette.lightComment   : Palette.darkComment),   // HJ_COMMENT
        43: S(fg: c ? Palette.lightComment   : Palette.darkComment),   // HJ_COMMENTLINE
        44: S(fg: c ? Palette.lightComment   : Palette.darkComment),   // HJ_COMMENTDOC
        45: S(fg: c ? Palette.lightNumber    : Palette.darkNumber),    // HJ_NUMBER
        46: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // HJ_WORD (identifier)
        47: S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword),   // HJ_KEYWORD
        48: S(fg: c ? Palette.lightString    : Palette.darkString),    // HJ_DOUBLESTRING
        49: S(fg: c ? Palette.lightString    : Palette.darkString),    // HJ_SINGLESTRING
        50: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),  // HJ_SYMBOLS
        51: S(fg: c ? Palette.lightString    : Palette.darkString),    // HJ_STRINGEOL
        52: S(fg: c ? Palette.lightRegex     : Palette.darkRegex),     // HJ_REGEX
        53: S(fg: c ? Palette.lightString    : Palette.darkString),    // HJ_TEMPLATELITERAL
        // ASP-embedded JS (SCE_HJA_*, 55-67) — same colors
        55: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),
        56: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),
        57: S(fg: c ? Palette.lightComment   : Palette.darkComment),
        58: S(fg: c ? Palette.lightComment   : Palette.darkComment),
        59: S(fg: c ? Palette.lightComment   : Palette.darkComment),
        60: S(fg: c ? Palette.lightNumber    : Palette.darkNumber),
        61: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),
        62: S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword),
        63: S(fg: c ? Palette.lightString    : Palette.darkString),
        64: S(fg: c ? Palette.lightString    : Palette.darkString),
        65: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),
        66: S(fg: c ? Palette.lightString    : Palette.darkString),
        67: S(fg: c ? Palette.lightRegex     : Palette.darkRegex),
        // Embedded CSS — applied by CSSStyler post-pass since Lexilla's
        // hypertext lexer doesn't sub-lex CSS. Indices 70-79 are our custom
        // allocation, safely above HJ/HJA (40-67) and below 100.
        70: S(fg: c ? Palette.lightComment   : Palette.darkComment),    // /* comment */
        71: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator),  // @directive
        72: S(fg: c ? Palette.lightTag       : Palette.darkTag),        // tag selector
        73: S(fg: c ? Palette.lightType      : Palette.darkType),       // .class
        74: S(fg: c ? Palette.lightType      : Palette.darkType),       // #id
        75: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),   // :pseudo
        76: S(fg: c ? Palette.lightProperty  : Palette.darkProperty),   // property name
        77: S(fg: c ? Palette.lightString    : Palette.darkString),     // value
        78: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),   // { } ; , : ( )
        79: S(fg: c ? Palette.lightString    : Palette.darkString),     // "string"
    ]
}

private func cssStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightTag       : Palette.darkTag),       // TAG
        2:  S(fg: c ? Palette.lightType      : Palette.darkType),      // CLASS
        3:  S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // PSEUDOCLASS
        4:  S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // UNKNOWN_PSEUDOCLASS
        5:  S(fg: c ? Palette.lightOperator  : Palette.darkOperator),  // OPERATOR
        6:  S(fg: c ? Palette.lightProperty  : Palette.darkProperty),  // IDENTIFIER (prop name)
        7:  S(fg: c ? Palette.lightProperty  : Palette.darkProperty),  // UNKNOWN_IDENTIFIER
        8:  S(fg: c ? Palette.lightString    : Palette.darkString),    // VALUE
        9:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENT
        10: S(fg: c ? Palette.lightType      : Palette.darkType),      // ID
        11: S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword, bold: true), // IMPORTANT
        12: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator), // DIRECTIVE (@media etc.)
        13: S(fg: c ? Palette.lightString    : Palette.darkString),    // DOUBLESTRING
        14: S(fg: c ? Palette.lightString    : Palette.darkString),    // SINGLESTRING
        15: S(fg: c ? Palette.lightProperty  : Palette.darkProperty),  // IDENTIFIER2
        16: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // ATTRIBUTE
        17: S(fg: c ? Palette.lightProperty  : Palette.darkProperty),  // IDENTIFIER3
        18: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // PSEUDOELEMENT
        19: S(fg: c ? Palette.lightProperty  : Palette.darkProperty),  // EXTENDED_IDENTIFIER
        23: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // VARIABLE
    ]
}

private func yamlStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1: S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENT
        2: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // IDENTIFIER (keys)
        3: S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword),   // KEYWORD
        4: S(fg: c ? Palette.lightNumber    : Palette.darkNumber),    // NUMBER
        5: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator), // REFERENCE
        6: S(fg: c ? Palette.lightTag       : Palette.darkTag),       // DOCUMENT
        7: S(fg: c ? Palette.lightString    : Palette.darkString),    // TEXT
        9: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),  // OPERATOR
    ]
}

private func sqlStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment  : Palette.darkComment),   // COMMENT
        2:  S(fg: c ? Palette.lightComment  : Palette.darkComment),   // COMMENTLINE
        3:  S(fg: c ? Palette.lightComment  : Palette.darkComment),   // COMMENTDOC
        4:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),    // NUMBER
        5:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true), // WORD
        6:  S(fg: c ? Palette.lightString   : Palette.darkString),    // STRING
        7:  S(fg: c ? Palette.lightString   : Palette.darkString),    // CHARACTER
        10: S(fg: c ? Palette.lightOperator : Palette.darkOperator),  // OPERATOR
        11: S(fg: c ? Palette.lightVariable : Palette.darkVariable),  // IDENTIFIER
        16: S(fg: c ? Palette.lightType     : Palette.darkType),      // WORD2
    ]
}

private func bashStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        2:  S(fg: c ? Palette.lightComment   : Palette.darkComment),  // COMMENTLINE
        3:  S(fg: c ? Palette.lightNumber    : Palette.darkNumber),   // NUMBER
        4:  S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword),  // WORD
        5:  S(fg: c ? Palette.lightString    : Palette.darkString),   // STRING
        6:  S(fg: c ? Palette.lightString    : Palette.darkString),   // CHARACTER
        7:  S(fg: c ? Palette.lightOperator  : Palette.darkOperator), // OPERATOR
        8:  S(fg: c ? Palette.lightVariable  : Palette.darkVariable), // IDENTIFIER
        9:  S(fg: c ? Palette.lightDecorator : Palette.darkDecorator),// SCALAR ($var)
        10: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator),// PARAM
        11: S(fg: c ? Palette.lightString    : Palette.darkString),   // BACKTICKS
    ]
}

private func rubyStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        2:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENTLINE
        3:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // POD
        4:  S(fg: c ? Palette.lightNumber    : Palette.darkNumber),    // NUMBER
        5:  S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword),   // WORD
        6:  S(fg: c ? Palette.lightString    : Palette.darkString),    // STRING
        7:  S(fg: c ? Palette.lightString    : Palette.darkString),    // CHARACTER
        8:  S(fg: c ? Palette.lightType      : Palette.darkType, bold: true), // CLASSNAME
        9:  S(fg: c ? Palette.lightFunction  : Palette.darkFunction),  // DEFNAME
        10: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),  // OPERATOR
        11: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // IDENTIFIER
        12: S(fg: c ? Palette.lightRegex     : Palette.darkRegex),     // REGEX
        13: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator), // GLOBAL ($)
        14: S(fg: c ? Palette.lightProperty  : Palette.darkProperty),  // SYMBOL (:foo)
        15: S(fg: c ? Palette.lightType      : Palette.darkType),      // MODULE_NAME
        16: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator), // INSTANCE_VAR (@)
        17: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator), // CLASS_VAR (@@)
    ]
}

private func luaStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENT
        2:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENTLINE
        3:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENTDOC
        4:  S(fg: c ? Palette.lightNumber    : Palette.darkNumber),    // NUMBER
        5:  S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword),   // WORD
        6:  S(fg: c ? Palette.lightString    : Palette.darkString),    // STRING
        7:  S(fg: c ? Palette.lightString    : Palette.darkString),    // CHARACTER
        8:  S(fg: c ? Palette.lightString    : Palette.darkString),    // LITERALSTRING
        10: S(fg: c ? Palette.lightOperator  : Palette.darkOperator),  // OPERATOR
        11: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // IDENTIFIER
    ]
}

// PHP — Lexilla's "phpscript" runs the HPHP states (118+) primarily.
private func phpStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    var s = htmlStyles(mode)
    // HPHP_* token states for the PHP code regions
    s[118] = S(fg: c ? Palette.lightOperator  : Palette.darkOperator)   // DEFAULT
    s[119] = S(fg: c ? Palette.lightString    : Palette.darkString)     // HSTRING
    s[120] = S(fg: c ? Palette.lightString    : Palette.darkString)     // SIMPLESTRING
    s[121] = S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword)    // WORD
    s[122] = S(fg: c ? Palette.lightNumber    : Palette.darkNumber)     // NUMBER
    s[123] = S(fg: c ? Palette.lightDecorator : Palette.darkDecorator)  // VARIABLE ($x)
    s[124] = S(fg: c ? Palette.lightComment   : Palette.darkComment)    // COMMENT
    s[125] = S(fg: c ? Palette.lightComment   : Palette.darkComment)    // COMMENTLINE
    s[126] = S(fg: c ? Palette.lightDecorator : Palette.darkDecorator)  // HSTRING_VARIABLE
    s[127] = S(fg: c ? Palette.lightOperator  : Palette.darkOperator)   // OPERATOR
    return s
}

private func propsStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1: S(fg: c ? Palette.lightComment   : Palette.darkComment),  // COMMENT
        2: S(fg: c ? Palette.lightTag       : Palette.darkTag, bold: true), // SECTION [foo]
        3: S(fg: c ? Palette.lightOperator  : Palette.darkOperator), // ASSIGNMENT (=)
        4: S(fg: c ? Palette.lightString    : Palette.darkString),   // DEFVAL
        5: S(fg: c ? Palette.lightProperty  : Palette.darkProperty), // KEY
    ]
}

private func tomlStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment   : Palette.darkComment),   // COMMENT
        2:  S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // IDENTIFIER
        3:  S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword),   // KEYWORD
        4:  S(fg: c ? Palette.lightNumber    : Palette.darkNumber),    // NUMBER
        5:  S(fg: c ? Palette.lightTag       : Palette.darkTag, bold: true), // TABLE [name]
        6:  S(fg: c ? Palette.lightProperty  : Palette.darkProperty),  // KEY
        8:  S(fg: c ? Palette.lightOperator  : Palette.darkOperator),  // OPERATOR
        9:  S(fg: c ? Palette.lightString    : Palette.darkString),    // STRING_SQ
        10: S(fg: c ? Palette.lightString    : Palette.darkString),    // STRING_DQ
        11: S(fg: c ? Palette.lightString    : Palette.darkString),    // TRIPLE_STRING_SQ
        12: S(fg: c ? Palette.lightString    : Palette.darkString),    // TRIPLE_STRING_DQ
        13: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator), // ESCAPECHAR
        14: S(fg: c ? Palette.lightNumber    : Palette.darkNumber),    // DATETIME
    ]
}

private func markdownStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    let h = c ? Palette.lightHeading : Palette.darkHeading
    return [
        2:  S(fg: c ? Palette.lightTag      : Palette.darkTag, bold: true),    // STRONG1
        3:  S(fg: c ? Palette.lightTag      : Palette.darkTag, bold: true),    // STRONG2
        4:  S(fg: c ? Palette.lightFunction : Palette.darkFunction),           // EM1
        5:  S(fg: c ? Palette.lightFunction : Palette.darkFunction),           // EM2
        6:  S(fg: h, bold: true),  // HEADER1
        7:  S(fg: h, bold: true),  // HEADER2
        8:  S(fg: h, bold: true),  // HEADER3
        9:  S(fg: h, bold: true),  // HEADER4
        10: S(fg: h, bold: true),  // HEADER5
        11: S(fg: h, bold: true),  // HEADER6
        13: S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),            // ULIST_ITEM
        14: S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),            // OLIST_ITEM
        15: S(fg: c ? Palette.lightComment  : Palette.darkComment),            // BLOCKQUOTE
        18: S(fg: c ? Palette.lightLink     : Palette.darkLink),               // LINK
        19: S(fg: c ? Palette.lightString   : Palette.darkString),             // CODE `inline`
        20: S(fg: c ? Palette.lightString   : Palette.darkString),             // CODE2
        21: S(fg: c ? Palette.lightString   : Palette.darkString),             // CODEBK (fenced)
    ]
}

private func makefileStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1: S(fg: c ? Palette.lightComment   : Palette.darkComment),  // COMMENT
        2: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator),// PREPROCESSOR
        3: S(fg: c ? Palette.lightVariable  : Palette.darkVariable), // IDENTIFIER ($(VAR))
        4: S(fg: c ? Palette.lightOperator  : Palette.darkOperator), // OPERATOR
        5: S(fg: c ? Palette.lightFunction  : Palette.darkFunction, bold: true), // TARGET
    ]
}

private func diffStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1: S(fg: c ? Palette.lightComment  : Palette.darkComment),   // COMMENT
        2: S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),   // COMMAND
        3: S(fg: c ? Palette.lightTag      : Palette.darkTag),       // HEADER
        4: S(fg: c ? Palette.lightOperator : Palette.darkOperator),  // POSITION
        5: S(fg: NSColor.hex(c ? 0xA31515 : 0xCE9178)),              // DELETED
        6: S(fg: NSColor.hex(c ? 0x098658 : 0xB5CEA8)),              // ADDED
        7: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator), // CHANGED
    ]
}

// MARK: - Phase 8: additional lexer style maps

private func perlStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        2:  S(fg: c ? Palette.lightComment  : Palette.darkComment),   // COMMENTLINE
        3:  S(fg: c ? Palette.lightComment  : Palette.darkComment),   // POD
        4:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),    // NUMBER
        5:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),  // WORD (keyword)
        6:  S(fg: c ? Palette.lightString   : Palette.darkString),    // STRING
        7:  S(fg: c ? Palette.lightString   : Palette.darkString),    // CHARACTER
        8:  S(fg: c ? Palette.lightOperator : Palette.darkOperator),  // PUNCTUATION
        10: S(fg: c ? Palette.lightOperator : Palette.darkOperator),  // OPERATOR
        11: S(fg: c ? Palette.lightFunction : Palette.darkFunction),  // IDENTIFIER
        12: S(fg: c ? Palette.lightVariable : Palette.darkVariable),  // SCALAR ($)
        13: S(fg: c ? Palette.lightVariable : Palette.darkVariable),  // ARRAY (@)
        14: S(fg: c ? Palette.lightVariable : Palette.darkVariable),  // HASH (%)
        17: S(fg: c ? Palette.lightRegex    : Palette.darkRegex),     // REGEX
        20: S(fg: c ? Palette.lightString   : Palette.darkString),    // BACKTICKS
    ]
}

private func powershellStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment  : Palette.darkComment),   // COMMENT
        2:  S(fg: c ? Palette.lightString   : Palette.darkString),    // STRING
        3:  S(fg: c ? Palette.lightString   : Palette.darkString),    // CHARACTER
        4:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),    // NUMBER
        5:  S(fg: c ? Palette.lightVariable : Palette.darkVariable),  // VARIABLE
        6:  S(fg: c ? Palette.lightOperator : Palette.darkOperator),  // OPERATOR
        7:  S(fg: c ? Palette.lightFunction : Palette.darkFunction),  // IDENTIFIER
        8:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),  // KEYWORD
        9:  S(fg: c ? Palette.lightType     : Palette.darkType),      // CMDLET
        10: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator), // ALIAS
        11: S(fg: c ? Palette.lightFunction : Palette.darkFunction),  // FUNCTION
        13: S(fg: c ? Palette.lightComment  : Palette.darkComment),   // COMMENTSTREAM
        14: S(fg: c ? Palette.lightString   : Palette.darkString),    // HERE_STRING
    ]
}

private func batchStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1: S(fg: c ? Palette.lightComment  : Palette.darkComment),
        2: S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        3: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),  // LABEL
        5: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        6: S(fg: c ? Palette.lightVariable : Palette.darkVariable),   // IDENTIFIER ($VAR)
        7: S(fg: c ? Palette.lightString   : Palette.darkString),
    ]
}

private func asmStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment   : Palette.darkComment),
        2:  S(fg: c ? Palette.lightNumber    : Palette.darkNumber),
        3:  S(fg: c ? Palette.lightString    : Palette.darkString),
        4:  S(fg: c ? Palette.lightOperator  : Palette.darkOperator),
        5:  S(fg: c ? Palette.lightFunction  : Palette.darkFunction),  // IDENTIFIER
        6:  S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword, bold: true), // CPUINSTR
        7:  S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword),   // MATHINSTR
        8:  S(fg: c ? Palette.lightType      : Palette.darkType),      // REGISTER
        9:  S(fg: c ? Palette.lightDecorator : Palette.darkDecorator), // DIRECTIVE
        10: S(fg: c ? Palette.lightVariable  : Palette.darkVariable),  // DIRECTIVEOPERAND
    ]
}

private func pascalStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        2:  S(fg: c ? Palette.lightComment  : Palette.darkComment),    // COMMENTLINE
        3:  S(fg: c ? Palette.lightComment  : Palette.darkComment),    // COMMENT
        4:  S(fg: c ? Palette.lightComment  : Palette.darkComment),    // COMMENTBOR ({...})
        5:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        6:  S(fg: c ? Palette.lightString   : Palette.darkString),
        8:  S(fg: c ? Palette.lightString   : Palette.darkString),     // CHARACTER
        9:  S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        11: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),  // DIRECTIVE
        12: S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        13: S(fg: c ? Palette.lightType     : Palette.darkType),
    ]
}

private func rStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1: S(fg: c ? Palette.lightComment  : Palette.darkComment),
        2: S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),  // KWORD
        3: S(fg: c ? Palette.lightType     : Palette.darkType),                 // BASEKWORD
        4: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),            // OTHERKWORD
        5: S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        6: S(fg: c ? Palette.lightString   : Palette.darkString),
        7: S(fg: c ? Palette.lightString   : Palette.darkString),               // STRING2
        8: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        9: S(fg: c ? Palette.lightFunction : Palette.darkFunction),             // IDENTIFIER
        10: S(fg: c ? Palette.lightOperator: Palette.darkOperator),             // INFIX
    ]
}

private func matlabStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1: S(fg: c ? Palette.lightComment  : Palette.darkComment),
        2: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),  // COMMAND
        3: S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        4: S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        5: S(fg: c ? Palette.lightString   : Palette.darkString),
        6: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        7: S(fg: c ? Palette.lightFunction : Palette.darkFunction),
        8: S(fg: c ? Palette.lightString   : Palette.darkString),
    ]
}

private func tclStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1: S(fg: c ? Palette.lightComment  : Palette.darkComment),
        2: S(fg: c ? Palette.lightComment  : Palette.darkComment),
        3: S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        5: S(fg: c ? Palette.lightString   : Palette.darkString),
        6: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        7: S(fg: c ? Palette.lightFunction : Palette.darkFunction),
        8: S(fg: c ? Palette.lightVariable : Palette.darkVariable),  // SUBSTITUTION
        12: S(fg: c ? Palette.lightKeyword : Palette.darkKeyword, bold: true),
    ]
}

private func latexStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),  // COMMAND
        2:  S(fg: c ? Palette.lightTag      : Palette.darkTag),                  // TAG
        3:  S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),            // MATH
        4:  S(fg: c ? Palette.lightComment  : Palette.darkComment),
        5:  S(fg: c ? Palette.lightTag      : Palette.darkTag),                  // TAG2
        8:  S(fg: c ? Palette.lightString   : Palette.darkString),               // VERBATIM
        9:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),              // SHORTCMD
        10: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),
        11: S(fg: c ? Palette.lightVariable : Palette.darkVariable),             // CMDOPT
    ]
}

private func haskellStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightFunction : Palette.darkFunction),  // IDENTIFIER
        2:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        3:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        4:  S(fg: c ? Palette.lightString   : Palette.darkString),
        5:  S(fg: c ? Palette.lightString   : Palette.darkString),
        6:  S(fg: c ? Palette.lightType     : Palette.darkType),  // CLASS
        7:  S(fg: c ? Palette.lightType     : Palette.darkType),  // MODULE
        8:  S(fg: c ? Palette.lightType     : Palette.darkType),  // CAPITAL
        9:  S(fg: c ? Palette.lightType     : Palette.darkType),  // DATA
        10: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),  // IMPORT
        11: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        13: S(fg: c ? Palette.lightComment  : Palette.darkComment),
        14: S(fg: c ? Palette.lightComment  : Palette.darkComment),
        18: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),
        20: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
    ]
}

private func lispStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment  : Palette.darkComment),
        2:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        3:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        4:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),
        5:  S(fg: c ? Palette.lightVariable : Palette.darkVariable),
        6:  S(fg: c ? Palette.lightString   : Palette.darkString),
        9:  S(fg: c ? Palette.lightFunction : Palette.darkFunction),
        10: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        11: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),
        12: S(fg: c ? Palette.lightComment  : Palette.darkComment),
    ]
}

private func camlStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightFunction : Palette.darkFunction),
        2:  S(fg: c ? Palette.lightType     : Palette.darkType),         // TAGNAME
        3:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        4:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),
        5:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),
        7:  S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        8:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        9:  S(fg: c ? Palette.lightString   : Palette.darkString),       // CHAR
        11: S(fg: c ? Palette.lightString   : Palette.darkString),
        12: S(fg: c ? Palette.lightComment  : Palette.darkComment),
    ]
}

private func fsharpStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment  : Palette.darkComment),
        2:  S(fg: c ? Palette.lightComment  : Palette.darkComment),
        3:  S(fg: c ? Palette.lightComment  : Palette.darkComment),
        7:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        8:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),
        9:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),
        10: S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),
        11: S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        12: S(fg: c ? Palette.lightString   : Palette.darkString),
        13: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),
        14: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        15: S(fg: c ? Palette.lightFunction : Palette.darkFunction),
        18: S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        19: S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),
    ]
}

private func juliaStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment  : Palette.darkComment),
        2:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        3:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        4:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),
        5:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword),
        6:  S(fg: c ? Palette.lightString   : Palette.darkString),
        7:  S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        8:  S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        9:  S(fg: c ? Palette.lightFunction : Palette.darkFunction),
        10: S(fg: c ? Palette.lightString   : Palette.darkString),
        11: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),  // SYMBOL
        12: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),  // MACRO
        13: S(fg: c ? Palette.lightString   : Palette.darkString),
        14: S(fg: c ? Palette.lightComment  : Palette.darkComment),    // DOCSTRING
        15: S(fg: c ? Palette.lightString   : Palette.darkString),
        18: S(fg: c ? Palette.lightType     : Palette.darkType),
    ]
}

private func nimStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment  : Palette.darkComment),
        2:  S(fg: c ? Palette.lightComment  : Palette.darkComment),  // COMMENTDOC
        3:  S(fg: c ? Palette.lightComment  : Palette.darkComment),
        5:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        6:  S(fg: c ? Palette.lightString   : Palette.darkString),
        7:  S(fg: c ? Palette.lightString   : Palette.darkString),
        8:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        12: S(fg: c ? Palette.lightFunction : Palette.darkFunction),
        15: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        16: S(fg: c ? Palette.lightVariable : Palette.darkVariable),
    ]
}

private func adaStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        2:  S(fg: c ? Palette.lightFunction : Palette.darkFunction),
        3:  S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        4:  S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        5:  S(fg: c ? Palette.lightString   : Palette.darkString),
        7:  S(fg: c ? Palette.lightString   : Palette.darkString),
        9:  S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),
        10: S(fg: c ? Palette.lightComment  : Palette.darkComment),
    ]
}

private func fortranStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1:  S(fg: c ? Palette.lightComment   : Palette.darkComment),
        2:  S(fg: c ? Palette.lightNumber    : Palette.darkNumber),
        3:  S(fg: c ? Palette.lightString    : Palette.darkString),
        4:  S(fg: c ? Palette.lightString    : Palette.darkString),
        6:  S(fg: c ? Palette.lightOperator  : Palette.darkOperator),
        7:  S(fg: c ? Palette.lightFunction  : Palette.darkFunction),
        8:  S(fg: c ? Palette.lightKeyword   : Palette.darkKeyword, bold: true),
        9:  S(fg: c ? Palette.lightType      : Palette.darkType),
        11: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator),
        13: S(fg: c ? Palette.lightDecorator : Palette.darkDecorator),
    ]
}

private func vhdlStyles(_ mode: ThemeMode) -> [Int: S] {
    let c = mode == .light
    return [
        1: S(fg: c ? Palette.lightComment  : Palette.darkComment),
        3: S(fg: c ? Palette.lightNumber   : Palette.darkNumber),
        4: S(fg: c ? Palette.lightString   : Palette.darkString),
        5: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        6: S(fg: c ? Palette.lightFunction : Palette.darkFunction),
        8: S(fg: c ? Palette.lightKeyword  : Palette.darkKeyword, bold: true),
        9: S(fg: c ? Palette.lightOperator : Palette.darkOperator),
        10: S(fg: c ? Palette.lightDecorator: Palette.darkDecorator),
        11: S(fg: c ? Palette.lightFunction : Palette.darkFunction),
        12: S(fg: c ? Palette.lightType     : Palette.darkType),
        13: S(fg: c ? Palette.lightType     : Palette.darkType),
    ]
}

// MARK: - Public lookup

public enum SchemeLibrary {
    public static func scheme(for lexer: String?, mode: ThemeMode) -> ColorScheme {
        let key = lexer ?? ""
        switch key {
        case "cpp":         return wrap(cppStyles(mode),      mode)
        case "python":      return wrap(pythonStyles(mode),   mode)
        case "json":        return wrap(jsonStyles(mode),     mode)
        case "hypertext",
             "xml":         return wrap(htmlStyles(mode),     mode)
        case "css":         return wrap(cssStyles(mode),      mode)
        case "yaml":        return wrap(yamlStyles(mode),     mode)
        case "sql",
             "mssql":       return wrap(sqlStyles(mode),      mode)
        case "bash":        return wrap(bashStyles(mode),     mode)
        case "ruby":        return wrap(rubyStyles(mode),     mode)
        case "lua":         return wrap(luaStyles(mode),      mode)
        case "phpscript":   return wrap(phpStyles(mode),      mode)
        case "props":       return wrap(propsStyles(mode),    mode)
        case "toml":        return wrap(tomlStyles(mode),     mode)
        case "markdown":    return wrap(markdownStyles(mode), mode)
        case "makefile":    return wrap(makefileStyles(mode), mode)
        case "diff":        return wrap(diffStyles(mode),     mode)

        // Phase 8 additions
        case "perl":        return wrap(perlStyles(mode),       mode)
        case "powershell":  return wrap(powershellStyles(mode), mode)
        case "batch":       return wrap(batchStyles(mode),      mode)
        case "asm":         return wrap(asmStyles(mode),        mode)
        case "pascal":      return wrap(pascalStyles(mode),     mode)
        case "r":           return wrap(rStyles(mode),          mode)
        case "matlab":      return wrap(matlabStyles(mode),     mode)
        case "tcl":         return wrap(tclStyles(mode),        mode)
        case "latex":       return wrap(latexStyles(mode),      mode)
        case "haskell":     return wrap(haskellStyles(mode),    mode)
        case "lisp",
             "scheme":      return wrap(lispStyles(mode),       mode)
        case "caml":        return wrap(camlStyles(mode),       mode)
        case "fsharp":      return wrap(fsharpStyles(mode),     mode)
        case "julia":       return wrap(juliaStyles(mode),      mode)
        case "nim",
             "nimrod":      return wrap(nimStyles(mode),        mode)
        case "ada":         return wrap(adaStyles(mode),        mode)
        case "fortran",
             "f77":         return wrap(fortranStyles(mode),    mode)
        case "vhdl",
             "verilog":     return wrap(vhdlStyles(mode),       mode)

        default:            return wrap([:],                   mode)  // fallback: just bg/fg
        }
    }
}
