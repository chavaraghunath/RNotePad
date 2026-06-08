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
    public let lexerName: String
    private let workspaceRoot: URL

    private var client: LSPClient?
    private var sync: LSPDocumentSync?
    public let diagnostics = LSPDiagnostics()

    /// Most recent source we sent to the server. Used to convert LSP
    /// (UTF-16) positions to byte offsets.
    public var lastSyncedSource: String = ""

    public init?(documentURL: URL,
                 lexerName: String,
                 workspaceRoot: URL,
                 sciView: NSView) {
        guard let spec = LSPServerRegistry.spec(forLexer: lexerName) else { return nil }
        self.lexerName = lexerName
        self.languageId = spec.languageId
        self.documentURI = LSP.uri(forPath: documentURL.standardizedFileURL.path)
        self.workspaceRoot = workspaceRoot
        self.sciView = sciView
    }

    // MARK: - Lifecycle

    public func start(initialText: String) {
        guard let view = sciView else { return }
        guard let c = LSPServerManager.shared.client(forLexer: lexerName,
                                                     workspaceRoot: workspaceRoot) else {
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
