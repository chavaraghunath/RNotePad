// SPDX-License-Identifier: MIT
// RNotePad — application lifecycle.

import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {

    public func applicationDidFinishLaunching(_ notification: Notification) {
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

    // Handle files dropped on the Dock icon or launched via `open foo.txt`.
    public func application(_ application: NSApplication, open urls: [URL]) {
        let dc = NSDocumentController.shared
        for url in urls {
            dc.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSLog("[RNotePad] open failed: \(url.path) — \(error)") }
            }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Standard macOS behavior — quit explicitly via Cmd-Q.
    }
}
