// SPDX-License-Identifier: MIT
// Sourcepad — per-(workspace root, language) LSP server lifecycle.
//
// One client per (rootURL, languageId). Created lazily when a document
// requests an LSP feature; torn down when the last document for that
// pair closes (Phase 8 — hover/diagnostics/completion will retain a
// document count). Phase 6 keeps clients alive for the app lifetime;
// teardown can be added when it becomes a profiled concern.

import Foundation

public final class LSPServerManager: LSPClientDelegate {

    public static let shared = LSPServerManager()

    public weak var delegate: LSPServerManagerDelegate?

    private struct Key: Hashable {
        let rootPath: String
        let languageId: String
    }

    private var clients: [Key: LSPClient] = [:]
    private var initialized: Set<Key> = []
    private let queue = DispatchQueue(label: "sourcepad.lsp.manager")

    private init() {}

    // MARK: - Client lookup / spawn

    /// Get-or-create a client for the language identified by Sourcepad's
    /// internal lexer name. Returns nil if no LSP server is configured
    /// (or installed) for that language.
    public func client(forLexer lexer: String,
                       workspaceRoot rootURL: URL) -> LSPClient? {
        guard let spec = LSPServerRegistry.spec(forLexer: lexer) else { return nil }
        let rootPath = rootURL.standardizedFileURL.path
        let key = Key(rootPath: rootPath, languageId: spec.languageId)
        return queue.sync {
            if let existing = self.clients[key] { return existing }
            guard let exec = spec.locate() else {
                NSLog("[Sourcepad] LSP \(spec.displayName) not installed; \(spec.installHint)")
                return nil
            }
            let client = LSPClient(serverID: "\(spec.languageId)@\(rootPath.suffix(20))",
                                   executable: exec,
                                   arguments: spec.arguments)
            client.delegate = self
            guard client.start() else { return nil }
            self.clients[key] = client
            self.sendInitialize(client: client, rootURL: rootURL, languageId: spec.languageId)
            return client
        }
    }

    /// Stop and forget every running server.
    public func shutdownAll() {
        let snapshot = queue.sync { Array(self.clients.values) }
        for c in snapshot { c.stop() }
        queue.sync {
            self.clients.removeAll()
            self.initialized.removeAll()
        }
    }

    // MARK: - LSP initialize handshake

    private func sendInitialize(client: LSPClient, rootURL: URL, languageId: String) {
        let rootURI = LSP.uri(forPath: rootURL.standardizedFileURL.path)
        let params: [String: Any] = [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "rootUri": rootURI,
            "workspaceFolders": [
                ["uri": rootURI, "name": rootURL.lastPathComponent],
            ],
            "capabilities": initializeCapabilities(),
            "clientInfo": [
                "name": "Sourcepad",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "0.1.0",
            ],
        ]
        client.sendRequest(method: "initialize", params: params) { [weak self] result in
            switch result {
            case .success:
                // Servers expect us to send `initialized` after the response.
                client.sendNotification(method: "initialized", params: [:])
                self?.queue.async {
                    let key = Key(rootPath: rootURL.standardizedFileURL.path, languageId: languageId)
                    self?.initialized.insert(key)
                }
                self?.delegate?.lspManager(self!, didInitialize: client, languageId: languageId)
            case .failure(let error):
                NSLog("[Sourcepad] LSP \(languageId) initialize failed: \(error.message)")
            }
        }
    }

    private func initializeCapabilities() -> [String: Any] {
        // Phase 6: minimal capabilities — what hover / definition /
        // completion / diagnostics need. Phase 8 expands with signature
        // help, code actions, rename, inlay hints.
        return [
            "textDocument": [
                "synchronization": [
                    "dynamicRegistration": false,
                    "willSave": false,
                    "willSaveWaitUntil": false,
                    "didSave": true,
                ] as [String: Any],
                "hover": [
                    "dynamicRegistration": false,
                    "contentFormat": ["markdown", "plaintext"],
                ] as [String: Any],
                "completion": [
                    "dynamicRegistration": false,
                    "completionItem": [
                        "snippetSupport": false,
                        "documentationFormat": ["markdown", "plaintext"],
                    ] as [String: Any],
                ] as [String: Any],
                "definition": ["dynamicRegistration": false],
                "references":  ["dynamicRegistration": false],
                "publishDiagnostics": [
                    "relatedInformation": true,
                    "versionSupport": false,
                ] as [String: Any],
            ] as [String: Any],
            "workspace": [
                "workspaceFolders": true,
                "configuration": true,
            ] as [String: Any],
        ]
    }

    // MARK: - LSPClientDelegate

    public func lsp(_ client: LSPClient,
                    didReceiveNotification method: String,
                    params: Any?) {
        delegate?.lspManager(self,
                             client: client,
                             didReceiveNotification: method,
                             params: params)
    }

    public func lsp(_ client: LSPClient,
                    didReceiveRequest method: String,
                    id: LSPID,
                    params: Any?) {
        // Phase 6: respond to a few standard server-originated requests
        // so the protocol doesn't deadlock. workspace/configuration is
        // common during init.
        switch method {
        case "workspace/configuration":
            // Return an array of null per requested item.
            if let p = params as? [String: Any],
               let items = p["items"] as? [[String: Any]] {
                client.respond(toID: id, result: Array(repeating: NSNull(), count: items.count))
            } else {
                client.respond(toID: id, result: [])
            }
        case "window/workDoneProgress/create":
            client.respond(toID: id, result: NSNull())
        default:
            // Reply with an empty object; this is friendlier than rejecting,
            // and the server can fall back to defaults.
            client.respond(toID: id, result: NSNull())
        }
    }

    public func lsp(_ client: LSPClient, didLog message: String) {
        // Surface server stderr for debugging; not user-facing.
        NSLog("[Sourcepad] LSP[\(client.serverID)] stderr: \(message)")
    }

    public func lsp(_ client: LSPClient, didExit code: Int32) {
        NSLog("[Sourcepad] LSP[\(client.serverID)] exited with \(code)")
        queue.sync {
            self.clients = self.clients.filter { $0.value !== client }
        }
    }
}

public protocol LSPServerManagerDelegate: AnyObject {
    func lspManager(_ manager: LSPServerManager,
                    didInitialize client: LSPClient,
                    languageId: String)

    func lspManager(_ manager: LSPServerManager,
                    client: LSPClient,
                    didReceiveNotification method: String,
                    params: Any?)
}
