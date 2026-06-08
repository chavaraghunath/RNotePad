#!/usr/bin/env python3
# Extract language → Lexilla-lexer mapping from Notepad++ source files (factual data
# only; no code copied), optionally enrich with VS Code's language extension table,
# then emit a Swift literal table to RNotePad/Languages/LexerRegistry.swift.
#
# Inputs:
#   - PowerEditor/src/langs.model.xml                                 (ext list per langname)
#   - PowerEditor/src/ScintillaComponent/ScintillaEditView.cpp        (langname → lexerId)
#   - (optional) microsoft/vscode raw URLs                            (modern langs)
#
# Output:
#   - RNotePad/Languages/LexerRegistry.swift                          (committed)
#
# Facts are not copyrightable (Feist v. Rural). The NPP sources are GPL but this
# script reads only data points (file-extension strings, lexer-id strings) and
# emits them in a fresh structure. No NPP code is reproduced.

import os
import re
import sys
import json
import urllib.request
import urllib.error
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
LANGS_XML = ROOT / "PowerEditor" / "src" / "langs.model.xml"
SCI_EDIT_CPP = ROOT / "PowerEditor" / "src" / "ScintillaComponent" / "ScintillaEditView.cpp"
OUT_SWIFT = ROOT / "RNotePad" / "Languages" / "LexerRegistry.swift"


def parse_npp_xml():
    """Return list of (langname, [exts])."""
    tree = ET.parse(LANGS_XML)
    root = tree.getroot()
    result = []
    for lang in root.iter("Language"):
        name = lang.attrib.get("name")
        ext = lang.attrib.get("ext", "")
        exts = [e.strip().lower() for e in ext.split() if e.strip()]
        if name and exts:
            result.append((name, exts))
    return result


def parse_lang_to_lexer_map():
    """Return dict mapping NPP langname → Lexilla lexer id."""
    text = SCI_EDIT_CPP.read_text(encoding="utf-8", errors="ignore")
    # Match rows like: {L"cpp", L"...", L"...", L_CPP, "cpp"}
    pattern = re.compile(
        r'\{\s*L"([^"]+)"\s*,\s*L"[^"]*"\s*,\s*L"[^"]*"\s*,\s*L_\w+\s*,\s*"([^"]+)"\s*\}'
    )
    return dict(pattern.findall(text))


# Map NPP/VS Code lexer ids to actual Lexilla lexer names. Lexilla accepts the
# strings we pass to CreateLexer(); this normalises a few aliases.
def normalize_lexer(lex):
    aliases = {
        "null": None,           # plain text — no lexer
        "user": None,
        "searchResult": None,
        "COBOL": "COBOL",
    }
    return aliases.get(lex, lex)


# VS Code identifier → closest Lexilla lexer name. Hand-mapped: VS Code uses
# textmate-style language ids, while Lexilla uses its own short ids. Sources of
# truth: scintilla.org/LexillaDoc.html for the full Lexilla lexer list.
VSCODE_TO_LEXILLA = {
    "typescript": "cpp",          # NPP uses cpp lexer; close enough
    "typescriptreact": "cpp",
    "javascriptreact": "cpp",
    "vue": "hypertext",
    "svelte": "hypertext",
    "astro": "hypertext",
    "mdx": "markdown",
    "graphql": "cpp",
    "dockerfile": "bash",         # Dockerfiles tokenize close enough w/ bash
    "dockercompose": "yaml",
    "groovy": "cpp",
    "scala": "cpp",
    "dart": "cpp",
    "elixir": "cpp",
    "elm": "haskell",
    "clojure": "lisp",
    "fsharp": "caml",
    "ocaml": "caml",
    "crystal": "ruby",
    "julia": "julia",
    "kotlin": "cpp",
    "shellscript": "bash",
    "fish": "bash",
    "zig": "cpp",
    "v": "cpp",
    "solidity": "cpp",
    "vimscript": "cpp",
    "wasm": "cpp",
    "wat": "cpp",
    "nim": "nimrod",
    "purescript": "haskell",
    "wgsl": "cpp",
    "glsl": "cpp",
    "hlsl": "cpp",
    "metal": "cpp",
    "cuda": "cpp",
    "html.handlebars": "hypertext",
    "handlebars": "hypertext",
    "jinja": "hypertext",
    "twig": "hypertext",
    "smarty": "hypertext",
    "blade": "hypertext",
    "ejs": "hypertext",
    "pug": "html",
    "stylus": "css",
    "sass": "css",
    "scss": "css",
    "less": "css",
    "toml": "toml",
    "properties": "props",
    "log": None,
    "diff": "diff",
    "patch": "diff",
    "gitignore": "bash",          # comment-style close enough
    "gitconfig": "props",
    "gitcommit": None,
    "ssh_config": "props",
    "csv": None,
    "tsv": None,
    "dotenv": "bash",
    "env": "bash",
    "ini": "props",
    "vbs": "vb",
    "objective-c": "objc",
    "objective-cpp": "objc",
}


# Curated supplemental extension map for languages VS Code knows about but that
# NPP doesn't list. Sourced from VS Code's bundled extensions (MIT, microsoft/vscode).
VSCODE_EXTRA_EXTS = {
    "typescript":     ["ts", "tsx", "mts", "cts"],
    "vue":            ["vue"],
    "svelte":         ["svelte"],
    "astro":          ["astro"],
    "mdx":            ["mdx"],
    "graphql":        ["graphql", "graphqls", "gql"],
    "dockerfile":     ["dockerfile"],   # also handled by-name below
    "dockercompose":  ["dockerfile"],
    "groovy":         ["groovy", "gvy"],
    "scala":          ["scala", "sc"],
    "dart":           ["dart"],
    "elixir":         ["ex", "exs"],
    "elm":            ["elm"],
    "clojure":        ["clj", "cljs", "cljc", "edn"],
    "fsharp":         ["fs", "fsi", "fsx", "fsscript"],
    "ocaml":          ["ml", "mli"],
    "crystal":        ["cr"],
    "julia":          ["jl"],
    "kotlin":         ["kt", "kts"],
    "shellscript":    ["sh", "bash", "zsh", "command"],
    "fish":           ["fish"],
    "zig":            ["zig"],
    "v":              [],
    "solidity":       ["sol"],
    "vimscript":      ["vim"],
    "wasm":           ["wasm"],
    "wat":            ["wat", "wast"],
    "stylus":         ["styl", "stylus"],
    "sass":           ["sass"],
    "scss":           ["scss"],
    "less":           ["less"],
    "pug":            ["pug", "jade"],
    "handlebars":     ["hbs", "handlebars", "mustache"],
    "ejs":            ["ejs"],
    "blade":          ["blade.php"],
    "twig":           ["twig"],
    "jinja":          ["jinja", "j2", "jinja2"],
    "smarty":         ["tpl"],
    "properties":     ["properties"],
    "diff":           ["diff", "patch"],
    "gitignore":      ["gitignore"],
    "gitconfig":      ["gitconfig"],
    "gitcommit":      ["COMMIT_EDITMSG"],
    "ssh_config":     ["ssh_config"],
    "csv":            ["csv"],
    "tsv":            ["tsv"],
    "dotenv":         ["env"],
    "ini":            ["ini", "cfg", "conf"],
    "vbs":            ["vbs"],
    "objective-c":    ["m"],
    "objective-cpp":  ["mm"],
    "html.handlebars":["html.hbs"],
}


def build_ext_to_lexer():
    """Combine NPP and VS Code data. Returns {ext: (lexerName_or_None, sourceLangId)}."""
    out = {}

    # 1. NPP data
    lang_to_lexer = parse_lang_to_lexer_map()
    for langname, exts in parse_npp_xml():
        lex = lang_to_lexer.get(langname)
        if lex is None:
            continue
        lex = normalize_lexer(lex)
        for ext in exts:
            if ext not in out:
                out[ext] = (lex, langname)

    # 2. VS Code data layered on top (NPP wins on conflict — it's hand-curated)
    for vs_id, exts in VSCODE_EXTRA_EXTS.items():
        lex = VSCODE_TO_LEXILLA.get(vs_id)
        if lex == "_skip":
            continue
        # We allow lex==None for explicit "no lexer" entries (plain text).
        for ext in exts:
            ext_l = ext.lower()
            if ext_l not in out:
                out[ext_l] = (lex, vs_id)

    return out


def build_filename_to_lexer():
    """Special filenames (no extension) → lexer name."""
    return {
        "Dockerfile": "bash",
        "Makefile": "makefile",
        "makefile": "makefile",
        "GNUmakefile": "makefile",
        "Rakefile": "ruby",
        "Gemfile": "ruby",
        "Podfile": "ruby",
        "Fastfile": "ruby",
        "CMakeLists.txt": "cmake",
        ".bashrc": "bash",
        ".zshrc": "bash",
        ".profile": "bash",
        ".gitignore": "bash",
        ".gitconfig": "props",
        ".editorconfig": "props",
        ".env": "bash",
    }


def emit_swift(ext_map, name_map):
    lines = []
    lines.append("// SPDX-License-Identifier: MIT")
    lines.append("// RNotePad — file-extension to Lexilla-lexer mapping.")
    lines.append("// AUTO-GENERATED by scripts/extract-langs.py. Do not edit by hand.")
    lines.append("//")
    lines.append("// Sources (factual data only, no copyrighted expression copied):")
    lines.append("//   - Notepad++ langs.model.xml                       (extension lists)")
    lines.append("//   - Notepad++ ScintillaEditView.cpp _langNameInfoArray (langname→lexerId)")
    lines.append("//   - Curated VS Code language metadata               (modern langs)")
    lines.append("")
    lines.append("import Foundation")
    lines.append("")
    lines.append("public enum LexerRegistry {")
    lines.append("    /// File extension (lowercased, no dot) → Lexilla lexer name.")
    lines.append("    /// `nil` means \"no syntax highlighting\" (plain text).")
    lines.append("    public static let byExtension: [String: String?] = [")

    for ext in sorted(ext_map.keys()):
        lex, src = ext_map[ext]
        val = f"\"{lex}\"" if lex else "nil"
        lines.append(f"        \"{ext}\": {val},   // {src}")
    lines.append("    ]")
    lines.append("")
    lines.append("    /// Full filenames (case-sensitive) → Lexilla lexer name.")
    lines.append("    /// For files with no extension (Dockerfile, Makefile, etc.) and dotfiles.")
    lines.append("    public static let byFilename: [String: String] = [")
    for name in sorted(name_map.keys()):
        lines.append(f"        \"{name}\": \"{name_map[name]}\",")
    lines.append("    ]")
    lines.append("")
    lines.append("    /// Resolve a file URL or filename to a Lexilla lexer name.")
    lines.append("    /// Returns `nil` if the file should be shown as plain text.")
    lines.append("    public static func lexer(for filename: String) -> String? {")
    lines.append("        if let exact = byFilename[filename] { return exact }")
    lines.append("        let lower = filename.lowercased()")
    lines.append("        if let exact = byFilename[lower] { return exact }")
    lines.append("        // Match longest extension suffix (handles e.g. \"foo.blade.php\" → \"blade.php\").")
    lines.append("        let parts = lower.split(separator: \".\")")
    lines.append("        if parts.count >= 3 {")
    lines.append("            let twoDot = parts.suffix(2).joined(separator: \".\")")
    lines.append("            if let hit = byExtension[twoDot] { return hit }")
    lines.append("        }")
    lines.append("        if let dot = lower.lastIndex(of: \".\") {")
    lines.append("            let ext = String(lower[lower.index(after: dot)...])")
    lines.append("            if let hit = byExtension[ext] { return hit }")
    lines.append("        }")
    lines.append("        return nil")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main():
    if not LANGS_XML.exists():
        print(f"error: {LANGS_XML} not found", file=sys.stderr)
        sys.exit(1)
    if not SCI_EDIT_CPP.exists():
        print(f"error: {SCI_EDIT_CPP} not found", file=sys.stderr)
        sys.exit(1)

    ext_map = build_ext_to_lexer()
    name_map = build_filename_to_lexer()
    swift = emit_swift(ext_map, name_map)

    OUT_SWIFT.parent.mkdir(parents=True, exist_ok=True)
    OUT_SWIFT.write_text(swift, encoding="utf-8")

    print(f"wrote {OUT_SWIFT}")
    print(f"  extensions: {len(ext_map)}")
    print(f"  filenames:  {len(name_map)}")


if __name__ == "__main__":
    main()
