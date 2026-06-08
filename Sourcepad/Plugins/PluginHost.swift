// SPDX-License-Identifier: MIT
// Sourcepad — Phase 35 JavaScript plugin sandbox.
//
// JS plugins live in
//   ~/Library/Application Support/Sourcepad/Plugins/<id>/
// each with a manifest.json + entry.js. We run them in a JSContext with
// a curated `sp` global exposing the editor + commands APIs. Long-running
// plugins are not killed automatically (deferred — needs a watchdog).

import AppKit
import JavaScriptCore

public final class PluginHost {

    public static let shared = PluginHost()

    private var contexts: [String: JSContext] = [:]

    private init() {}

    public var pluginsDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = support.appendingPathComponent("Sourcepad/Plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func loadAll() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: pluginsDir,
                                                                  includingPropertiesForKeys: nil)) ?? []
        for dir in urls where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            load(at: dir)
        }
    }

    public func load(at dir: URL) {
        let manifestURL = dir.appendingPathComponent("manifest.json")
        let entryURL = dir.appendingPathComponent("entry.js")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let id = manifest["id"] as? String,
              let script = try? String(contentsOf: entryURL) else { return }

        let ctx = JSContext()!
        ctx.exceptionHandler = { _, exception in
            NSLog("[Sourcepad] Plugin \(id) exception: \(exception?.toString() ?? "?")")
        }
        installAPI(into: ctx, pluginID: id)
        ctx.evaluateScript(script)
        contexts[id] = ctx
        NSLog("[Sourcepad] Plugin loaded: \(id)")
    }

    public func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([pluginsDir])
    }

    // MARK: - Plugin API surface

    private func installAPI(into ctx: JSContext, pluginID: String) {
        let api = JSValue(newObjectIn: ctx)!

        // sp.editor.getText()
        let editor = JSValue(newObjectIn: ctx)!
        let getText: @convention(block) () -> String = {
            guard let pane = PluginHost.activePane() else { return "" }
            return SciGetText(pane.view)
        }
        editor.setObject(unsafeBitCast(getText, to: AnyObject.self),
                         forKeyedSubscript: "getText" as NSString)

        // sp.editor.insertAtCaret(text)
        let insert: @convention(block) (String) -> Void = { text in
            guard let pane = PluginHost.activePane() else { return }
            let sel = SciGetSelectionBytes(pane.view)
            let pos = sel.location == NSNotFound ? 0 : sel.location
            SciInsertTextAt(pane.view, pos, text)
        }
        editor.setObject(unsafeBitCast(insert, to: AnyObject.self),
                         forKeyedSubscript: "insertAtCaret" as NSString)

        api.setObject(editor, forKeyedSubscript: "editor" as NSString)

        // sp.ui.showAlert(message)
        let ui = JSValue(newObjectIn: ctx)!
        let alert: @convention(block) (String) -> Void = { message in
            let a = NSAlert()
            a.messageText = message
            a.runModal()
        }
        ui.setObject(unsafeBitCast(alert, to: AnyObject.self),
                     forKeyedSubscript: "showAlert" as NSString)
        api.setObject(ui, forKeyedSubscript: "ui" as NSString)

        ctx.setObject(api, forKeyedSubscript: "sp" as NSString)
        ctx.setObject(pluginID, forKeyedSubscript: "_pluginID" as NSString)
    }

    private static func activePane() -> EditorPaneViewController? {
        guard let doc = NSDocumentController.shared.currentDocument as? TextDocument,
              let editor = doc.primaryEditorViewController() else { return nil }
        return editor.editorPane
    }
}
