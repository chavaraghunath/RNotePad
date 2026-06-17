// SPDX-License-Identifier: MIT
// Sourcepad — extract top-level + nested code symbols (functions, classes,
// methods, types) from a source file using Tree-sitter.
//
// Used by the background indexer to populate ProjectIndex.symbols, which in turn
// feeds SourceGraph's symbol nodes. Each language contributes a small mapping of
// tree-sitter node kinds → symbol kinds plus how to locate the name node; adding
// a language is a couple of switch cases once its grammar is vendored.

import Foundation

public struct ExtractedSymbol: Equatable {
    public let name: String
    public let kind: String   // function | method | class | struct | enum | type | interface | constant
    public let line: Int      // 0-based row
    public let col: Int       // 0-based byte column
}

public enum SymbolExtractor {

    /// Parse `source` and return its definitions in document order.
    public static func extract(source: String, language: TreeSitterLanguage) -> [ExtractedSymbol] {
        guard !source.isEmpty,
              let parser = TreeSitterParser(language: language),
              let tree = parser.parse(source: source) else { return [] }
        let bytes = Array(source.utf8)
        var out: [ExtractedSymbol] = []
        walk(tree.rootNode, language: language, bytes: bytes, enclosing: nil, depth: 0, into: &out)
        return out
    }

    private static func walk(_ node: TreeSitterNode,
                             language: TreeSitterLanguage,
                             bytes: [UInt8],
                             enclosing: String?,
                             depth: Int,
                             into out: inout [ExtractedSymbol]) {
        if depth > 64 { return }   // pathological-nesting guard
        let count = node.namedChildCount()
        for i in 0..<count {
            guard let child = node.namedChild(at: i) else { continue }
            let childKind = child.kind
            var enclosingForChildren = enclosing
            if let symKind = language.symbolKind(forNodeKind: childKind, enclosing: enclosing),
               let nameNode = language.nameNode(of: child),
               case let name = nameNode.text(in: bytes), isReasonableName(name) {
                let p = nameNode.startPoint
                let kind = language.refineKind(symKind, name: name)
                out.append(ExtractedSymbol(name: name, kind: kind, line: Int(p.row), col: Int(p.column)))
                enclosingForChildren = childKind
            } else if language.symbolKind(forNodeKind: childKind, enclosing: enclosing) != nil
                        || language.isScopeContainer(childKind) {
                // A definition we couldn't name, or a non-symbol scope (e.g. a
                // Rust `impl` block): still descend with it as the enclosing
                // scope so members get the right kind (method vs function).
                enclosingForChildren = childKind
            }
            walk(child, language: language, bytes: bytes,
                 enclosing: enclosingForChildren, depth: depth + 1, into: &out)
        }
    }

    private static func isReasonableName(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 200 && !s.contains("\n") && !s.contains(" ")
    }
}

// MARK: - Per-language node mapping

extension TreeSitterLanguage {

    /// Map a tree-sitter node kind to a Sourcepad symbol kind, given the nearest
    /// enclosing definition node kind (so e.g. a function inside a class becomes
    /// a method). Returns nil for non-definition nodes.
    func symbolKind(forNodeKind nodeKind: String, enclosing: String?) -> String? {
        switch self {
        case .python:
            switch nodeKind {
            case "class_definition":    return "class"
            case "function_definition": return isClassLike(enclosing) ? "method" : "function"
            default:                    return nil
            }
        case .c:
            switch nodeKind {
            case "function_definition": return "function"
            case "struct_specifier":    return "struct"
            case "union_specifier":     return "struct"
            case "enum_specifier":      return "enum"
            case "type_definition":     return "type"
            default:                    return nil
            }
        case .cpp:
            switch nodeKind {
            case "function_definition": return isClassLike(enclosing) ? "method" : "function"
            case "class_specifier":     return "class"
            case "struct_specifier":    return "struct"
            case "union_specifier":     return "struct"
            case "enum_specifier":      return "enum"
            case "type_definition":     return "type"
            default:                    return nil
            }
        case .javascript:
            switch nodeKind {
            case "function_declaration", "generator_function_declaration": return "function"
            case "class_declaration":   return "class"
            case "method_definition":   return "method"
            default:                    return nil
            }
        case .typescript:
            switch nodeKind {
            case "function_declaration", "generator_function_declaration": return "function"
            case "class_declaration", "abstract_class_declaration": return "class"
            case "method_definition", "method_signature": return "method"
            case "interface_declaration": return "interface"
            case "type_alias_declaration": return "type"
            case "enum_declaration":    return "enum"
            default:                    return nil
            }
        case .go:
            switch nodeKind {
            case "function_declaration": return "function"
            case "method_declaration":   return "method"
            case "type_spec":            return "type"
            default:                     return nil
            }
        case .rust:
            switch nodeKind {
            case "function_item":  return isClassLike(enclosing) ? "method" : "function"
            case "function_signature_item": return "method"   // trait method w/o body
            case "struct_item":    return "struct"
            case "enum_item":      return "enum"
            case "trait_item":     return "interface"
            case "type_item":      return "type"
            case "const_item", "static_item": return "constant"
            default:               return nil
            }
        case .java:
            switch nodeKind {
            case "class_declaration":       return "class"
            case "interface_declaration":   return "interface"
            case "enum_declaration":        return "enum"
            case "record_declaration":      return "class"
            case "method_declaration":      return "method"
            case "constructor_declaration": return "method"
            default:                        return nil
            }
        }
    }

    /// Locate the identifier node that names a definition.
    func nameNode(of node: TreeSitterNode) -> TreeSitterNode? {
        switch self {
        case .python, .javascript, .typescript, .go, .rust, .java:
            return node.child(byFieldName: "name") ?? firstIdentifier(in: node)
        case .c, .cpp:
            // Functions hide their name inside a (possibly pointer/reference)
            // declarator chain; type-like nodes use a plain "name" field.
            if node.kind == "function_definition" {
                return cDeclaratorName(node) ?? firstIdentifier(in: node)
            }
            return node.child(byFieldName: "name") ?? firstIdentifier(in: node)
        }
    }

    /// Walk a C/C++ declarator chain (pointer/reference/parenthesized/function)
    /// down to the identifier that actually names the function.
    private func cDeclaratorName(_ node: TreeSitterNode) -> TreeSitterNode? {
        var cur = node.child(byFieldName: "declarator")
        var hops = 0
        while let c = cur, hops < 24 {
            switch c.kind {
            case "identifier", "field_identifier", "type_identifier",
                 "qualified_identifier", "destructor_name", "operator_name":
                return c
            default:
                cur = c.child(byFieldName: "declarator") ?? c.namedChild(at: 0)
            }
            hops += 1
        }
        return nil
    }

    /// First direct/shallow named identifier child — a generic fallback.
    private func firstIdentifier(in node: TreeSitterNode) -> TreeSitterNode? {
        let count = node.namedChildCount()
        for i in 0..<count {
            guard let c = node.namedChild(at: i) else { continue }
            if c.kind.hasSuffix("identifier") { return c }
        }
        return nil
    }

    /// Refine a symbol kind using the resolved name. Out-of-line C/C++ method
    /// definitions live at file scope but carry a qualified name (`A::m`), so
    /// reclassify those from function → method.
    func refineKind(_ kind: String, name: String) -> String {
        switch self {
        case .c, .cpp:
            return (kind == "function" && name.contains("::")) ? "method" : kind
        default:
            return kind
        }
    }

    /// Non-symbol nodes that still establish a member scope (so functions inside
    /// them are classified as methods).
    func isScopeContainer(_ nodeKind: String) -> Bool {
        switch self {
        case .rust: return nodeKind == "impl_item" || nodeKind == "trait_item"
        default:    return false
        }
    }

    private func isClassLike(_ kind: String?) -> Bool {
        guard let kind else { return false }
        return kind.contains("class") || kind.contains("struct")
            || kind.contains("interface") || kind.contains("protocol")
            || kind.contains("impl") || kind.contains("trait")
    }
}
