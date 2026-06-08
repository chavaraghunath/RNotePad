// SPDX-License-Identifier: MIT
// RNotePad — color schemes for the editor.
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
                           styles: styles)
    case .dark:
        return ColorScheme(defaultFg: Palette.fgDark, defaultBg: Palette.bgDark,
                           lineNumberFg: Palette.lnFgDark, lineNumberBg: Palette.bgDark,
                           styles: styles)
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
        default:            return wrap([:],                   mode)  // fallback: just bg/fg
        }
    }
}
