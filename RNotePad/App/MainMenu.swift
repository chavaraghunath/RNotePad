// SPDX-License-Identifier: MIT
// RNotePad — programmatic main menu (no .xib).

import AppKit

public enum MainMenu {

    public static func build() -> NSMenu {
        let menubar = NSMenu()

        // MARK: RNotePad menu
        let appItem = NSMenuItem()
        menubar.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        appMenu.addItem(withTitle: "About RNotePad",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide RNotePad",
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
        appMenu.addItem(withTitle: "Quit RNotePad",
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
        fileMenu.addItem(withTitle: "Page Setup…",
                         action: #selector(NSDocument.runPageLayout(_:)),
                         keyEquivalent: "P")
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
        let previewItem = NSMenuItem(title: "Toggle Preview",
                                     action: #selector(PreviewMenuTarget.showPreview(_:)),
                                     keyEquivalent: "p")
        previewItem.keyEquivalentModifierMask = [.command, .shift]
        previewItem.target = PreviewMenuTarget.shared
        viewMenu.addItem(previewItem)

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
