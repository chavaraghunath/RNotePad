// SPDX-License-Identifier: MIT
// Sourcepad — Phase 27 Edit > Transform > … utility transforms.
//
// Each transform reads the current selection (or full buffer), pipes
// through a small pure-Swift function, and replaces the selection.

import AppKit
import CryptoKit

public enum UtilityTransforms {

    public enum Kind: String {
        case base64Encode  = "Base64 Encode"
        case base64Decode  = "Base64 Decode"
        case urlEncode     = "URL Encode"
        case urlDecode     = "URL Decode"
        case md5
        case sha256
        case uuid          = "Generate UUID"
        case timestampNow  = "Insert Timestamp (now)"
        case toUpper       = "UPPER"
        case toLower       = "lower"
    }

    public static func apply(_ kind: Kind) {
        guard let doc = NSDocumentController.shared.currentDocument as? TextDocument,
              let pane = doc.primaryEditorViewController()?.editorPane else { return }
        let sel = SciGetSelectionBytes(pane.view)
        let bytes = Array(SciGetText(pane.view).utf8)
        let input: String
        if sel.length > 0, sel.location + sel.length <= bytes.count {
            input = String(decoding: bytes[sel.location..<sel.location+sel.length], as: UTF8.self)
        } else {
            input = ""
        }
        let output = transform(input, kind: kind)
        if sel.length > 0 {
            SciBeginUndoAction(pane.view)
            _ = SciReplaceBytesRange(pane.view, sel.location, sel.location + sel.length, output)
            SciEndUndoAction(pane.view)
        } else {
            SciInsertTextAt(pane.view, sel.location == NSNotFound ? 0 : sel.location, output)
        }
    }

    static func transform(_ input: String, kind: Kind) -> String {
        switch kind {
        case .base64Encode:
            return input.data(using: .utf8)?.base64EncodedString() ?? ""
        case .base64Decode:
            return Data(base64Encoded: input).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        case .urlDecode:
            return input.removingPercentEncoding ?? ""
        case .md5:
            let data = input.data(using: .utf8) ?? Data()
            return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha256:
            let data = input.data(using: .utf8) ?? Data()
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .uuid:
            return UUID().uuidString
        case .timestampNow:
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: Date())
        case .toUpper:
            return input.uppercased()
        case .toLower:
            return input.lowercased()
        }
    }
}
