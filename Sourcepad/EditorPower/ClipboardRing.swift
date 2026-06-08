// SPDX-License-Identifier: MIT
// Sourcepad — Phase 26 clipboard ring.
//
// Last 20 distinct strings copied to the system pasteboard. ⌘⇧V cycles
// through them via a popover-style picker.

import AppKit

public final class ClipboardRing {

    public static let shared = ClipboardRing()

    private var entries: [String] = []
    private let max = 20
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?

    private init() {}

    /// Start polling the system pasteboard. NSPasteboard doesn't expose a
    /// notification API; 0.6s polling is cheap and barely noticeable.
    public func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    public func stop() {
        timer?.invalidate(); timer = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        if let s = pb.string(forType: .string), !s.isEmpty {
            entries.removeAll(where: { $0 == s })
            entries.insert(s, at: 0)
            if entries.count > max { entries = Array(entries.prefix(max)) }
        }
    }

    public func showPicker(anchor: NSView) {
        guard !entries.isEmpty else { NSSound.beep(); return }
        let menu = NSMenu()
        for entry in entries {
            let label = String(entry.prefix(80)).replacingOccurrences(of: "\n", with: "⏎")
            let item = NSMenuItem(title: label,
                                  action: #selector(pickEntry(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = entry
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
    }

    @objc private func pickEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }
}
