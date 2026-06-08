// SPDX-License-Identifier: MIT
// RNotePad — application lifecycle.

import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Native macOS multi-window tabs.
        NSWindow.allowsAutomaticWindowTabbing = true

        // Build the menu bar before showing any windows.
        NSApp.mainMenu = MainMenu.build()
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return true
    }

    public func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.newDocument(nil)
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Standard macOS behavior — quit explicitly via Cmd-Q.
    }
}
