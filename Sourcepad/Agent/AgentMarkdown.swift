// SPDX-License-Identifier: MIT
// Sourcepad — lightweight markdown → NSAttributedString for chat bubbles.
//
// Agent replies are markdown-heavy (code fences, inline code, bold, lists).
// Foundation's NSAttributedString(markdown:) handles inline syntax well but
// renders fenced code blocks poorly, so we split on ``` fences ourselves:
// fenced spans become monospaced, background-filled paragraphs; everything
// else goes through the system inline markdown parser. Good enough for a chat
// transcript without pulling in a full markdown engine.

import AppKit

enum AgentMarkdown {

    static func render(_ source: String,
                       baseFont: NSFont,
                       textColor: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 0.5, weight: .regular)

        // Split into alternating non-code / code segments on ``` fences.
        let segments = source.components(separatedBy: "```")
        for (i, seg) in segments.enumerated() {
            let isCode = (i % 2 == 1)
            if isCode {
                out.append(codeBlock(seg, font: monoFont))
            } else if !seg.isEmpty {
                out.append(inline(seg, baseFont: baseFont, textColor: textColor, monoFont: monoFont))
            }
        }
        return out
    }

    // MARK: - Inline (non-fenced) markdown

    private static func inline(_ text: String,
                               baseFont: NSFont,
                               textColor: NSColor,
                               monoFont: NSFont) -> NSAttributedString {
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        opts.allowsExtendedAttributes = true

        let attributed: NSMutableAttributedString
        if let parsed = try? AttributedString(markdown: text, options: opts) {
            attributed = NSMutableAttributedString(parsed)
        } else {
            attributed = NSMutableAttributedString(string: text)
        }

        // Normalize fonts/colors: AttributedString markdown sets intents but not
        // a concrete NSFont. Map bold/italic/inline-code onto our base font.
        let full = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.foregroundColor, value: textColor, range: full)
        attributed.enumerateAttribute(.font, in: full) { value, range, _ in
            let existing = value as? NSFont
            let traits = existing?.fontDescriptor.symbolicTraits ?? []
            if traits.contains(.monoSpace) {
                attributed.addAttribute(.font, value: monoFont, range: range)
            } else {
                var desc = baseFont.fontDescriptor
                var merged: NSFontDescriptor.SymbolicTraits = []
                if traits.contains(.bold) { merged.insert(.bold) }
                if traits.contains(.italic) { merged.insert(.italic) }
                if !merged.isEmpty { desc = desc.withSymbolicTraits(merged) }
                attributed.addAttribute(.font, value: NSFont(descriptor: desc, size: baseFont.pointSize) ?? baseFont,
                                        range: range)
            }
        }
        return attributed
    }

    // MARK: - Fenced code block

    private static func codeBlock(_ raw: String, font: NSFont) -> NSAttributedString {
        // Drop an optional language hint on the first line (```swift).
        var body = raw
        if let nl = raw.firstIndex(of: "\n") {
            let firstLine = raw[raw.startIndex..<nl].trimmingCharacters(in: .whitespaces)
            if !firstLine.isEmpty && !firstLine.contains(" ") && firstLine.count < 20 {
                body = String(raw[raw.index(after: nl)...])
            }
        }
        body = body.trimmingCharacters(in: CharacterSet.newlines)

        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 8
        para.headIndent = 8
        para.tailIndent = -8
        para.paragraphSpacingBefore = 6
        para.paragraphSpacing = 6
        para.lineSpacing = 1

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.textColor.withAlphaComponent(0.06),
            .paragraphStyle: para,
        ]
        return NSAttributedString(string: "\n" + body + "\n", attributes: attrs)
    }
}
