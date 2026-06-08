// SPDX-License-Identifier: MIT
// Sourcepad — Phase 25 menu-bar quick-capture.
//
// Adds an NSStatusItem to the menu bar. Clicking it pops a small floating
// panel with a text view; ⌘↵ saves whatever's typed to today's daily
// note (appended) and dismisses the panel.

import AppKit

public final class QuickCaptureController {

    public static let shared = QuickCaptureController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var textView: NSTextView?

    private init() {}

    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = item.button {
            btn.image = NSImage(systemSymbolName: "square.and.pencil",
                                accessibilityDescription: "Sourcepad Quick Capture")
            btn.target = self
            btn.action = #selector(togglePanel(_:))
        }
        self.statusItem = item
    }

    @objc private func togglePanel(_ sender: Any?) {
        if let p = panel, p.isVisible { p.orderOut(nil); return }
        let p = panel ?? makePanel()
        // Position below the status item.
        if let frame = statusItem?.button?.window?.frame {
            let origin = NSPoint(x: frame.midX - 200, y: frame.minY - 240)
            p.setFrameOrigin(origin)
        } else {
            p.center()
        }
        p.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            self.textView?.window?.makeFirstResponder(self.textView)
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
                        styleMask: [.titled, .closable, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Quick Capture"
        p.isFloatingPanel = true
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        let scroll = NSScrollView(frame: tv.frame)
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        p.contentView = scroll
        textView = tv
        panel = p
        // Local key monitor: ⌘↵ → save + dismiss.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === p else { return e }
            if e.modifierFlags.contains(.command) && e.keyCode == 36 {
                self.saveAndDismiss()
                return nil
            }
            return e
        }
        return p
    }

    private func saveAndDismiss() {
        guard let tv = textView else { return }
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { panel?.orderOut(nil); return }
        appendToDailyNote(text)
        tv.string = ""
        panel?.orderOut(nil)
    }

    private func appendToDailyNote(_ text: String) {
        guard let root = WorkspaceManager.shared.activeWorkspace.roots.first else { return }
        let dir = root.appendingPathComponent("Daily", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = dir.appendingPathComponent("\(formatter.string(from: Date())).md")
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let entry = "\n\n## \(time)\n\n\(text)\n"
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
