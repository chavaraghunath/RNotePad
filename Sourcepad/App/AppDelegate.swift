// SPDX-License-Identifier: MIT
// Sourcepad — application lifecycle.

import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {

    public func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.log("==== launch ====")
        NSWindow.allowsAutomaticWindowTabbing = true

        // Phase 2: prime the active workspace + start the background indexer
        // BEFORE the menu is built so the Workspace submenu picks up the
        // populated workspace list correctly.
        _ = WorkspaceManager.shared.activeWorkspace
        WorkspaceIndexHost.shared.start()

        // Phase 25: menu-bar quick capture.
        QuickCaptureController.shared.install()

        NSApp.mainMenu = MainMenu.build()
        NSApp.activate(ignoringOtherApps: true)

        // Open + show an untitled document on launch. We do this explicitly
        // rather than relying on applicationShouldOpenUntitledFile, because:
        //   (a) some launch paths (e.g. running the binary directly) skip it
        //   (b) the default NSDocument display path doesn't reliably bring
        //       our programmatic window controller to the front.
        DispatchQueue.main.async {
            // Skip if files were already opened via Apple Events (launch-with-file).
            if !NSDocumentController.shared.documents.isEmpty { return }
            // Try to restore the previous session.
            if SessionRestore.shared.tryRestore() { return }
            // No session to restore — fall back to an untitled document.
            guard let doc = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) else { return }
            for wc in doc.windowControllers {
                wc.showWindow(nil)
                wc.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        SessionRestore.shared.saveCurrentSession()
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

    // MARK: - Palettes (Phase 3)
    //
    // Live on AppDelegate (not a per-window VC) because palettes are global.
    // The responder chain reaches AppDelegate as a last resort.

    @objc public func sourcepadQuickOpenFile(_ sender: Any?) {
        PaletteWindowController.shared.present(provider: FilePaletteProvider())
    }

    @objc public func sourcepadCommandPalette(_ sender: Any?) {
        PaletteWindowController.shared.present(provider: CommandPaletteProvider())
    }

    @objc public func sourcepadGoToSymbol(_ sender: Any?) {
        PaletteWindowController.shared.present(provider: SymbolPaletteProvider())
    }

    // MARK: - View > Open As (Phase 4)
    //
    // Sets EditorContentFactory.nextOpenOverride and re-opens the current
    // document. The factory consumes the override and resets it so the
    // next file picks up its default view again.

    @objc public func sourcepadReopenAs(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let raw = item.representedObject as? String,
              let mode = EditorContentMode(rawValue: raw) else {
            NSSound.beep(); return
        }
        guard let doc = NSDocumentController.shared.currentDocument as? TextDocument,
              let url = doc.fileURL else {
            NSSound.beep(); return
        }
        EditorContentFactory.nextOpenOverride = mode

        // Close the current document and re-open the same URL. NSDocument's
        // built-in flow handles the user-confirmation if the buffer is
        // dirty; for placeholders the buffer is read-only anyway.
        doc.close()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSLog("[Sourcepad] reopen-as failed: \(error)") }
        }
    }
}
