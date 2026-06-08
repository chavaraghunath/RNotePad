// SPDX-License-Identifier: MIT
// Sourcepad — small modal "Go to Line" panel (⌘L).

import AppKit

public final class GoToLinePanel: NSObject, NSTextFieldDelegate {

    public static let shared = GoToLinePanel()

    private var panel: NSPanel?
    private var field: NSTextField?
    private var rangeLabel: NSTextField?
    private var onSubmit: ((Int) -> Void)?

    public func show(in window: NSWindow, totalLines: Int, onSubmit: @escaping (Int) -> Void) {
        self.onSubmit = onSubmit
        if panel == nil { buildPanel() }
        rangeLabel?.stringValue = "1…\(max(1, totalLines))"
        field?.stringValue = ""
        guard let panel else { return }
        // Centre on the parent window.
        let parentFrame = window.frame
        let p = NSPoint(
            x: parentFrame.midX - panel.frame.width / 2,
            y: parentFrame.midY - panel.frame.height / 2 + 80)
        panel.setFrameOrigin(p)
        window.beginSheet(panel)
        field?.becomeFirstResponder()
    }

    private func buildPanel() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 110),
                        styleMask: [.titled, .closable],
                        backing: .buffered, defer: false)
        p.title = "Go to Line"
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = false
        p.hidesOnDeactivate = false

        let header = NSTextField(labelWithString: "Line number:")
        header.font = NSFont.systemFont(ofSize: 13)
        header.translatesAutoresizingMaskIntoConstraints = false

        let f = NSTextField()
        f.bezelStyle = .roundedBezel
        f.placeholderString = "1"
        f.alignment = .right
        f.delegate = self
        f.target = self
        f.action = #selector(submitTapped(_:))
        f.translatesAutoresizingMaskIntoConstraints = false
        self.field = f

        let range = NSTextField(labelWithString: "")
        range.font = NSFont.systemFont(ofSize: 11)
        range.textColor = .secondaryLabelColor
        range.translatesAutoresizingMaskIntoConstraints = false
        self.rangeLabel = range

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped(_:)))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1B}"  // Esc
        cancel.translatesAutoresizingMaskIntoConstraints = false

        let go = NSButton(title: "Go", target: self, action: #selector(submitTapped(_:)))
        go.bezelStyle = .rounded
        go.keyEquivalent = "\r"
        go.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)
        content.addSubview(f)
        content.addSubview(range)
        content.addSubview(cancel)
        content.addSubview(go)
        p.contentView = content

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            f.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            f.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            f.widthAnchor.constraint(equalToConstant: 120),

            range.centerYAnchor.constraint(equalTo: f.centerYAnchor),
            range.leadingAnchor.constraint(equalTo: f.trailingAnchor, constant: 10),

            go.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            go.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            cancel.bottomAnchor.constraint(equalTo: go.bottomAnchor),
            cancel.trailingAnchor.constraint(equalTo: go.leadingAnchor, constant: -8),
        ])

        self.panel = p
    }

    @objc private func submitTapped(_ sender: Any?) {
        guard let raw = field?.stringValue, let n = Int(raw.trimmingCharacters(in: .whitespaces)) else {
            close()
            return
        }
        onSubmit?(n)
        close()
    }

    @objc private func cancelTapped(_ sender: Any?) { close() }

    private func close() {
        guard let panel else { return }
        if let parent = panel.sheetParent {
            parent.endSheet(panel)
        } else {
            panel.orderOut(nil)
        }
    }
}
