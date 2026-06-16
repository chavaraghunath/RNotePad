// SPDX-License-Identifier: MIT
// Sourcepad — application lifecycle.

import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {

    /// True once the user has committed to quitting (Cmd-Q past its
    /// confirmations). Lets `windowWillClose` tell "user closed the last file"
    /// (→ keep a blank window, VSCode-style) apart from "app is quitting"
    /// (→ let every window close).
    public static private(set) var isTerminating = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.log("==== launch ====")
        NSWindow.allowsAutomaticWindowTabbing = true

        // Apply the saved appearance preference so the user's Light/Dark choice
        // persists across launches. Absent (the default) → NSApp.appearance stays
        // nil, i.e. the app follows the system appearance. Previously the override
        // was only applied live from the Preferences window and never re-applied
        // at launch, so a chosen theme silently reverted on relaunch.
        if let raw = UserDefaults.standard.string(forKey: "Sourcepad.themeOverride"),
           let name = NSAppearance(named: NSAppearance.Name(rawValue: raw)) {
            NSApp.appearance = name
        } else {
            NSApp.appearance = nil
        }

        // Phase 2: prime the active workspace + start the background indexer
        // BEFORE the menu is built so the Workspace submenu picks up the
        // populated workspace list correctly.
        _ = WorkspaceManager.shared.activeWorkspace
        WorkspaceIndexHost.shared.start()

        // Phase 25: menu-bar quick capture.
        QuickCaptureController.shared.install()

        // Phase 26: clipboard ring background polling.
        ClipboardRing.shared.start()

        // Phase 35: discover + load user JS plugins.
        PluginHost.shared.loadAll()

        // Agent panel: probe installed agent CLIs + their models in the
        // background so the panel's pickers are warm by the time it's opened.
        // Never blocks launch.
        AgentRegistry.shared.warmUp()

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
        MLXServer.shared.shutdown()   // stop any running local model server
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

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 1) Warn if a local model download is still in flight — quitting kills it.
        if MLXModelManager.isDownloading {
            let names = MLXModelManager.activeDownloads
                .map { ($0 as NSString).lastPathComponent }
                .joined(separator: ", ")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "A model is still downloading"
            alert.informativeText = "Quitting now will cancel the in-progress download (\(names)). Quit anyway?"
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Keep Downloading")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }

        // From here we're committed to quitting unless the save review is
        // cancelled — so closing windows below should NOT spawn a blank one.
        AppDelegate.isTerminating = true

        // 2) Preserve the standard unsaved-document review (Save / Don't Save /
        //    Cancel). Defining this method overrides NSApplication's default,
        //    so we re-run the document controller's review ourselves.
        NSDocumentController.shared.reviewUnsavedDocuments(
            withAlertTitle: nil, cancellable: true, delegate: self,
            didReviewAllSelector: #selector(documentController(_:didReviewAll:contextInfo:)),
            contextInfo: nil)
        return .terminateLater
    }

    @objc private func documentController(_ controller: NSDocumentController,
                                          didReviewAll allClosed: Bool,
                                          contextInfo: UnsafeMutableRawPointer?) {
        // User cancelled the Save dialog — we're staying. Clear the flag so the
        // blank-window behaviour works again.
        if !allClosed { AppDelegate.isTerminating = false }
        NSApp.reply(toApplicationShouldTerminate: allClosed)
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

    @objc public func sourcepadOpenRegexTester(_ sender: Any?) {
        RegexTesterWindow.shared.show()
    }

    @objc public func sourcepadFormatBuffer(_ sender: Any?) {
        Formatters.formatActiveBuffer()
    }

    @objc public func sourcepadShowClipboardRing(_ sender: Any?) {
        guard let view = NSApp.keyWindow?.contentView else { NSSound.beep(); return }
        ClipboardRing.shared.showPicker(anchor: view)
    }

    @objc public func sourcepadShowBranchPicker(_ sender: Any?) {
        GitBranchUI.showBranchPicker()
    }

    @objc public func sourcepadRevealThemesFolder(_ sender: Any?) {
        ThemeStudio.revealFolder()
    }

    @objc public func sourcepadRevealKeymap(_ sender: Any?) {
        KeymapStudio.revealFile()
    }

    @objc public func sourcepadRevealPluginsFolder(_ sender: Any?) {
        PluginHost.shared.revealFolder()
    }

    @objc public func sourcepadFollowTail(_ sender: Any?) {
        guard let doc = NSDocumentController.shared.currentDocument as? TextDocument,
              let url = doc.fileURL,
              let pane = doc.primaryEditorViewController()?.editorPane else { return }
        TailMode.shared.startFollowing(url, pane: pane)
    }

    @objc public func sourcepadTransform(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let raw = item.representedObject as? String,
              let kind = UtilityTransforms.Kind(rawValue: raw) else { return }
        UtilityTransforms.apply(kind)
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
