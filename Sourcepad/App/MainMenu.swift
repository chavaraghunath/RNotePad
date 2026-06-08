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

        // Workspace submenu (Phase 2)
        let workspaceItem = NSMenuItem(title: "Workspace", action: nil, keyEquivalent: "")
        workspaceItem.submenu = WorkspaceMenu.makeMenu()
        fileMenu.addItem(workspaceItem)
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
        // Print loses ⌘P to Quick Open File (VS Code / Sublime convention).
        // Still reachable via the menu (no shortcut).
        fileMenu.addItem(withTitle: "Print…",
                         action: #selector(NSDocument.printDocument(_:)),
                         keyEquivalent: "")

        fileMenu.addItem(.separator())

        // ⌘P — Quick Open File (Phase 3)
        let quickOpen = NSMenuItem(title: "Quick Open File…",
                                   action: Selector(("sourcepadQuickOpenFile:")),
                                   keyEquivalent: "p")
        fileMenu.addItem(quickOpen)

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

        // LSP hover (Phase 6). F1 by editor convention; modifier mask = [].
        let hoverItem = NSMenuItem(title: "Show Hover Info",
                                   action: Selector(("sourcepadShowHover:")),
                                   keyEquivalent: String(UnicodeScalar(UInt32(NSF1FunctionKey))!))
        hoverItem.keyEquivalentModifierMask = []
        editMenu.addItem(hoverItem)

        // Phase 8 — LSP semantic UX
        let gotoDef = NSMenuItem(title: "Go to Definition",
                                 action: Selector(("sourcepadGoToDefinition:")),
                                 keyEquivalent: String(UnicodeScalar(UInt32(NSF12FunctionKey))!))
        gotoDef.keyEquivalentModifierMask = []
        editMenu.addItem(gotoDef)
        let findRefs = NSMenuItem(title: "Find References",
                                  action: Selector(("sourcepadFindReferences:")),
                                  keyEquivalent: String(UnicodeScalar(UInt32(NSF12FunctionKey))!))
        findRefs.keyEquivalentModifierMask = [.shift]
        editMenu.addItem(findRefs)
        let renameSym = NSMenuItem(title: "Rename Symbol…",
                                   action: Selector(("sourcepadRenameSymbol:")),
                                   keyEquivalent: "r")
        renameSym.keyEquivalentModifierMask = [.control, .command]
        editMenu.addItem(renameSym)

        // Smart selection (Phase 5 — Tree-sitter).
        // ⌃⇧→ / ⌃⇧← — expand / shrink to the enclosing syntax node.
        let rightArrow = String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)
        let leftArrow  = String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)
        let expandItem = NSMenuItem(title: "Expand Selection",
                                    action: Selector(("sourcepadExpandSelection:")),
                                    keyEquivalent: rightArrow)
        expandItem.keyEquivalentModifierMask = [.control, .shift]
        editMenu.addItem(expandItem)
        let shrinkItem = NSMenuItem(title: "Shrink Selection",
                                    action: Selector(("sourcepadShrinkSelection:")),
                                    keyEquivalent: leftArrow)
        shrinkItem.keyEquivalentModifierMask = [.control, .shift]
        editMenu.addItem(shrinkItem)
        editMenu.addItem(withTitle: "Go to Line…",
                         action: Selector(("sourcepadGoToLine:")),
                         keyEquivalent: "l")

        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Toggle Line Comment",
                         action: Selector(("sourcepadToggleLineComment:")),
                         keyEquivalent: "/")

        // Sort submenu
        let sort = NSMenuItem(title: "Sort", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu(title: "Sort")
        sort.submenu = sortMenu
        sortMenu.addItem(withTitle: "Ascending",
                         action: Selector(("sourcepadSortLinesAsc:")), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Descending",
                         action: Selector(("sourcepadSortLinesDesc:")), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Unique (Ascending)",
                         action: Selector(("sourcepadSortLinesUnique:")), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Reverse",
                         action: Selector(("sourcepadReverseLines:")), keyEquivalent: "")
        editMenu.addItem(sort)

        // Case submenu
        let caseItem = NSMenuItem(title: "Convert Case", action: nil, keyEquivalent: "")
        let caseMenu = NSMenu(title: "Convert Case")
        caseItem.submenu = caseMenu
        caseMenu.addItem(withTitle: "UPPER CASE",
                         action: Selector(("sourcepadConvertCaseUpper:")), keyEquivalent: "")
        caseMenu.addItem(withTitle: "lower case",
                         action: Selector(("sourcepadConvertCaseLower:")), keyEquivalent: "")
        caseMenu.addItem(withTitle: "Title Case",
                         action: Selector(("sourcepadConvertCaseTitle:")), keyEquivalent: "")
        caseMenu.addItem(withTitle: "camelCase",
                         action: Selector(("sourcepadConvertCaseCamel:")), keyEquivalent: "")
        caseMenu.addItem(withTitle: "snake_case",
                         action: Selector(("sourcepadConvertCaseSnake:")), keyEquivalent: "")
        caseMenu.addItem(withTitle: "kebab-case",
                         action: Selector(("sourcepadConvertCaseKebab:")), keyEquivalent: "")
        editMenu.addItem(caseItem)

        // Bookmark submenu
        let bookmark = NSMenuItem(title: "Bookmark", action: nil, keyEquivalent: "")
        let bookmarkMenu = NSMenu(title: "Bookmark")
        bookmark.submenu = bookmarkMenu
        let bookmarkToggle = NSMenuItem(title: "Toggle on Current Line",
                                        action: Selector(("sourcepadToggleBookmark:")),
                                        keyEquivalent: "\u{F705}")  // F2
        bookmarkToggle.keyEquivalentModifierMask = []
        bookmarkMenu.addItem(bookmarkToggle)
        let bmNext = NSMenuItem(title: "Next Bookmark",
                                action: Selector(("sourcepadJumpNextBookmark:")),
                                keyEquivalent: "\u{F705}")
        bmNext.keyEquivalentModifierMask = [.command]
        bookmarkMenu.addItem(bmNext)
        let bmPrev = NSMenuItem(title: "Previous Bookmark",
                                action: Selector(("sourcepadJumpPreviousBookmark:")),
                                keyEquivalent: "\u{F705}")
        bmPrev.keyEquivalentModifierMask = [.command, .shift]
        bookmarkMenu.addItem(bmPrev)
        bookmarkMenu.addItem(withTitle: "Clear All Bookmarks",
                             action: Selector(("sourcepadClearBookmarks:")),
                             keyEquivalent: "")
        editMenu.addItem(bookmark)

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
        let findInFiles = NSMenuItem(title: "Find in Files…",
                                     action: Selector(("sourcepadOpenFindInFiles:")),
                                     keyEquivalent: "f")
        findInFiles.keyEquivalentModifierMask = [.command, .shift]
        findMenu.addItem(findInFiles)
        editMenu.addItem(find)

        // ⌘⇧P — Command Palette (Phase 3)
        editMenu.addItem(.separator())
        let cmdPalette = NSMenuItem(title: "Command Palette…",
                                    action: Selector(("sourcepadCommandPalette:")),
                                    keyEquivalent: "p")
        cmdPalette.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(cmdPalette)

        // MARK: Notes menu (Phase 19–21)
        let notesItem = NSMenuItem()
        menubar.addItem(notesItem)
        let notesMenu = NSMenu(title: "Notes")
        notesItem.submenu = notesMenu
        let daily = NSMenuItem(title: "Open Today's Daily Note",
                               action: Selector(("sourcepadOpenDailyNote:")),
                               keyEquivalent: "d")
        daily.keyEquivalentModifierMask = [.command, .shift]
        notesMenu.addItem(daily)
        notesMenu.addItem(withTitle: "Follow Wikilink Under Caret",
                          action: Selector(("sourcepadFollowWikilink:")),
                          keyEquivalent: "")
        notesMenu.addItem(withTitle: "Toggle Reading Mode",
                          action: Selector(("sourcepadToggleReadingMode:")),
                          keyEquivalent: "r").keyEquivalentModifierMask = [.command, .shift]
        notesMenu.addItem(.separator())
        notesMenu.addItem(withTitle: "OCR Text from Image…",
                          action: #selector(NativeMacMenuTarget.runOCR(_:)),
                          keyEquivalent: "").target = NativeMacMenuTarget.shared
        notesMenu.addItem(withTitle: "Insert Image…",
                          action: #selector(NativeMacMenuTarget.insertImage(_:)),
                          keyEquivalent: "").target = NativeMacMenuTarget.shared
        notesMenu.addItem(withTitle: "Speak Selection",
                          action: #selector(NativeMacMenuTarget.speakSelection(_:)),
                          keyEquivalent: "").target = NativeMacMenuTarget.shared

        // MARK: AI menu (Phase 10–13)
        let aiItem = NSMenuItem()
        menubar.addItem(aiItem)
        let aiMenu = NSMenu(title: "AI")
        aiItem.submenu = aiMenu
        aiMenu.addItem(withTitle: "Enable AI…",
                       action: #selector(AIMenuTarget.enableAI(_:)),
                       keyEquivalent: "").target = AIMenuTarget.shared
        aiMenu.addItem(withTitle: "Pick Model…",
                       action: #selector(AIMenuTarget.pickModel(_:)),
                       keyEquivalent: "").target = AIMenuTarget.shared
        aiMenu.addItem(.separator())
        let rewrite = NSMenuItem(title: "Rewrite Selection…",
                                 action: Selector(("sourcepadRewriteSelection:")),
                                 keyEquivalent: "k")
        aiMenu.addItem(rewrite)
        let explain = NSMenuItem(title: "Explain Selection",
                                 action: Selector(("sourcepadExplainSelection:")),
                                 keyEquivalent: "e")
        explain.keyEquivalentModifierMask = [.command, .shift]
        aiMenu.addItem(explain)
        let accept = NSMenuItem(title: "Accept Ghost Suggestion",
                                action: Selector(("sourcepadAcceptGhostText:")),
                                keyEquivalent: "\t")
        accept.keyEquivalentModifierMask = []
        aiMenu.addItem(accept)
        aiMenu.addItem(.separator())
        aiMenu.addItem(withTitle: "AI Commit Message",
                       action: Selector(("sourcepadAICommit:")),
                       keyEquivalent: "")
        aiMenu.addItem(withTitle: "Generate Test Stub",
                       action: Selector(("sourcepadGenerateTest:")),
                       keyEquivalent: "")

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

        viewMenu.addItem(.separator())
        // Fold submenu — ⌥⌘[ / ⌥⌘] / ⌥⌘⇧[ / ⌥⌘⇧]
        let fold = NSMenuItem(title: "Fold", action: nil, keyEquivalent: "")
        let foldMenu = NSMenu(title: "Fold")
        fold.submenu = foldMenu
        let foldAtCursor = NSMenuItem(title: "Toggle Fold at Cursor",
                                      action: Selector(("sourcepadToggleFoldAtCursor:")),
                                      keyEquivalent: "[")
        foldAtCursor.keyEquivalentModifierMask = [.command, .option]
        foldMenu.addItem(foldAtCursor)
        let foldAll = NSMenuItem(title: "Fold All",
                                 action: Selector(("sourcepadFoldAll:")),
                                 keyEquivalent: "[")
        foldAll.keyEquivalentModifierMask = [.command, .option, .shift]
        foldMenu.addItem(foldAll)
        let unfoldAll = NSMenuItem(title: "Unfold All",
                                   action: Selector(("sourcepadUnfoldAll:")),
                                   keyEquivalent: "]")
        unfoldAll.keyEquivalentModifierMask = [.command, .option, .shift]
        foldMenu.addItem(unfoldAll)
        viewMenu.addItem(fold)

        // Toggle Preview moves from ⌘⇧P to ⌥⌘P; ⌘⇧P is now Command Palette.
        let previewItem = NSMenuItem(title: "Toggle Preview",
                                     action: #selector(PreviewMenuTarget.showPreview(_:)),
                                     keyEquivalent: "p")
        previewItem.keyEquivalentModifierMask = [.command, .option]
        previewItem.target = PreviewMenuTarget.shared
        viewMenu.addItem(previewItem)

        // View → LSP Status (Phase 7) — dynamic menu rebuilt on open.
        let lspStatus = NSMenuItem(title: "LSP Status",
                                   action: nil,
                                   keyEquivalent: "")
        let lspStatusMenu = NSMenu(title: "LSP Status")
        lspStatusMenu.delegate = LSPStatusMenuTarget.shared
        lspStatus.submenu = lspStatusMenu
        viewMenu.addItem(lspStatus)

        // ⌘T — Go to Symbol in Workspace (Phase 3)
        let gotoSymbol = NSMenuItem(title: "Go to Symbol…",
                                    action: Selector(("sourcepadGoToSymbol:")),
                                    keyEquivalent: "t")
        viewMenu.addItem(gotoSymbol)

        // View > Open As (Phase 4 — placeholders today; real views in 14–17)
        let openAs = NSMenuItem(title: "Open As", action: nil, keyEquivalent: "")
        let openAsMenu = NSMenu(title: "Open As")
        openAs.submenu = openAsMenu
        for (title, mode) in [
            ("Text",            "text"),
            ("Grid (CSV)",      "grid"),
            ("Tree (JSON/YAML)", "tree"),
            ("SQLite Browser",  "sqlite"),
            ("Hex",             "hex"),
            ("Font Preview",    "font"),
            ("PDF Preview",     "pdf"),
        ] {
            let item = NSMenuItem(title: title,
                                  action: Selector(("sourcepadReopenAs:")),
                                  keyEquivalent: "")
            item.representedObject = mode
            openAsMenu.addItem(item)
        }
        viewMenu.addItem(openAs)

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
        // Inspect only meaningful for the Scintilla path.
        guard let pane = editor.editorPane else { NSSound.beep(); return }
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

// MARK: - Workspace menu (Phase 2)

enum WorkspaceMenu {

    /// Build the workspace submenu. Rebuilt lazily; the NSMenu delegate
    /// refreshes the dynamic items each time the menu opens so checkmarks
    /// match the currently-active workspace even after switching.
    static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Workspace")
        menu.delegate = WorkspaceMenuTarget.shared
        WorkspaceMenuTarget.shared.populate(menu)
        return menu
    }
}

@objc final class WorkspaceMenuTarget: NSObject, NSMenuDelegate {
    @objc static let shared = WorkspaceMenuTarget()

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let active = WorkspaceManager.shared.activeWorkspace
        for ws in WorkspaceManager.shared.workspaces {
            let item = NSMenuItem(title: ws.name,
                                  action: #selector(switchWorkspace(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = ws.id
            item.state = (ws.id == active.id) ? .on : .off
            menu.addItem(item)
        }
        if WorkspaceManager.shared.workspaces.count > 0 {
            menu.addItem(.separator())
        }
        let actions: [(String, Selector)] = [
            ("Add Folder to Workspace…", #selector(addFolderToWorkspace(_:))),
            ("New Workspace…",           #selector(newWorkspace(_:))),
            ("Rename Workspace…",        #selector(renameWorkspace(_:))),
            ("Delete Workspace…",        #selector(deleteWorkspace(_:))),
        ]
        for (title, sel) in actions {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let reveal = NSMenuItem(title: "Reveal Workspaces Folder",
                                action: #selector(revealWorkspacesFolder(_:)),
                                keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
    }

    @objc func switchWorkspace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let ws = WorkspaceManager.shared.workspaces.first(where: { $0.id == id }) else { return }
        WorkspaceManager.shared.activeWorkspace = ws
    }

    @objc func addFolderToWorkspace(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add to Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        WorkspaceManager.shared.addRoot(url)
        NotificationCenter.default.post(name: .sourcepadActiveWorkspaceChanged, object: nil)
    }

    @objc func newWorkspace(_ sender: Any?) {
        let alert = NameAlert()
        alert.messageText = "New Workspace"
        alert.informativeText = "Name:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.bezelStyle = .roundedBezel
        alert.accessoryView = field
        alert.field = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        DispatchQueue.main.async { field.becomeFirstResponder() }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = alert.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let ws = Workspace(name: name)
        WorkspaceManager.shared.upsert(ws)
        WorkspaceManager.shared.activeWorkspace = ws
    }

    @objc func renameWorkspace(_ sender: Any?) {
        var ws = WorkspaceManager.shared.activeWorkspace
        let alert = NameAlert()
        alert.messageText = "Rename Workspace"
        alert.informativeText = "New name:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = ws.name
        field.bezelStyle = .roundedBezel
        alert.accessoryView = field
        alert.field = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        DispatchQueue.main.async { field.becomeFirstResponder(); field.selectText(nil) }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = alert.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        ws.name = name
        WorkspaceManager.shared.upsert(ws)
    }

    @objc func deleteWorkspace(_ sender: Any?) {
        let ws = WorkspaceManager.shared.activeWorkspace
        guard WorkspaceManager.shared.workspaces.count > 1 else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete workspace \"\(ws.name)\"?"
        alert.informativeText = "The workspace metadata + its project index are removed. Files in the folder roots are NOT touched."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        WorkspaceManager.shared.delete(ws.id)
    }

    @objc func revealWorkspacesFolder(_ sender: Any?) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("Sourcepad/Workspaces", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}

// MARK: - LSP Status menu (Phase 7)

@objc final class LSPStatusMenuTarget: NSObject, NSMenuDelegate {
    @objc static let shared = LSPStatusMenuTarget()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for spec in LSPServerRegistry.all {
            let installed = spec.locate() != nil
            let title = "\(spec.displayName) — \(installed ? "available" : "not installed")"
            let item = NSMenuItem(title: title,
                                  action: installed ? nil : #selector(installSpec(_:)),
                                  keyEquivalent: "")
            item.representedObject = spec.languageId
            item.target = self
            item.state = installed ? .on : .off
            if installed {
                item.toolTip = "Resolved: \(spec.locate()?.path ?? "")"
            } else {
                item.toolTip = "Install hint: \(spec.installHint)"
            }
            menu.addItem(item)
        }
    }

    @objc func installSpec(_ sender: NSMenuItem) {
        guard let lid = sender.representedObject as? String,
              let spec = LSPServerRegistry.all.first(where: { $0.languageId == lid }) else { return }
        LSPInstaller.shared.promptIfMissing(spec, parentWindow: NSApp.keyWindow)
    }
}

// MARK: - AI menu target (Phase 10)

@objc final class AIMenuTarget: NSObject {
    @objc static let shared = AIMenuTarget()

    @objc func enableAI(_ sender: Any?) {
        // First-run pick + spawn.
        if Preferences.shared.aiModelID == nil {
            _ = ModelManager.promptToPickModel(parent: NSApp.keyWindow)
        }
        guard MLXService.shared.isInstalled else {
            let alert = NSAlert()
            alert.messageText = "mlx-lm not installed"
            alert.informativeText = "Sourcepad needs mlx-lm to run local AI. Install with:\n\n    \(MLXService.shared.installHint ?? "pip install mlx-lm")"
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        MLXService.shared.start()
    }

    @objc func pickModel(_ sender: Any?) {
        _ = ModelManager.promptToPickModel(parent: NSApp.keyWindow)
        // Restart service with new model.
        MLXService.shared.stop()
        if Preferences.shared.aiEnabled {
            MLXService.shared.start()
        }
    }
}

// MARK: - Native Mac menu target (Phase 24)

@objc final class NativeMacMenuTarget: NSObject {
    @objc static let shared = NativeMacMenuTarget()

    @objc func runOCR(_ sender: Any?) {
        LiveTextOCR.runForActiveEditor()
    }

    @objc func insertImage(_ sender: Any?) {
        ContinuityCamera.insertImageReference()
    }

    @objc func speakSelection(_ sender: Any?) {
        SpeakSelection.speakActiveSelection()
    }
}
