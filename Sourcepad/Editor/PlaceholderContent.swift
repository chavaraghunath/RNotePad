// SPDX-License-Identifier: MIT
// Sourcepad — placeholder EditorContent.
//
// Proves the EditorContent abstraction lets non-Scintilla view modes plug
// into the editor pane without touching the surrounding chrome. Used by:
//   - "Open As > Grid" / "Open As > Tree" / "Open As > Hex" menu items
//     until Phases 14/15/16 ship the real implementations.
//   - Tests that want a known-good non-Scintilla content type.
//
// Renders a centered "<kind> view coming in Phase N" label. Saves through
// untouched bytes if the user picks "Save As" (we keep `currentText`
// intact so accidentally opening a file as Grid doesn't corrupt it).

import AppKit

public final class PlaceholderContent: NSViewController, EditorContent {

    /// What the placeholder claims it would be when real.
    public enum Kind {
        case grid, tree, hex, sqlite, font, pdf

        var description: String {
            switch self {
            case .grid:   return "Grid view"
            case .tree:   return "Tree view"
            case .hex:    return "Hex view"
            case .sqlite: return "SQLite browser"
            case .font:   return "Font preview"
            case .pdf:    return "PDF preview"
            }
        }

        var arrivesInPhase: String {
            switch self {
            case .grid, .tree:  return "Phase 14"
            case .sqlite:       return "Phase 15"
            case .hex, .font:   return "Phase 16"
            case .pdf:          return "Phase 17"
            }
        }
    }

    private let kind: Kind
    private var storedText: String

    public init(kind: Kind, initialText: String) {
        self.kind = kind
        self.storedText = initialText
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        root.wantsLayer = true

        let title = NSTextField(labelWithString: kind.description)
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let detail = NSTextField(labelWithString: "Available in \(kind.arrivesInPhase). Switch back to Text via View → Open As → Text.")
        detail.font = NSFont.systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.lineBreakMode = .byWordWrapping
        detail.usesSingleLineMode = false
        detail.maximumNumberOfLines = 0
        detail.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -40),
        ])

        // Accessibility label so test harnesses can locate the placeholder.
        root.setAccessibilityLabel("Sourcepad Placeholder: \(kind.description)")
        root.setAccessibilityIdentifier("sourcepad.placeholder.\(String(describing: kind))")

        self.view = root
    }

    // MARK: - EditorContent

    public var contentView: NSView { view }

    public var currentText: String { storedText }

    public func replaceWholeBuffer(with text: String) {
        storedText = text
    }

    public var activeLexer: String? { nil }

    public func setLexer(_ name: String?) {
        // Placeholder has no lexer concept; intentional no-op.
        _ = name
    }

    public var caretInfo: EditorCaretInfo {
        EditorCaretInfo(line0Based: 0, column0Based: 0, byteOffset: 0,
                        lineCount: storedText.split(separator: "\n").count,
                        bufferByteCount: storedText.lengthOfBytes(using: .utf8),
                        selectionByteCount: 0)
    }

    public var supportsPreview: Bool { false }

    public func documentContentsDidLoad() {}

    public func markSavePoint() {}

    public func currentCaretByte() -> Int { 0 }

    public var onTextChanged: (() -> Void)?
}
