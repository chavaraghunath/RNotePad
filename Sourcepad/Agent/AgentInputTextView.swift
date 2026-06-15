// SPDX-License-Identifier: MIT
// Sourcepad — the agent panel's multi-line input field.
//
// Return submits; Shift-Return inserts a newline (standard chat ergonomics).
// Grows with content up to a cap, then scrolls.

import AppKit

public final class AgentInputTextView: NSTextView {

    public var onSubmit: (() -> Void)?
    /// Fires with the content height (text + insets) whenever it changes, so the
    /// host can grow the enclosing scroll view to fit, up to a cap.
    public var onHeightChange: ((CGFloat) -> Void)?

    public override func keyDown(with event: NSEvent) {
        // keyCode 36 = Return / Enter.
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    /// Height needed to show all text plus vertical insets.
    public var contentHeight: CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return 28 }
        lm.ensureLayout(for: tc)
        return lm.usedRect(for: tc).height + 2 * textContainerInset.height
    }

    public override func didChangeText() {
        super.didChangeText()
        onHeightChange?(contentHeight)
    }
}
