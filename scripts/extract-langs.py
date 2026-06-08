#!/usr/bin/env python3
# Extract language → Lexilla-lexer mapping from Notepad++ source files (factual data
# only; no code copied), optionally enrich with VS Code's language extension table,
# then emit a Swift literal table to Rnotepad/Languages/LexerRegistry.swift.
#
# Inputs:
#   - PowerEditor/src/langs.model.xml                                 (ext list per langname)
#   - PowerEditor/src/ScintillaComponent/ScintillaEditView.cpp        (langname → lexerId)
#   - (optional) microsoft/vscode raw URLs                            (modern langs)
#
# Output:
#   - Rnotepad/Languages/LexerRegistry.swift                          (committed)
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
OUT_SWIFT       = ROOT / "Rnotepad" / "Languages"  / "LexerRegistry.swift"
OUT_KEYWORDS_H  = ROOT / "Rnotepad" / "Bridge"     / "KeywordSetsGenerated.h"
OUT_KEYWORDS_M  = ROOT / "Rnotepad" / "Bridge"     / "KeywordSetsGenerated.m"

# We deleted PowerEditor/ to keep the repo MIT-clean. Source files now come
# from upstream NPP's GitHub raw URLs. Data is fact-only (extensions, lexer
# ids, keyword strings — language-spec data); no GPL code is copied.
NPP_RAW = "https://raw.githubusercontent.com/notepad-plus-plus/notepad-plus-plus/master"
LANGS_XML_URL    = f"{NPP_RAW}/PowerEditor/src/langs.model.xml"
SCI_EDIT_CPP_URL = f"{NPP_RAW}/PowerEditor/src/ScintillaComponent/ScintillaEditView.cpp"

CACHE_DIR = Path("/tmp/rnotepad-npp-cache")


def fetch_cached(url, local_name):
    """Download `url` once into /tmp; return the text. Cached per-run so re-runs are fast."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = CACHE_DIR / local_name
    if cache_path.exists():
        return cache_path.read_text(encoding="utf-8", errors="ignore")
    print(f"  fetching {url}", file=sys.stderr)
    with urllib.request.urlopen(url, timeout=30) as r:
        text = r.read().decode("utf-8", errors="replace")
    cache_path.write_text(text, encoding="utf-8")
    return text


def parse_npp_xml():
    """Return list of (langname, [exts])."""
    xml_text = fetch_cached(LANGS_XML_URL, "langs.model.xml")
    root = ET.fromstring(xml_text)
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
    text = fetch_cached(SCI_EDIT_CPP_URL, "ScintillaEditView.cpp")
    # Match rows like: {L"cpp", L"...", L"...", L_CPP, "cpp"}
    pattern = re.compile(
        r'\{\s*L"([^"]+)"\s*,\s*L"[^"]*"\s*,\s*L"[^"]*"\s*,\s*L_\w+\s*,\s*"([^"]+)"\s*\}'
    )
    return dict(pattern.findall(text))


def parse_keyword_sets():
    """Return {langname: {slot_index: 'keywords ...'}}.

    NPP's XML uses these <Keywords name=...> slot names; we map them to
    SCI_SETKEYWORDS slot indices:
        instre1 → 0   (primary keywords)
        instre2 → 1   (secondary keywords)
        type1   → 2
        type2   → 3
        type3   → 4
        type4   → 5
        type5   → 6
        type6   → 7
    Most Lexilla lexers use slots 0-3; some go up to 7.

    Hypertext uses these slot meanings (per Lexilla's LexHTML.cxx):
        0 = HTML tag names
        1 = JavaScript keywords
        2 = VBScript keywords
        3 = Python keywords
        4 = PHP keywords
        5 = SGML keywords
    These correspond to NPP's instre1, instre2, type1, type2, type3, type4 (etc.)
    """
    xml_text = fetch_cached(LANGS_XML_URL, "langs.model.xml")
    root = ET.fromstring(xml_text)
    slot_order = ["instre1", "instre2", "type1", "type2", "type3", "type4", "type5", "type6"]
    result = {}
    for lang in root.iter("Language"):
        name = lang.attrib.get("name")
        if not name:
            continue
        keywords_by_slot = {}
        for kw_elem in lang.findall("Keywords"):
            slot_name = kw_elem.attrib.get("name") or ""
            if slot_name not in slot_order:
                continue
            text = (kw_elem.text or "").strip()
            if not text:
                continue
            slot_idx = slot_order.index(slot_name)
            # Normalise whitespace: keywords are space-separated.
            keywords_by_slot[slot_idx] = " ".join(text.split())
        if keywords_by_slot:
            result[name] = keywords_by_slot
    return result


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
    lines.append("// Rnotepad — file-extension to Lexilla-lexer mapping.")
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


def build_keywords_by_lexer():
    """Combine keyword sets across NPP languages, keyed by Lexilla lexer name.

    Multiple NPP langs can map to the same Lexilla lexer (e.g., c, cpp, java,
    swift, go, javascript all → "cpp"). When that happens we take the entry
    with the most slots filled (preference: cpp's actual cpp entry, etc.).
    """
    lang_to_lexer = parse_lang_to_lexer_map()
    keyword_sets = parse_keyword_sets()

    by_lexer = {}
    for langname, slots in keyword_sets.items():
        lex = lang_to_lexer.get(langname)
        if lex is None:
            continue
        lex = normalize_lexer(lex)
        if not lex:
            continue
        # Prefer langs whose name matches the lexer id (e.g., "cpp" entry for
        # "cpp" lexer over "java" entry for "cpp" lexer). Else take the largest.
        existing = by_lexer.get(lex)
        if existing is None:
            by_lexer[lex] = slots
        else:
            score_new = sum(len(s.split()) for s in slots.values())
            score_old = sum(len(s.split()) for s in existing.values())
            prefer_new = (langname == lex) or (score_new > score_old)
            if prefer_new:
                by_lexer[lex] = slots
    return by_lexer


def _escape_c(s):
    """Escape a string for use inside an Obj-C C string literal."""
    return (s.replace("\\", "\\\\").replace("\"", "\\\"")
             .replace("\n", "\\n").replace("\r", "\\r"))


def emit_keyword_obj_c(by_lexer):
    """Emit KeywordSetsGenerated.h/.m exposing a single C function for the bridge."""
    header = """// SPDX-License-Identifier: MIT
// Rnotepad — keyword sets per Lexilla lexer, generated by
// scripts/extract-langs.py from NPP's langs.model.xml (factual keyword
// strings only, no GPL code copied).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// Returns the per-slot keyword strings for the given Lexilla lexer name,
/// indexed by SCI_SETKEYWORDS slot (0 = primary, 1 = secondary, ...).
/// Empty strings indicate that slot has no keywords. Returns nil for
/// unknown lexers.
NSArray<NSString *> *_Nullable RNPKeywordSetsForLexer(NSString *lexerName);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
"""
    impl_lines = [
        "// SPDX-License-Identifier: MIT",
        "// AUTO-GENERATED by scripts/extract-langs.py. Do not edit by hand.",
        "",
        "#import \"KeywordSetsGenerated.h\"",
        "",
        "NSArray<NSString *> *RNPKeywordSetsForLexer(NSString *lexerName) {",
        "    static NSDictionary<NSString *, NSArray<NSString *> *> *table = nil;",
        "    static dispatch_once_t once;",
        "    dispatch_once(&once, ^{",
        "        table = @{",
    ]

    for lex in sorted(by_lexer):
        slots = by_lexer[lex]
        max_slot = max(slots.keys())
        sets_array = [slots.get(i, "") for i in range(max_slot + 1)]
        impl_lines.append(f'            @"{_escape_c(lex)}": @[')
        for s in sets_array:
            impl_lines.append(f'                @"{_escape_c(s)}",')
        impl_lines.append("            ],")

    impl_lines.extend([
        "        };",
        "    });",
        "    return table[lexerName];",
        "}",
        "",
    ])

    return header, "\n".join(impl_lines)


def main():
    ext_map = build_ext_to_lexer()
    name_map = build_filename_to_lexer()
    swift = emit_swift(ext_map, name_map)
    OUT_SWIFT.parent.mkdir(parents=True, exist_ok=True)
    OUT_SWIFT.write_text(swift, encoding="utf-8")
    print(f"wrote {OUT_SWIFT}")
    print(f"  extensions: {len(ext_map)}")
    print(f"  filenames:  {len(name_map)}")

    by_lexer = build_keywords_by_lexer()
    header, impl = emit_keyword_obj_c(by_lexer)
    OUT_KEYWORDS_H.parent.mkdir(parents=True, exist_ok=True)
    OUT_KEYWORDS_H.write_text(header, encoding="utf-8")
    OUT_KEYWORDS_M.write_text(impl, encoding="utf-8")
    total_kw = sum(sum(len(s.split()) for s in slots.values()) for slots in by_lexer.values())
    print(f"wrote {OUT_KEYWORDS_H}")
    print(f"wrote {OUT_KEYWORDS_M}")
    print(f"  lexers with keyword sets: {len(by_lexer)}")
    print(f"  total keywords:           {total_kw}")


if __name__ == "__main__":
    main()
