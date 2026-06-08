// SPDX-License-Identifier: MIT
// Sourcepad — Phase 12 ⌘K rewrite sheet.
//
// Flow:
//   1. User selects a span (or runs with no selection → current line).
//   2. ⌘K opens a sheet with an instruction field.
//   3. User types instruction + Enter; MLXService rewrites the
//      selection per the instruction. Result shown as a diff preview.
//   4. Accept → replace the original selection.

import AppKit

public final class RewriteSheet: NSWindowController {

    public static let shared = RewriteSheet()

    public weak var hostEditor: EditorPaneViewController?
    public var originalRange: NSRange = NSRange(location: 0, length: 0)
    public var originalText: String = ""

    private let instructionField = NSTextField()
    private let resultView = NSTextView()
    private let runButton = NSButton(title: "Rewrite", target: nil, action: nil)
    private let acceptButton = NSButton(title: "Accept", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var resultText: String = ""

    private init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Rewrite Selection"
        super.init(window: win)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func buildUI() {
        guard let window else { return }
        let content = window.contentView!

        instructionField.placeholderString = "Instruction (e.g. 'add docstring', 'rename foo to bar')"
        instructionField.bezelStyle = .roundedBezel
        instructionField.translatesAutoresizingMaskIntoConstraints = false

        resultView.isEditable = false
        resultView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let resultScroll = NSScrollView()
        resultScroll.documentView = resultView
        resultScroll.hasVerticalScroller = true
        resultScroll.borderType = .bezelBorder
        resultScroll.translatesAutoresizingMaskIntoConstraints = false

        runButton.target = self
        runButton.action = #selector(runRewrite(_:))
        runButton.translatesAutoresizingMaskIntoConstraints = false
        acceptButton.target = self
        acceptButton.action = #selector(acceptResult(_:))
        acceptButton.isEnabled = false
        acceptButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let buttons = NSStackView(views: [cancelButton, acceptButton, runButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(instructionField)
        content.addSubview(resultScroll)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            instructionField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            instructionField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            instructionField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            instructionField.heightAnchor.constraint(equalToConstant: 28),

            resultScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            resultScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            resultScroll.topAnchor.constraint(equalTo: instructionField.bottomAnchor, constant: 8),
            resultScroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),

            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    public func present(editor: EditorPaneViewController) {
        self.hostEditor = editor
        let sel = SciGetSelectionBytes(editor.view)
        if sel.length > 0 {
            originalRange = sel
            // Pull the selected substring from current text.
            let text = SciGetText(editor.view)
            originalText = RewriteSheet.utf8Substring(text, byteRange: sel)
        } else {
            // No selection — operate on current line.
            let line = editor.currentCursorLine
            let start = SciLineStartByte(editor.view, line)
            let end = SciLineEndByte(editor.view, line)
            originalRange = NSRange(location: start, length: end - start)
            let text = SciGetText(editor.view)
            originalText = RewriteSheet.utf8Substring(text, byteRange: originalRange)
        }
        instructionField.stringValue = ""
        resultView.string = "(original)\n\n\(originalText)"
        resultText = ""
        acceptButton.isEnabled = false
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.instructionField.becomeFirstResponder() }
    }

    private static func utf8Substring(_ s: String, byteRange: NSRange) -> String {
        let bytes = Array(s.utf8)
        let start = max(0, byteRange.location)
        let end = min(bytes.count, byteRange.location + byteRange.length)
        guard start < end else { return "" }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    @objc private func runRewrite(_ sender: Any?) {
        let instruction = instructionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { NSSound.beep(); return }
        let prompt = """
        You are a code-editing assistant. Apply the user's instruction to the snippet and return ONLY the rewritten snippet, no surrounding markdown or commentary.

        --- instruction ---
        \(instruction)
        --- snippet ---
        \(originalText)
        --- rewritten ---
        """
        runButton.isEnabled = false
        resultView.string = "(streaming…)"
        MLXService.shared.complete(prompt: prompt, maxTokens: 512) { [weak self] result in
            guard let self else { return }
            self.runButton.isEnabled = true
            switch result {
            case .success(let text):
                self.resultText = text
                self.resultView.string = text
                self.acceptButton.isEnabled = true
            case .failure(let err):
                self.resultView.string = "(error: \(err))"
            }
        }
    }

    @objc private func acceptResult(_ sender: Any?) {
        guard let editor = hostEditor, !resultText.isEmpty else { return }
        let range = originalRange
        SciBeginUndoAction(editor.view)
        _ = SciReplaceBytesRange(editor.view,
                                 range.location,
                                 range.location + range.length,
                                 resultText)
        SciEndUndoAction(editor.view)
        close()
    }

    @objc private func cancel(_ sender: Any?) {
        close()
    }
}
