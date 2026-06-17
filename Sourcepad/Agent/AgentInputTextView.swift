// SPDX-License-Identifier: MIT
// Sourcepad — the agent panel's multi-line input field.
//
// Return submits; Shift-Return inserts a newline (standard chat ergonomics).
// Grows with content up to a cap, then scrolls.
//
// It also drives the inline `@`/`/` completion popup: as the user types it
// detects an active trigger token under the caret and reports it via
// `onTrigger`. While the popup is open the host wires `isCompletionVisible` /
// `moveCompletion` / `acceptCompletion` / `dismissCompletion`, and arrow / Tab /
// Enter / Esc are routed to the popup instead of editing the text.
//
// Accepted `@`-mentions are inserted as chip attachments (see AgentMention);
// `currentMentions()` reads them back at send time and `displayText()` renders
// them as `@name` for the persisted user message.

import AppKit

public final class AgentInputTextView: NSTextView, NSTextViewDelegate {

    public enum TriggerKind { case mention, slash }

    /// An active completion trigger under the caret.
    public struct Trigger {
        public let kind: TriggerKind
        public let query: String
        /// The text range to replace on accept (the `@query` or `/query` run).
        public let replaceRange: NSRange
    }

    public var onSubmit: (() -> Void)?
    /// Fires with the content height (text + insets) whenever it changes, so the
    /// host can grow the enclosing scroll view to fit, up to a cap.
    public var onHeightChange: ((CGFloat) -> Void)?
    /// Fires whenever the text changes, so the host can refresh a live preview
    /// (e.g. the agent panel's `@`-mention context bar).
    public var onTextChange: (() -> Void)?

    /// Fires when an `@`/`/` trigger is active under the caret (or nil to hide
    /// the popup). The host computes results and shows the popup.
    public var onTrigger: ((Trigger?) -> Void)?

    // Wired by the host so the input can route nav keys to the popup.
    public var isCompletionVisible: (() -> Bool)?
    public var moveCompletion: ((Int) -> Bool)?
    public var acceptCompletion: (() -> Bool)?
    public var dismissCompletion: (() -> Bool)?

    public override func awakeFromNib() { super.awakeFromNib(); delegate = self }

    /// Default attributes for typed (non-chip) text, so inserting a chip never
    /// leaks attachment styling into subsequent typing.
    private var defaultTypingAttributes: [NSAttributedString.Key: Any] {
        [.font: font ?? .systemFont(ofSize: 13),
         .foregroundColor: NSColor.labelColor]
    }

    public override func keyDown(with event: NSEvent) {
        let popupOpen = isCompletionVisible?() ?? false
        if popupOpen {
            switch event.keyCode {
            case 125: if moveCompletion?(1) == true { return }      // ↓
            case 126: if moveCompletion?(-1) == true { return }     // ↑
            case 36, 48: if acceptCompletion?() == true { return }  // Return / Tab
            case 53: if dismissCompletion?() == true { return }     // Esc
            default: break
            }
        }
        // keyCode 36 = Return / Enter. Submit unless Shift (newline).
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
        onTextChange?()
        reportTrigger()
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        // A caret move (no text edit) can move out of / into a trigger token.
        reportTrigger()
    }

    // MARK: - Trigger detection

    private func reportTrigger() {
        onTrigger?(activeTrigger())
    }

    /// Scan back from the caret for an active `@` (anywhere, at a token start)
    /// or `/` (only at the very start of the input) trigger.
    public func activeTrigger() -> Trigger? {
        let sel = selectedRange()
        guard sel.length == 0 else { return nil }   // no completion while selecting
        let s = string as NSString
        let caret = sel.location
        guard caret >= 1, caret <= s.length else { return nil }

        // Slash command: only when the input begins with '/' and the caret is
        // within that first (whitespace-free) token.
        if s.length >= 1, s.character(at: 0) == 0x2F /* '/' */ {
            var end = 1
            while end < s.length, !isWhitespace(s.character(at: end)) { end += 1 }
            if caret <= end {
                let q = s.substring(with: NSRange(location: 1, length: caret - 1))
                return Trigger(kind: .slash, query: q,
                               replaceRange: NSRange(location: 0, length: caret))
            }
        }

        // Mention: find the most recent '@' before the caret that begins a token
        // and has no whitespace between it and the caret.
        var i = caret - 1
        while i >= 0 {
            let ch = s.character(at: i)
            if isWhitespace(ch) { return nil }          // hit a space before any '@'
            if ch == 0x40 /* '@' */ {
                let prevOK: Bool
                if i == 0 { prevOK = true }
                else {
                    let prev = s.character(at: i - 1)
                    prevOK = isWhitespace(prev) || isOpener(prev)
                }
                guard prevOK else { return nil }
                let q = s.substring(with: NSRange(location: i + 1, length: caret - i - 1))
                return Trigger(kind: .mention, query: q,
                               replaceRange: NSRange(location: i, length: caret - i))
            }
            i -= 1
        }
        return nil
    }

    private func isWhitespace(_ u: unichar) -> Bool {
        u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0D || u == 0x0C
    }
    private func isOpener(_ u: unichar) -> Bool {
        // ( [ { ' " ` <
        [0x28, 0x5B, 0x7B, 0x27, 0x22, 0x60, 0x3C].contains(u)
    }

    /// Screen rect of the trigger's start, for anchoring the popup.
    public func caretRectOnScreen(for trigger: Trigger) -> NSRect {
        let r = firstRect(forCharacterRange: NSRange(location: trigger.replaceRange.location, length: 0),
                          actualRange: nil)
        return r
    }

    // MARK: - Chip insertion & readback

    /// Replace `range` with a mention chip + trailing space; place caret after.
    public func insertMentionChip(_ mention: Mention, replacing range: NSRange) {
        guard let storage = textStorage else { return }
        guard shouldChangeText(in: range, replacementString: "") else { return }
        let f = font ?? .systemFont(ofSize: 13)
        let attachment = MentionAttachment(mention: mention, font: f)
        let chip = NSMutableAttributedString(attachment: attachment)
        chip.append(NSAttributedString(string: " ", attributes: defaultTypingAttributes))
        storage.replaceCharacters(in: range, with: chip)
        setSelectedRange(NSRange(location: range.location + chip.length, length: 0))
        typingAttributes = defaultTypingAttributes
        didChangeText()
    }

    /// Replace `range` with plain `text` (used for `/` templates and clearing a
    /// consumed slash command). Places caret at the end of the inserted text.
    public func replace(range: NSRange, with text: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with:
            NSAttributedString(string: text, attributes: defaultTypingAttributes))
        setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
        typingAttributes = defaultTypingAttributes
        didChangeText()
    }

    /// All mention chips currently in the field, in document order.
    public func currentMentions() -> [Mention] {
        guard let storage = textStorage else { return [] }
        var out: [Mention] = []
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let m = (value as? MentionAttachment)?.mention { out.append(m) }
        }
        return out
    }

    /// The field's text with each chip rendered as `@name`, for the persisted
    /// user message and the displayed bubble.
    public func displayText() -> String {
        guard let storage = textStorage else { return string }
        let result = NSMutableString()
        storage.enumerateAttributesAndLongestEffectiveRange(in:
            NSRange(location: 0, length: storage.length)) { attrs, range, _ in
            if let m = (attrs[.attachment] as? MentionAttachment)?.mention {
                result.append("@\(m.displayName)")
            } else {
                result.append((storage.string as NSString).substring(with: range))
            }
        }
        return result as String
    }

    /// Clear text and chips, restoring default typing attributes.
    public func clearAll() {
        textStorage?.setAttributedString(NSAttributedString(string: "", attributes: defaultTypingAttributes))
        typingAttributes = defaultTypingAttributes
        didChangeText()
    }
}

private extension NSAttributedString {
    /// Convenience to walk attributes with their longest effective range.
    func enumerateAttributesAndLongestEffectiveRange(
        in range: NSRange,
        using block: ([NSAttributedString.Key: Any], NSRange, inout Bool) -> Void) {
        var loc = range.location
        let end = range.location + range.length
        var stop = false
        while loc < end && !stop {
            var eff = NSRange(location: 0, length: 0)
            let attrs = attributes(at: loc, longestEffectiveRange: &eff,
                                   in: NSRange(location: loc, length: end - loc))
            block(attrs, eff, &stop)
            loc = eff.location + eff.length
            if eff.length == 0 { break }
        }
    }
}
