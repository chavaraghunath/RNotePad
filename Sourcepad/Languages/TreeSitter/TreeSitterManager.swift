// SPDX-License-Identifier: MIT
// Sourcepad — per-document Tree-sitter state.
//
// One parser + tree pair per EditorPaneViewController. The pane creates
// a TreeSitterManager when its lexer is known, feeds it the full buffer
// on documentContentsDidLoad, and then incrementally edits the tree on
// every modification.
//
// Phase 5 uses this for smart selection only. Later phases:
//   - Symbol extraction → ProjectIndex.symbols (Phase 9 outline panel)
//   - Bracket-pair colorize (Phase 28)
//   - Semantic syntax highlight overlay for languages Lexilla under-styles

import Foundation

public final class TreeSitterManager {

    public let language: TreeSitterLanguage
    private let parser: TreeSitterParser
    private var tree: TreeSitterTree?

    /// Last full source we parsed against. Used to compute row/column for
    /// incremental edits without paying for a second walk.
    private var lastSource: String = ""

    public init?(language: TreeSitterLanguage) {
        guard let p = TreeSitterParser(language: language) else { return nil }
        self.parser = p
        self.language = language
    }

    public var currentTree: TreeSitterTree? { tree }

    // MARK: - Full reparse

    public func reparse(source: String) {
        lastSource = source
        tree = parser.parse(source: source, oldTree: nil)
    }

    // MARK: - Incremental edit
    //
    // Scintilla's SCN_MODIFIED gives us the byte range that changed, the
    // text being inserted, and the count of bytes being deleted. The
    // tree-sitter edit description needs (start, oldEnd, newEnd) byte
    // positions + their row/column equivalents. We compute row/column
    // from the source string we held onto.

    public func applyEditAndReparse(newSource: String,
                                    startByte: Int,
                                    oldEndByte: Int,
                                    newEndByte: Int) {
        guard let oldTree = tree else {
            reparse(source: newSource)
            return
        }
        let startPoint  = TreeSitterManager.point(for: startByte,  in: lastSource)
        let oldEndPoint = TreeSitterManager.point(for: oldEndByte, in: lastSource)
        let newEndPoint = TreeSitterManager.point(for: newEndByte, in: newSource)
        oldTree.applyEdit(
            startByte: UInt32(startByte),
            oldEndByte: UInt32(oldEndByte),
            newEndByte: UInt32(newEndByte),
            startPoint: startPoint,
            oldEndPoint: oldEndPoint,
            newEndPoint: newEndPoint)
        lastSource = newSource
        tree = parser.parse(source: newSource, oldTree: oldTree)
    }

    /// Resolve a byte offset to a tree-sitter (row, column) point.
    /// Linear scan; cheap enough at the edit-event scale we care about.
    /// Column is byte-based, not character-based — that's what Tree-sitter
    /// expects for its incremental edit descriptors.
    private static func point(for byte: Int, in source: String) -> TreeSitterPoint {
        var row: UInt32 = 0
        var col: UInt32 = 0
        var i = 0
        for b in source.utf8 {
            if i >= byte { break }
            if b == 0x0A {  // \n
                row += 1
                col = 0
            } else {
                col += 1
            }
            i += 1
        }
        return TreeSitterPoint(row: row, column: col)
    }

    // MARK: - Smart selection helpers (used by SmartSelection)

    /// Smallest named node enclosing the byte range [start, end).
    public func smallestNamedNode(coveringByteRange start: Int, _ end: Int) -> TreeSitterNode? {
        guard let tree else { return nil }
        return tree.rootNode.smallestNamedDescendant(
            startByte: UInt32(start),
            endByte: UInt32(end))
    }
}
