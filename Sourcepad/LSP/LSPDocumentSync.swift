// SPDX-License-Identifier: MIT
// Sourcepad — bridges Scintilla edits to LSP textDocument/* messages.
//
// One LSPDocumentSync per (EditorPaneViewController, server). It owns the
// document's monotonic version, sends didOpen on attach, didChange on edit,
// didSave on save, didClose on detach. Phase 6 sends FULL text on each
// change (the simplest correct flow); future phases can switch to
// incremental once we instrument enough to be sure.

import Foundation

public final class LSPDocumentSync {

    public let client: LSPClient
    public let documentURI: String
    public let languageId: String
    private(set) public var version: Int = 1

    public init(client: LSPClient,
                documentURI: String,
                languageId: String) {
        self.client = client
        self.documentURI = documentURI
        self.languageId = languageId
    }

    public func didOpen(text: String) {
        let params: [String: Any] = [
            "textDocument": [
                "uri": documentURI,
                "languageId": languageId,
                "version": version,
                "text": text,
            ],
        ]
        client.sendNotification(method: "textDocument/didOpen", params: params)
    }

    public func didChangeFullText(_ text: String) {
        version += 1
        let params: [String: Any] = [
            "textDocument": [
                "uri": documentURI,
                "version": version,
            ],
            "contentChanges": [
                ["text": text],
            ],
        ]
        client.sendNotification(method: "textDocument/didChange", params: params)
    }

    public func didSave(text: String?) {
        var params: [String: Any] = ["textDocument": ["uri": documentURI]]
        if let text { params["text"] = text }
        client.sendNotification(method: "textDocument/didSave", params: params)
    }

    public func didClose() {
        let params: [String: Any] = [
            "textDocument": ["uri": documentURI],
        ]
        client.sendNotification(method: "textDocument/didClose", params: params)
    }
}
