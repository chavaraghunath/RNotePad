// SPDX-License-Identifier: MIT
// Sourcepad — programmatic main menu (no .xib).

import AppKit

public enum MainMenu {

    public static func build() -> NSMenu {
        let menubar = NSMenu()

        // MARK: Sourcepad menu
        let appItem = NSMenuItem()
        menubar.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        appMenu.addItem(withTitle: "About Sourcepad",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferences…",
                               action: #selector(PreferencesWindowController.showFromMenu(_:)),
                               keyEquivalent: ",")
        prefs.target = PreferencesWindowController.shared
        appMenu.addItem(prefs)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Sourcepad",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Sourcepad",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // MARK: File menu
        let fileItem = NSMenuItem()
        menubar.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu

        fileMenu.addItem(withTitle: "New",
                         action: #selector(NSDocumentController.newDocument(_:)),
                         keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…",
                         action: #selector(NSDocumentController.openDocument(_:)),
                         keyEquivalent: "o")
        let openFolder = NSMenuItem(title: "Open Folder…",
                                    action: Selector(("sourcepadOpenFolder:")),
                                    keyEquivalent: "O")
        openFolder.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(openFolder)
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recent.submenu = recentMenu
        recentMenu.addItem(withTitle: "Clear Menu",
                           action: #selector(NSDocumentController.clearRecentDocuments(_:)),
                           keyEquivalent: "")
        fileMenu.addItem(recent)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")
        let reopen = NSMenuItem(title: "Reopen Closed Tab",
                                action: Selector(("sourcepadReopenClosedTab:")),
                                keyEquivalent: "t")
        reopen.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(reopen)
        fileMenu.addItem(withTitle: "Save",
                         action: #selector(NSDocument.save(_:)),
                         keyEquivalent: "s")
        let saveAs = NSMenuItem(title: "Save As…",
                                action: #selector(NSDocument.saveAs(_:)),
                                keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)
        fileMenu.addItem(withTitle: "Revert to Saved",
                         action: #selector(NSDocument.revertToSaved(_:)),
                         keyEquivalent: "")
        fileMenu.addItem(.separator())
        // No key equivalent — Cmd-Shift-P is reserved for View > Toggle Preview.
        fileMenu.addItem(withTitle: "Page Setup…",
                         action: #selector(NSDocument.runPageLayout(_:)),
                         keyEquivalent: "")
        fileMenu.addItem(withTitle: "Print…",
                         action: #selector(NSDocument.printDocument(_:)),
                         keyEquivalent: "p")

        // MARK: Edit menu (standard responder chain — Scintilla handles via first responder)
        let editItem = NSMenuItem()
        menubar.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo",
                         action: Selector(("undo:")),
                         keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",
                         action: #selector(NSText.cut(_:)),
                         keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")

        editMenu.addItem(.separator())
        let find = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        find.submenu = findMenu

        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Add Cursor to Next Occurrence",
                         action: Selector(("sourcepadAddNextOccurrence:")),
                         keyEquivalent: "d")
        editMenu.addItem(withTitle: "Go to Line…",
                         action: Selector(("sourcepadGoToLine:")),
                         keyEquivalent: "l")

        // Cmd-F / Cmd-E both focus the toolbar search field.
        findMenu.addItem(withTitle: "Find…",
                         action: Selector(("sourcepadFocusToolbarSearch:")),
                         keyEquivalent: "f")
        findMenu.addItem(withTitle: "Search (toolbar)",
                         action: Selector(("sourcepadFocusToolbarSearch:")),
                         keyEquivalent: "e")
        findMenu.addItem(withTitle: "Find and Replace…",
                         action: Selector(("sourcepadShowFindReplace:")),
                         keyEquivalent: "f").keyEquivalentModifierMask = [.command, .option]
        findMenu.addItem(withTitle: "Find Next",
                         action: Selector(("sourcepadFindNext:")),
                         keyEquivalent: "g")
        let findPrev = NSMenuItem(title: "Find Previous",
                                  action: Selector(("sourcepadFindPrevious:")),
                                  keyEquivalent: "g")
        findPrev.keyEquivalentModifierMask = [.command, .shift]
        findMenu.addItem(findPrev)
        editMenu.addItem(find)

        // MARK: View menu — Theme submenu
        let viewItem = NSMenuItem()
        menubar.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu

        let theme = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "Theme")
        theme.submenu = themeMenu
        themeMenu.addItem(makeThemeItem(title: "System", appearance: nil))
        themeMenu.addItem(makeThemeItem(title: "Light", appearance: .aqua))
        themeMenu.addItem(makeThemeItem(title: "Dark", appearance: .darkAqua))
        viewMenu.addItem(theme)

        let lang = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu(title: "Language")
        lang.submenu = langMenu
        for (label, lexerName) in LanguageMenu.entries {
            langMenu.addItem(makeLangItem(title: label, lexer: lexerName))
        }
        viewMenu.addItem(lang)

        viewMenu.addItem(.separator())
        let sidebarItem = NSMenuItem(title: "Toggle Sidebar",
                                     action: Selector(("sourcepadToggleSidebar:")),
                                     keyEquivalent: "0")
        sidebarItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(sidebarItem)

        viewMenu.addItem(.separator())
        // Zoom group: Cmd-+ / Cmd-- / Cmd-0 (Apple-standard).
        // Cmd-0 also toggles sidebar above; we use Cmd-Shift-0 for Actual Size
        // to avoid the conflict, matching Safari / Mail.
        let zoomIn = NSMenuItem(title: "Zoom In",
                                action: Selector(("sourcepadZoomIn:")),
                                keyEquivalent: "+")
        zoomIn.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(zoomIn)
        let zoomOut = NSMenuItem(title: "Zoom Out",
                                 action: Selector(("sourcepadZoomOut:")),
                                 keyEquivalent: "-")
        zoomOut.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(zoomOut)
        let zoomReset = NSMenuItem(title: "Actual Size",
                                   action: Selector(("sourcepadZoomReset:")),
                                   keyEquivalent: "0")
        zoomReset.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(zoomReset)

        viewMenu.addItem(.separator())
        let wrap = NSMenuItem(title: "Word Wrap",
                              action: Selector(("sourcepadToggleWordWrap:")),
                              keyEquivalent: "w")
        wrap.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(wrap)
        viewMenu.addItem(withTitle: "Indent Guides",
                         action: Selector(("sourcepadToggleIndentGuides:")),
                         keyEquivalent: "")
        viewMenu.addItem(withTitle: "Show Invisibles",
                         action: Selector(("sourcepadToggleShowInvisibles:")),
                         keyEquivalent: "")

        let previewItem = NSMenuItem(title: "Toggle Preview",
                                     action: #selector(PreviewMenuTarget.showPreview(_:)),
                                     keyEquivalent: "p")
        previewItem.keyEquivalentModifierMask = [.command, .shift]
        previewItem.target = PreviewMenuTarget.shared
        viewMenu.addItem(previewItem)

        viewMenu.addItem(.separator())
        let inspectItem = NSMenuItem(title: "Inspect Lexer Styles → /tmp/sourcepad.log",
                                     action: #selector(InspectMenuTarget.inspect(_:)),
                                     keyEquivalent: "")
        inspectItem.target = InspectMenuTarget.shared
        viewMenu.addItem(inspectItem)

        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen",
                         action: #selector(NSWindow.toggleFullScreen(_:)),
                         keyEquivalent: "f")

        // MARK: Window menu
        let windowItem = NSMenuItem()
        menubar.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Merge All Windows",
                           action: #selector(NSWindow.mergeAllWindows(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")

        return menubar
    }

    private static func makeThemeItem(title: String, appearance: NSAppearance.Name?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(ThemeMenuTarget.setTheme(_:)), keyEquivalent: "")
        item.target = ThemeMenuTarget.shared
        item.representedObject = appearance?.rawValue
        return item
    }

    private static func makeLangItem(title: String, lexer: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(LangMenuTarget.setLanguage(_:)), keyEquivalent: "")
        item.target = LangMenuTarget.shared
        item.representedObject = lexer  // may be nil for "Plain Text"
        return item
    }
}

enum LanguageMenu {
    /// Short list of common languages. Maps user-visible name → Lexilla lexer
    /// name. nil means "no syntax highlighting".
    static let entries: [(String, String?)] = [
        ("Plain Text", nil),
        ("C / C++ / Java / Swift / Go / JS / TS / Kotlin / Rust / C#", "cpp"),
        ("Python", "python"),
        ("JSON", "json"),
        ("XML", "xml"),
        ("HTML", "hypertext"),
        ("CSS", "css"),
        ("YAML", "yaml"),
        ("Markdown", "markdown"),
        ("SQL", "sql"),
        ("Bash / Shell", "bash"),
        ("PHP", "phpscript"),
        ("Ruby", "ruby"),
        ("Lua", "lua"),
        ("Perl", "perl"),
        ("Makefile", "makefile"),
        ("CMake", "cmake"),
        ("TOML", "toml"),
        ("Diff", "diff"),
        ("Properties / INI", "props"),
        ("Assembly", "asm"),
        ("Pascal", "pascal"),
        ("Haskell", "haskell"),
        ("Lisp / Scheme / Clojure", "lisp"),
        ("R", "r"),
        ("Matlab", "matlab"),
        ("PowerShell", "powershell"),
        ("Batch", "batch"),
        ("LaTeX", "latex"),
        ("VHDL", "vhdl"),
        ("Verilog", "verilog"),
    ]
}

@objc final class LangMenuTarget: NSObject {
    @objc static let shared = LangMenuTarget()

    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let vc = LangMenuTarget.activeEditor() else { return }
        let lexer = sender.representedObject as? String  // nil → plain text
        vc.setLexer(lexer)
    }

    private static func activeEditor() -> EditorViewController? {
        // Most recently active document's first window controller's content VC.
        if let doc = NSDocumentController.shared.currentDocument as? TextDocument,
           let wc = doc.windowControllers.first as? EditorWindowController {
            return wc.editorViewController
        }
        // Fallback: any key-window's content VC.
        if let vc = NSApp.keyWindow?.contentViewController as? EditorViewController {
            return vc
        }
        return nil
    }
}

@objc final class ThemeMenuTarget: NSObject {
    @objc static let shared = ThemeMenuTarget()

    @objc func setTheme(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String {
            NSApp.appearance = NSAppearance(named: NSAppearance.Name(raw))
        } else {
            NSApp.appearance = nil  // follow system
        }
    }
}

@objc final class PreviewMenuTarget: NSObject {
    @objc static let shared = PreviewMenuTarget()

    @objc func showPreview(_ sender: NSMenuItem) {
        guard let editor = activeEditor() else {
            NSSound.beep()
            return
        }
        editor.togglePreview()
    }

    private func activeEditor() -> EditorViewController? {
        if let doc = NSDocumentController.shared.currentDocument as? TextDocument,
           let wc = doc.windowControllers.first as? EditorWindowController {
            return wc.editorViewController
        }
        if let vc = NSApp.keyWindow?.contentViewController as? EditorViewController {
            return vc
        }
        return nil
    }
}

@objc final class InspectMenuTarget: NSObject {
    @objc static let shared = InspectMenuTarget()

    @objc func inspect(_ sender: NSMenuItem) {
        guard let editor = activeEditor() else { NSSound.beep(); return }
        let pane = editor.editorPane
        // Reach into the pane to grab its sciView via Mirror — keeping the
        // bridge boundary clean. Simpler: expose a small accessor on the pane.
        let dump = pane.dumpStyles(maxBytes: 4000)
        DebugLog.log("---- lexer style dump for \(editor.activeLexer ?? "plain") ----\n\(dump)\n---- end dump ----")
        let alert = NSAlert()
        alert.messageText = "Wrote lexer style dump"
        alert.informativeText = "Dump saved to /tmp/sourcepad.log. Open Terminal and run:\n\n  tail -200 /tmp/sourcepad.log"
        alert.runModal()
    }

    private func activeEditor() -> EditorViewController? {
        if let doc = NSDocumentController.shared.currentDocument as? TextDocument,
           let wc = doc.windowControllers.first as? EditorWindowController {
            return wc.editorViewController
        }
        if let vc = NSApp.keyWindow?.contentViewController as? EditorViewController {
            return vc
        }
        return nil
    }
}
