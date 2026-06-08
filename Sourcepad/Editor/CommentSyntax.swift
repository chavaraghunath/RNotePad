// SPDX-License-Identifier: MIT
// Sourcepad — comment-syntax lookup table by Lexilla lexer name.

import Foundation

public struct CommentSyntax {
    public let linePrefix: String?
    public let blockOpen: String?
    public let blockClose: String?

    public static func forLexer(_ lexer: String?) -> CommentSyntax {
        guard let lexer else { return CommentSyntax(linePrefix: nil, blockOpen: nil, blockClose: nil) }
        switch lexer {
        // C-family
        case "cpp", "rust", "swift", "kotlin", "scala", "groovy", "dart",
             "java", "csharp", "go", "javascript", "typescript", "verilog":
            return CommentSyntax(linePrefix: "//", blockOpen: "/*", blockClose: "*/")
        // Hash-style
        case "python", "ruby", "perl", "bash", "makefile", "yaml", "toml",
             "powershell", "cmake", "r", "tcl", "nim", "nimrod", "julia",
             "elixir", "crystal", "props":
            return CommentSyntax(linePrefix: "#", blockOpen: nil, blockClose: nil)
        // SQL / Lua / Ada / Haskell / VHDL
        case "sql", "mssql", "lua", "ada", "vhdl", "haskell":
            return CommentSyntax(linePrefix: "--", blockOpen: nil, blockClose: nil)
        // HTML / XML (block-comment only)
        case "hypertext", "xml":
            return CommentSyntax(linePrefix: nil, blockOpen: "<!--", blockClose: "-->")
        // CSS / Stylus / SCSS / LESS / Pascal
        case "css", "less", "stylus", "scss", "sass", "pascal":
            return CommentSyntax(linePrefix: "//", blockOpen: "/*", blockClose: "*/")
        // Lisp family
        case "lisp", "scheme", "clojure":
            return CommentSyntax(linePrefix: ";", blockOpen: nil, blockClose: nil)
        // Batch
        case "batch":
            return CommentSyntax(linePrefix: "REM ", blockOpen: nil, blockClose: nil)
        // Erlang
        case "erlang":
            return CommentSyntax(linePrefix: "%", blockOpen: nil, blockClose: nil)
        // LaTeX
        case "latex":
            return CommentSyntax(linePrefix: "%", blockOpen: nil, blockClose: nil)
        // Fortran (! for free-form)
        case "fortran", "f77":
            return CommentSyntax(linePrefix: "!", blockOpen: nil, blockClose: nil)
        // Matlab
        case "matlab":
            return CommentSyntax(linePrefix: "%", blockOpen: "%{", blockClose: "%}")
        // ASM
        case "asm":
            return CommentSyntax(linePrefix: ";", blockOpen: nil, blockClose: nil)
        // F#
        case "fsharp":
            return CommentSyntax(linePrefix: "//", blockOpen: "(*", blockClose: "*)")
        // OCaml / SML
        case "caml", "sml":
            return CommentSyntax(linePrefix: nil, blockOpen: "(*", blockClose: "*)")
        // Markdown — use HTML block comment
        case "markdown":
            return CommentSyntax(linePrefix: nil, blockOpen: "<!--", blockClose: "-->")
        // VBS / VB / Pascal
        case "vbscript", "vb":
            return CommentSyntax(linePrefix: "'", blockOpen: nil, blockClose: nil)
        default:
            return CommentSyntax(linePrefix: nil, blockOpen: nil, blockClose: nil)
        }
    }
}
