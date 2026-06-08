// SPDX-License-Identifier: MIT
// Sourcepad — manual CSS tokenizer for HTML <style> blocks.
//
// Lexilla's hypertext lexer doesn't sub-lex CSS inside <style>...</style>
// (only JS via SCE_HJ_*, VBS, PHP, Python). This post-pass finds <style>
// blocks, tokenizes their content with a small state machine, and applies
// custom Scintilla styles in the range 70-79 (which are above Lexilla's
// hypertext/HJ ranges and below 100, so no collisions).
//
// Run AFTER the hypertext lexer has lexed the buffer — we overwrite the
// SCE_H_DEFAULT (0) assignment that Lexilla leaves on CSS content.

import AppKit

public enum CSSStyler {

    /// Custom style indices used for embedded CSS. Match the palette in
    /// ColorScheme.swift's htmlStyles().
    public enum Style {
        public static let comment   = 70
        public static let directive = 71  // @media, @keyframes
        public static let selector  = 72  // tag selectors, default
        public static let cssClass  = 73  // .foo
        public static let cssId     = 74  // #bar
        public static let pseudo    = 75  // :hover, ::before
        public static let property  = 76  // color, background
        public static let value     = 77  // red, 12px (default for value side)
        public static let `operator` = 78 // { } ; , : ( )
        public static let string    = 79  // "..." or '...'
    }

    public static func applyToHTML(view: NSView, text: String) {
        let ns = text as NSString
        let total = ns.length
        var i = 0
        while i < total {
            // Find the next <style ...> tag.
            let tagStart = ns.range(of: "<style",
                                    options: [.caseInsensitive],
                                    range: NSRange(location: i, length: total - i))
            if tagStart.location == NSNotFound { break }
            // Find end of opening tag.
            let openEnd = ns.range(of: ">",
                                   options: [],
                                   range: NSRange(location: tagStart.location, length: total - tagStart.location))
            if openEnd.location == NSNotFound { break }
            let contentStart = openEnd.location + 1

            // Find closing </style>.
            let closeRange = ns.range(of: "</style",
                                      options: [.caseInsensitive],
                                      range: NSRange(location: contentStart, length: total - contentStart))
            if closeRange.location == NSNotFound { break }
            let contentLen = closeRange.location - contentStart

            if contentLen > 0 {
                let block = ns.substring(with: NSRange(location: contentStart, length: contentLen))
                tokenize(block: block, baseOffset: contentStart, view: view)
            }
            i = closeRange.location + closeRange.length
        }
    }

    /// Tokenize a CSS block and apply custom styles to `view` at the absolute
    /// UTF-16 offsets [baseOffset + tokenStart .. tokenStart+length].
    private static func tokenize(block: String, baseOffset: Int, view: NSView) {
        let chars = Array(block.utf16)
        var i = 0
        var inDeclarationBlock = false  // true between { and }
        var afterColonInDecl = false    // true after : (i.e. parsing a value)

        func apply(_ style: Int, from start: Int, to end: Int) {
            let len = end - start
            if len > 0 {
                SciSetCustomStyleUTF16(view, baseOffset + start, len, Int32(style))
            }
        }

        while i < chars.count {
            let c = chars[i]
            // Whitespace
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { i += 1; continue }

            // Block comment /* ... */
            if c == 0x2F /* / */ && i + 1 < chars.count && chars[i + 1] == 0x2A /* * */ {
                let start = i
                i += 2
                while i + 1 < chars.count && !(chars[i] == 0x2A && chars[i + 1] == 0x2F) { i += 1 }
                if i + 1 < chars.count { i += 2 } else { i = chars.count }
                apply(Style.comment, from: start, to: i)
                continue
            }

            // Strings
            if c == 0x22 /* " */ || c == 0x27 /* ' */ {
                let quote = c
                let start = i
                i += 1
                while i < chars.count && chars[i] != quote {
                    if chars[i] == 0x5C /* \ */ && i + 1 < chars.count { i += 2 } else { i += 1 }
                }
                if i < chars.count { i += 1 }
                apply(Style.string, from: start, to: i)
                continue
            }

            // Single-char operators
            if c == 0x7B /* { */ {
                apply(Style.operator, from: i, to: i + 1)
                inDeclarationBlock = true
                afterColonInDecl = false
                i += 1; continue
            }
            if c == 0x7D /* } */ {
                apply(Style.operator, from: i, to: i + 1)
                inDeclarationBlock = false
                afterColonInDecl = false
                i += 1; continue
            }
            if c == 0x3B /* ; */ {
                apply(Style.operator, from: i, to: i + 1)
                afterColonInDecl = false
                i += 1; continue
            }
            if c == 0x2C /* , */ || c == 0x28 /* ( */ || c == 0x29 /* ) */ {
                apply(Style.operator, from: i, to: i + 1)
                i += 1; continue
            }

            // @directive (selector context only)
            if c == 0x40 /* @ */ {
                let start = i
                i += 1
                while i < chars.count && isIdentChar(chars[i]) { i += 1 }
                apply(Style.directive, from: start, to: i)
                continue
            }

            // .class (selector context)
            if c == 0x2E /* . */ && !inDeclarationBlock && i + 1 < chars.count && isIdentStart(chars[i + 1]) {
                let start = i
                i += 1
                while i < chars.count && isIdentChar(chars[i]) { i += 1 }
                apply(Style.cssClass, from: start, to: i)
                continue
            }

            // #id (selector context)
            if c == 0x23 /* # */ && !inDeclarationBlock && i + 1 < chars.count && isIdentStart(chars[i + 1]) {
                let start = i
                i += 1
                while i < chars.count && isIdentChar(chars[i]) { i += 1 }
                apply(Style.cssId, from: start, to: i)
                continue
            }

            // :pseudo (selector context) — but inside declaration block, `:` separates property:value
            if c == 0x3A /* : */ {
                if inDeclarationBlock && !afterColonInDecl {
                    apply(Style.operator, from: i, to: i + 1)
                    afterColonInDecl = true
                    i += 1; continue
                } else {
                    let start = i
                    i += 1
                    if i < chars.count && chars[i] == 0x3A /* :: */ { i += 1 }
                    while i < chars.count && isIdentChar(chars[i]) { i += 1 }
                    apply(Style.pseudo, from: start, to: i)
                    continue
                }
            }

            // # color literal inside value (e.g. #fff or #00ff00)
            if c == 0x23 /* # */ && afterColonInDecl {
                let start = i
                i += 1
                while i < chars.count && isHexChar(chars[i]) { i += 1 }
                apply(Style.value, from: start, to: i)
                continue
            }

            // Identifier (property name in decl block before :, or selector/value)
            if isIdentStart(c) {
                let start = i
                while i < chars.count && isIdentChar(chars[i]) { i += 1 }
                if inDeclarationBlock && !afterColonInDecl {
                    apply(Style.property, from: start, to: i)
                } else if inDeclarationBlock && afterColonInDecl {
                    apply(Style.value, from: start, to: i)
                } else {
                    apply(Style.selector, from: start, to: i)
                }
                continue
            }

            // Number 12px, 0.5em, etc.
            if isDigit(c) || (c == 0x2D /* - */ && i + 1 < chars.count && isDigit(chars[i + 1])) {
                let start = i
                if c == 0x2D { i += 1 }
                while i < chars.count && (isDigit(chars[i]) || chars[i] == 0x2E /* . */) { i += 1 }
                while i < chars.count && (isIdentChar(chars[i]) || chars[i] == 0x25 /* % */) { i += 1 }
                apply(Style.value, from: start, to: i)
                continue
            }

            // Anything else — skip one char.
            i += 1
        }
    }

    private static func isIdentStart(_ c: UInt16) -> Bool {
        return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F /* _ */ || c == 0x2D /* - */
    }
    private static func isIdentChar(_ c: UInt16) -> Bool {
        return isIdentStart(c) || isDigit(c)
    }
    private static func isDigit(_ c: UInt16) -> Bool {
        return c >= 0x30 && c <= 0x39
    }
    private static func isHexChar(_ c: UInt16) -> Bool {
        return isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
    }
}
