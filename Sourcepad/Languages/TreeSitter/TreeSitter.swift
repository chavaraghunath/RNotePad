// SPDX-License-Identifier: MIT
// Sourcepad — Swift wrapper around the Tree-sitter C API.
//
// Goals:
//   - Type-safe, ARC-managed wrappers for TSParser / TSTree.
//   - Value-type TreeSitterNode that mirrors TSNode (which is itself a
//     struct, so this is just a Swift-side convenience).
//   - No raw C pointers leak out of this file.
//
// Reference for the C API: tree-sitter/lib/include/tree_sitter/api.h.
// Each grammar's `tree_sitter_<name>()` entry point is declared in
// tree-sitter/grammars/grammars.h (added to the bridging header).

import Foundation

// MARK: - Language registry

public enum TreeSitterLanguage: String, CaseIterable {
    case python
    case c
    case cpp
    case javascript
    case typescript
    case go
    case rust
    case java

    /// Resolve to the Tree-sitter language pointer the grammar's entry
    /// point returns. Each entry is declared C-side in
    /// tree-sitter/grammars/grammars.h. We surface as OpaquePointer
    /// because Swift's bridging-header importer doesn't reliably expose
    /// forward-declared C struct types like TSLanguage.
    var pointer: OpaquePointer? {
        switch self {
        case .python:     return tree_sitter_python()
        case .c:          return tree_sitter_c()
        case .cpp:        return tree_sitter_cpp()
        case .javascript: return tree_sitter_javascript()
        case .typescript: return tree_sitter_typescript()
        case .go:         return tree_sitter_go()
        case .rust:       return tree_sitter_rust()
        case .java:       return tree_sitter_java()
        }
    }

    /// Map a Sourcepad lexer name to a Tree-sitter language. NOTE: Lexilla
    /// collapses most C-like languages onto the single "cpp" lexer, so this is
    /// only reliable for Python; everything else should select by file
    /// extension via `forFilename`.
    public static func fromLexer(_ lexer: String?) -> TreeSitterLanguage? {
        switch lexer {
        case "python": return .python
        default:       return nil
        }
    }

    /// Select a grammar by file extension — the reliable path for symbol
    /// extraction, since Lexilla lexer names are too coarse. Returns nil for
    /// extensions we don't have a grammar for.
    public static func forFilename(_ name: String) -> TreeSitterLanguage? {
        switch (name as NSString).pathExtension.lowercased() {
        case "py", "pyi", "pyw":                     return .python
        case "c":                                     return .c
        case "cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "h++", "cppm", "ipp", "h", "inl":
                                                      return .cpp
        case "js", "jsx", "mjs", "cjs":              return .javascript
        case "ts", "mts", "cts", "tsx":              return .typescript
        case "go":                                    return .go
        case "rs":                                    return .rust
        case "java":                                  return .java
        default:                                      return nil
        }
    }
}

// MARK: - Parser (RAII around TSParser*)

public final class TreeSitterParser {

    private var raw: OpaquePointer?
    private(set) public var language: TreeSitterLanguage

    public init?(language: TreeSitterLanguage) {
        guard let langPtr = language.pointer,
              let parser = ts_parser_new() else { return nil }
        guard ts_parser_set_language(parser, langPtr) else {
            ts_parser_delete(parser)
            return nil
        }
        self.raw = parser
        self.language = language
    }

    deinit {
        if let raw { ts_parser_delete(raw) }
    }

    /// Parse `source` from scratch (or, if `oldTree` is supplied, by
    /// reusing its parse state — see TreeSitterTree.applyEdit for the
    /// incremental flow).
    public func parse(source: String, oldTree: TreeSitterTree? = nil) -> TreeSitterTree? {
        guard let raw else { return nil }
        let utf8 = Array(source.utf8)
        let result = utf8.withUnsafeBufferPointer { buf -> OpaquePointer? in
            return ts_parser_parse_string(raw, oldTree?.raw,
                                          buf.baseAddress, UInt32(buf.count))
        }
        guard let tree = result else { return nil }
        return TreeSitterTree(raw: tree)
    }
}

// MARK: - Tree (RAII around TSTree*)

public final class TreeSitterTree {

    fileprivate var raw: OpaquePointer

    fileprivate init(raw: OpaquePointer) {
        self.raw = raw
    }

    deinit {
        ts_tree_delete(raw)
    }

    public var rootNode: TreeSitterNode {
        TreeSitterNode(raw: ts_tree_root_node(raw))
    }

    /// Apply an edit description in preparation for the next incremental
    /// parse. Mirrors TSInputEdit; callers fill in old / new byte ranges
    /// + row+column points. Tree-sitter then knows which subtrees to
    /// reuse on the next parse() call.
    public func applyEdit(startByte: UInt32,
                          oldEndByte: UInt32,
                          newEndByte: UInt32,
                          startPoint: TreeSitterPoint,
                          oldEndPoint: TreeSitterPoint,
                          newEndPoint: TreeSitterPoint) {
        var edit = TSInputEdit(
            start_byte: startByte,
            old_end_byte: oldEndByte,
            new_end_byte: newEndByte,
            start_point: TSPoint(row: startPoint.row, column: startPoint.column),
            old_end_point: TSPoint(row: oldEndPoint.row, column: oldEndPoint.column),
            new_end_point: TSPoint(row: newEndPoint.row, column: newEndPoint.column))
        ts_tree_edit(raw, &edit)
    }
}

// MARK: - Node (value-type wrapper around TSNode)

public struct TreeSitterNode {

    /// The underlying C node value. Exposed so this file's helpers can
    /// pass it back to C; external code should use the Swift methods.
    var raw: TSNode

    init(raw: TSNode) { self.raw = raw }

    public var isNull: Bool { ts_node_is_null(raw) }

    public var startByte: UInt32 { ts_node_start_byte(raw) }
    public var endByte: UInt32   { ts_node_end_byte(raw) }

    /// Byte range as a closed-open interval, suitable for Scintilla's
    /// byte-based selection API.
    public var byteRange: Range<Int> {
        Int(startByte)..<Int(endByte)
    }

    /// Node kind (e.g. "function_definition" for Python).
    public var kind: String {
        guard let c = ts_node_type(raw) else { return "" }
        return String(cString: c)
    }

    public var isNamed: Bool { ts_node_is_named(raw) }

    public func parent() -> TreeSitterNode? {
        let p = ts_node_parent(raw)
        return ts_node_is_null(p) ? nil : TreeSitterNode(raw: p)
    }

    public func namedChildCount() -> Int { Int(ts_node_named_child_count(raw)) }

    public func namedChild(at index: Int) -> TreeSitterNode? {
        let c = ts_node_named_child(raw, UInt32(index))
        return ts_node_is_null(c) ? nil : TreeSitterNode(raw: c)
    }

    /// Smallest named descendant whose byte range covers [start, end).
    public func smallestNamedDescendant(startByte: UInt32, endByte: UInt32) -> TreeSitterNode? {
        let d = ts_node_named_descendant_for_byte_range(raw, startByte, endByte)
        return ts_node_is_null(d) ? nil : TreeSitterNode(raw: d)
    }

    /// 0-based (row, column) of the node's start. Column is a byte offset.
    public var startPoint: TreeSitterPoint {
        let p = ts_node_start_point(raw)
        return TreeSitterPoint(row: p.row, column: p.column)
    }

    /// The child stored under a grammar field name (e.g. "name" on a
    /// function/class definition). nil if the field is absent.
    public func child(byFieldName field: String) -> TreeSitterNode? {
        let c = field.utf8CString.withUnsafeBufferPointer { buf in
            ts_node_child_by_field_name(raw, buf.baseAddress, UInt32(field.utf8.count))
        }
        return ts_node_is_null(c) ? nil : TreeSitterNode(raw: c)
    }

    /// The node's source text, sliced from the original UTF-8 bytes.
    public func text(in bytes: [UInt8]) -> String {
        let lo = Int(startByte), hi = Int(endByte)
        guard lo >= 0, hi <= bytes.count, lo < hi else { return "" }
        return String(decoding: bytes[lo..<hi], as: UTF8.self)
    }
}

// MARK: - Convenience: Point

public struct TreeSitterPoint {
    public var row: UInt32
    public var column: UInt32
    public init(row: UInt32, column: UInt32) {
        self.row = row
        self.column = column
    }
}
