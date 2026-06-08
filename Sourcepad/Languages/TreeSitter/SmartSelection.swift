// SPDX-License-Identifier: MIT
// Sourcepad — Tree-sitter-powered "smart selection".
//
// ⌃⇧→ : grow the current selection to the smallest enclosing named node
//        that strictly contains it.
// ⌃⇧← : undo one growth step. Selections are stack-tracked so shrinking
//        returns to exactly the same earlier selection (not "smaller
//        named child" — that's a different feature).
//
// The selection stack is per-pane; we don't try to persist across edits.
// An edit that invalidates the byte ranges clears the stack on the next
// growth attempt (the tree changed, so the old ranges no longer mean
// what they meant).

import AppKit

public final class SmartSelection {

    /// Stack of (start, end) byte ranges representing prior selections.
    /// `expand()` pushes onto this stack; `shrink()` pops from it.
    private var history: [(start: Int, end: Int)] = []

    public init() {}

    /// Clear the history. Called when text mutates or selection moves
    /// outside the topmost-stack range.
    public func reset() { history.removeAll() }

    /// Expand to the smallest enclosing named Tree-sitter node strictly
    /// containing the current selection. Returns the new byte range
    /// the caller should apply, or nil if there's nothing larger.
    public func expand(currentStart: Int,
                       currentEnd: Int,
                       in manager: TreeSitterManager) -> (start: Int, end: Int)? {
        // Drop history if the current selection no longer matches the
        // top of the stack — the user moved or typed.
        if let top = history.last, top.start != currentStart || top.end != currentEnd {
            history.removeAll()
        }

        guard var node = manager.smallestNamedNode(coveringByteRange: currentStart, currentEnd) else {
            return nil
        }
        // If smallestNamedNode returned the same range we already have,
        // walk up to a strictly-larger ancestor.
        while !node.isNull
                && Int(node.startByte) == currentStart
                && Int(node.endByte) == currentEnd,
              let parent = node.parent() {
            node = parent
        }
        // No-op if we still don't have a larger node.
        if Int(node.startByte) == currentStart && Int(node.endByte) == currentEnd {
            return nil
        }
        history.append((currentStart, currentEnd))
        return (Int(node.startByte), Int(node.endByte))
    }

    /// Pop the last selection on the stack. Returns nil if the stack
    /// is empty (user has shrunk all the way back to a caret-style
    /// pre-expand state).
    public func shrink() -> (start: Int, end: Int)? {
        return history.popLast()
    }
}
