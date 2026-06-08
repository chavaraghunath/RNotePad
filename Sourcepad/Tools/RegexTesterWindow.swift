// SPDX-License-Identifier: MIT
// Sourcepad — Phase 29 regex tester.
//
// A small standalone window with a pattern field + flags + sample text.
// Matches highlight live as the user types. Tests against NSRegularExpression
// (same engine the find bar uses for regex mode).

import AppKit

public final class RegexTesterWindow: NSWindowController, NSTextFieldDelegate {

    public static let shared = RegexTesterWindow()

    private let patternField = NSTextField()
    private let sampleView = NSTextView()
    private let matchesLabel = NSTextField(labelWithString: "0 matches")
    private let ignoreCaseCheck = NSButton(checkboxWithTitle: "Ignore Case", target: nil, action: nil)
    private let multilineCheck  = NSButton(checkboxWithTitle: "Multiline",   target: nil, action: nil)

    private init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                           styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Regex Tester"
        super.init(window: win)
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func buildUI() {
        guard let window, let content = window.contentView else { return }

        patternField.placeholderString = #"Regex pattern, e.g. \w+@\w+\.\w+"#
        patternField.bezelStyle = .roundedBezel
        patternField.delegate = self
        patternField.translatesAutoresizingMaskIntoConstraints = false

        sampleView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        sampleView.isRichText = false
        sampleView.delegate = self as? NSTextViewDelegate
        let sampleScroll = NSScrollView()
        sampleScroll.documentView = sampleView
        sampleScroll.hasVerticalScroller = true
        sampleScroll.borderType = .bezelBorder
        sampleScroll.translatesAutoresizingMaskIntoConstraints = false

        ignoreCaseCheck.target = self
        ignoreCaseCheck.action = #selector(updateMatches)
        multilineCheck.target = self
        multilineCheck.action = #selector(updateMatches)

        matchesLabel.textColor = .secondaryLabelColor
        matchesLabel.translatesAutoresizingMaskIntoConstraints = false

        let flags = NSStackView(views: [ignoreCaseCheck, multilineCheck, NSView(), matchesLabel])
        flags.orientation = .horizontal
        flags.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(patternField)
        content.addSubview(flags)
        content.addSubview(sampleScroll)

        NSLayoutConstraint.activate([
            patternField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            patternField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            patternField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            patternField.heightAnchor.constraint(equalToConstant: 28),

            flags.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            flags.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            flags.topAnchor.constraint(equalTo: patternField.bottomAnchor, constant: 8),
            flags.heightAnchor.constraint(equalToConstant: 20),

            sampleScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            sampleScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            sampleScroll.topAnchor.constraint(equalTo: flags.bottomAnchor, constant: 8),
            sampleScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    public func controlTextDidChange(_ obj: Notification) {
        updateMatches()
    }

    @objc public func updateMatches() {
        let pat = patternField.stringValue
        let sample = sampleView.string
        var opts: NSRegularExpression.Options = []
        if ignoreCaseCheck.state == .on { opts.insert(.caseInsensitive) }
        if multilineCheck.state == .on   { opts.insert(.anchorsMatchLines) }
        guard let re = try? NSRegularExpression(pattern: pat, options: opts) else {
            matchesLabel.stringValue = "invalid pattern"
            sampleView.textStorage?.removeAttribute(.backgroundColor,
                range: NSRange(location: 0, length: (sample as NSString).length))
            return
        }
        let nsRange = NSRange(location: 0, length: (sample as NSString).length)
        let matches = re.matches(in: sample, range: nsRange)
        sampleView.textStorage?.removeAttribute(.backgroundColor, range: nsRange)
        for m in matches {
            sampleView.textStorage?.addAttribute(.backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.4),
                range: m.range)
        }
        matchesLabel.stringValue = "\(matches.count) matches"
    }

    public func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
