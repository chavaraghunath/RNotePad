// SPDX-License-Identifier: MIT
// RNotePad — application lifecycle.

import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {

    public func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.log("==== launch ====")
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.mainMenu = MainMenu.build()
        NSApp.activate(ignoringOtherApps: true)

        // Open + show an untitled document on launch. We do this explicitly
        // rather than relying on applicationShouldOpenUntitledFile, because:
        //   (a) some launch paths (e.g. running the binary directly) skip it
        //   (b) the default NSDocument display path doesn't reliably bring
        //       our programmatic window controller to the front.
        DispatchQueue.main.async {
            guard let doc = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) else { return }
            for wc in doc.windowControllers {
                wc.showWindow(nil)
                wc.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false  // Handled explicitly in applicationDidFinishLaunching above.
    }

    // Modern (macOS 10.13+) multi-URL open handler.
    @objc public func application(_ application: NSApplication, open urls: [URL]) {
        DebugLog.log("application(_:open:) received \(urls.count) URLs")
        for url in urls { DebugLog.log("  url: \(url.path)") }
        let dc = NSDocumentController.shared
        for url in urls {
            dc.openDocument(withContentsOf: url, display: true) { doc, _, error in
                if let error {
                    DebugLog.log("open failed: \(url.path) — \(error)")
                } else {
                    DebugLog.log("opened: \(url.path) — doc=\(String(describing: doc))")
                }
            }
        }
    }

    // Legacy multi-file open (pre-10.13).
    @objc public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        DebugLog.log("application(_:openFiles:) received \(filenames.count) files")
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        for url in urls { DebugLog.log("  file: \(url.path)") }
        let dc = NSDocumentController.shared
        var pending = urls.count
        for url in urls {
            dc.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { DebugLog.log("openFiles failed: \(url.path) — \(error)") }
                pending -= 1
                if pending == 0 { sender.reply(toOpenOrPrint: .success) }
            }
        }
        if urls.isEmpty { sender.reply(toOpenOrPrint: .success) }
    }

    // Legacy single-file open.
    @objc public func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        DebugLog.log("application(_:openFile:) received \(filename)")
        let url = URL(fileURLWithPath: filename)
        var success = false
        let group = DispatchGroup()
        group.enter()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            success = (error == nil)
            if let error { DebugLog.log("openFile failed: \(url.path) — \(error)") }
            group.leave()
        }
        group.wait()
        return success
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Standard macOS behavior — quit explicitly via Cmd-Q.
    }
}
