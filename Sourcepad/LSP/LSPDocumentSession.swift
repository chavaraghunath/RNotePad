// SPDX-License-Identifier: MIT
// Sourcepad — per-document LSP coordinator.
//
// One LSPDocumentSession per EditorPaneViewController. It glues:
//   - LSPServerManager (gets the right client)
//   - LSPDocumentSync (didOpen/didChange/didSave/didClose)
//   - LSPDiagnostics (renders publishDiagnostics)
//   - hover / definition / completion calls (Phase 6 implements hover;
//     Phase 8 adds the rest)
//
// The session subscribes to the manager's delegate stream so it can
// filter notifications by URI.

import AppKit

public final class LSPDocumentSession: LSPServerManagerDelegate {

    public weak var sciView: NSView?
    public let documentURI: String
    public let languageId: String
    public let documentURL: URL
    private let workspaceRoot: URL

    private var client: LSPClient?
    private var sync: LSPDocumentSync?
    public let diagnostics = LSPDiagnostics()

    /// Most recent source we sent to the server. Used to convert LSP
    /// (UTF-16) positions to byte offsets.
    public var lastSyncedSource: String = ""

    public init?(documentURL: URL,
                 workspaceRoot: URL,
                 sciView: NSView) {
        guard let spec = LSPServerRegistry.spec(for: documentURL) else { return nil }
        self.documentURL = documentURL
        self.languageId = spec.languageId
        self.documentURI = LSP.uri(forPath: documentURL.standardizedFileURL.path)
        self.workspaceRoot = workspaceRoot
        self.sciView = sciView
    }

    // MARK: - Lifecycle

    public func start(initialText: String) {
        guard let view = sciView else { return }
        guard let c = LSPServerManager.shared.client(forFileURL: documentURL,
                                                     workspaceRoot: workspaceRoot) else {
            // Server missing — surface the install prompt (once per session).
            if let spec = LSPServerRegistry.spec(for: documentURL) {
                LSPInstaller.shared.promptIfMissing(spec, parentWindow: view.window)
            }
            return
        }
        self.client = c
        // Set up the per-document diagnostic indicators + margin.
        diagnostics.setupIndicators(
            view: view,
            errorColor:   NSColor.systemRed,
            warningColor: NSColor.systemOrange,
            infoColor:    NSColor.systemBlue,
            hintColor:    NSColor.systemGray)
        let sync = LSPDocumentSync(client: c,
                                   documentURI: documentURI,
                                   languageId: languageId)
        self.sync = sync
        self.lastSyncedSource = initialText
        sync.didOpen(text: initialText)

        // Subscribe to publishDiagnostics. The manager has a single delegate
        // slot — we install ourselves while we're active; multiple
        // documents per app needs a hub layer (Phase 8). Phase 6 is the
        // single-doc proof: only the most recently opened LSP-capable
        // document receives diagnostics.
        LSPServerManager.shared.delegate = self
    }

    public func didChange(text: String) {
        lastSyncedSource = text
        sync?.didChangeFullText(text)
    }

    public func didSave(text: String) {
        sync?.didSave(text: text)
    }

    public func close() {
        sync?.didClose()
        diagnostics.clearAll()
        sync = nil
        if LSPServerManager.shared.delegate === self {
            LSPServerManager.shared.delegate = nil
        }
    }

    // MARK: - Hover

    /// Request hover-info at the caret's byte position.
    public func requestHover(atCaretByte byte: Int, completion: @escaping (LSP.Hover?) -> Void) {
        guard let client else { completion(nil); return }
        let pos = LSPDocumentSession.utf16Position(forByteOffset: byte,
                                                   in: lastSyncedSource)
        let params: [String: Any] = [
            "textDocument": ["uri": documentURI],
            "position": pos.dict,
        ]
        client.sendRequest(method: "textDocument/hover", params: params) { result in
            switch result {
            case .success(let payload):
                completion(LSP.Hover(payload))
            case .failure:
                completion(nil)
            }
        }
    }

    // MARK: - Goto definition / references

    /// Returns the array of LSP.Location the server points at. Pyright
    /// returns the symbol's defining range — we'll open that file +
    /// jump to the line.
    public func requestDefinition(atCaretByte byte: Int,
                                  completion: @escaping ([LSP.Location]) -> Void) {
        sendLocationsRequest(method: "textDocument/definition",
                             byte: byte, completion: completion)
    }

    public func requestReferences(atCaretByte byte: Int,
                                  completion: @escaping ([LSP.Location]) -> Void) {
        guard let client else { completion([]); return }
        let pos = LSPDocumentSession.utf16Position(forByteOffset: byte,
                                                   in: lastSyncedSource)
        let params: [String: Any] = [
            "textDocument": ["uri": documentURI],
            "position": pos.dict,
            "context": ["includeDeclaration": true],
        ]
        client.sendRequest(method: "textDocument/references", params: params) { result in
            switch result {
            case .success(let payload):
                completion(LSPDocumentSession.parseLocations(payload))
            case .failure:
                completion([])
            }
        }
    }

    private func sendLocationsRequest(method: String,
                                      byte: Int,
                                      completion: @escaping ([LSP.Location]) -> Void) {
        guard let client else { completion([]); return }
        let pos = LSPDocumentSession.utf16Position(forByteOffset: byte,
                                                   in: lastSyncedSource)
        let params: [String: Any] = [
            "textDocument": ["uri": documentURI],
            "position": pos.dict,
        ]
        client.sendRequest(method: method, params: params) { result in
            switch result {
            case .success(let payload):
                completion(LSPDocumentSession.parseLocations(payload))
            case .failure:
                completion([])
            }
        }
    }

    private static func parseLocations(_ raw: Any?) -> [LSP.Location] {
        if let single = LSP.Location(raw) { return [single] }
        if let arr = raw as? [[String: Any]] {
            return arr.compactMap { LSP.Location($0) }
        }
        return []
    }

    // MARK: - Document symbols

    public struct DocumentSymbol {
        public let name: String
        public let kind: String?
        public let line: Int
        public let column: Int
        public let children: [DocumentSymbol]
    }

    /// Request the outline symbols for this document. Pyright/clangd
    /// return a tree (DocumentSymbol[]); some servers return the flat
    /// SymbolInformation[] form. We handle both.
    public func requestDocumentSymbols(completion: @escaping ([DocumentSymbol]) -> Void) {
        guard let client else { completion([]); return }
        let params: [String: Any] = [
            "textDocument": ["uri": documentURI],
        ]
        client.sendRequest(method: "textDocument/documentSymbol", params: params) { result in
            switch result {
            case .success(let payload):
                completion(LSPDocumentSession.parseDocumentSymbols(payload))
            case .failure:
                completion([])
            }
        }
    }

    private static func parseDocumentSymbols(_ raw: Any?) -> [DocumentSymbol] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap(parseOne)
    }

    private static func parseOne(_ d: [String: Any]) -> DocumentSymbol? {
        let name: String
        let line: Int
        let column: Int
        let kind: String?
        let children: [DocumentSymbol]

        // DocumentSymbol form (recursive).
        if let n = d["name"] as? String,
           let r = LSP.Range_(d["range"] ?? d["selectionRange"]) {
            name = n
            line = r.start.line
            column = r.start.character
            kind = kindName(d["kind"] as? Int)
            if let kids = d["children"] as? [[String: Any]] {
                children = kids.compactMap(parseOne)
            } else {
                children = []
            }
            return DocumentSymbol(name: name, kind: kind, line: line, column: column, children: children)
        }
        // SymbolInformation form (flat).
        if let n = d["name"] as? String,
           let loc = d["location"] as? [String: Any],
           let r = LSP.Range_(loc["range"]) {
            return DocumentSymbol(name: n,
                                  kind: kindName(d["kind"] as? Int),
                                  line: r.start.line,
                                  column: r.start.character,
                                  children: [])
        }
        return nil
    }

    private static func kindName(_ k: Int?) -> String? {
        switch k ?? 0 {
        case 1: return "file"
        case 2: return "module"
        case 3: return "namespace"
        case 4: return "package"
        case 5: return "class"
        case 6: return "method"
        case 7: return "property"
        case 8: return "field"
        case 9: return "constructor"
        case 10: return "enum"
        case 11: return "interface"
        case 12: return "function"
        case 13: return "variable"
        case 14: return "constant"
        case 22: return "struct"
        case 23: return "event"
        case 24: return "operator"
        default: return nil
        }
    }

    // MARK: - Rename

    /// Returns a WorkspaceEdit-style raw dictionary; caller applies it.
    public func requestRename(atCaretByte byte: Int,
                              newName: String,
                              completion: @escaping (Any?) -> Void) {
        guard let client else { completion(nil); return }
        let pos = LSPDocumentSession.utf16Position(forByteOffset: byte,
                                                   in: lastSyncedSource)
        let params: [String: Any] = [
            "textDocument": ["uri": documentURI],
            "position": pos.dict,
            "newName": newName,
        ]
        client.sendRequest(method: "textDocument/rename", params: params) { result in
            switch result {
            case .success(let payload): completion(payload)
            case .failure:              completion(nil)
            }
        }
    }

    // MARK: - LSPServerManagerDelegate

    public func lspManager(_ manager: LSPServerManager,
                           didInitialize client: LSPClient,
                           languageId: String) {
        _ = (manager, client, languageId)
        // We initialized eagerly via start(); nothing to do here.
    }

    public func lspManager(_ manager: LSPServerManager,
                           client: LSPClient,
                           didReceiveNotification method: String,
                           params: Any?) {
        guard method == "textDocument/publishDiagnostics",
              let params = LSP.PublishDiagnosticsParams(params),
              params.uri == documentURI else {
            return
        }
        diagnostics.apply(params.diagnostics, sourceForConversion: lastSyncedSource)
    }

    // MARK: - Byte offset → LSP UTF-16 position

    static func utf16Position(forByteOffset offset: Int, in source: String) -> LSP.Position {
        var byte = 0
        var line = 0
        var col = 0
        for scalar in source.unicodeScalars {
            if byte >= offset {
                return LSP.Position(line: line, character: col)
            }
            let utf8Count = String(scalar).utf8.count
            let utf16Count = scalar.utf16.count
            if scalar == "\n" {
                line += 1
                col = 0
            } else {
                col += utf16Count
            }
            byte += utf8Count
        }
        return LSP.Position(line: line, character: col)
    }
}
