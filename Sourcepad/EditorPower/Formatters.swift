// SPDX-License-Identifier: MIT
// Sourcepad — Phase 27 format-on-save / format-buffer command.
//
// Each known language maps to a CLI formatter that reads stdin → stdout
// (the universal interface). We pipe the buffer in, capture the output,
// replace the buffer. Format-on-save runs this on every save when the
// preference is enabled.

import Foundation
import AppKit

public struct FormatterSpec {
    public let executable: String
    public let arguments: [String]
}

public enum Formatters {

    public static func spec(forFileURL url: URL) -> FormatterSpec? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "py":               return FormatterSpec(executable: "black", arguments: ["-"])
        case "go":               return FormatterSpec(executable: "gofmt", arguments: [])
        case "rs":               return FormatterSpec(executable: "rustfmt", arguments: ["--emit=stdout"])
        case "js", "jsx", "ts", "tsx", "json", "html", "css", "scss", "yaml", "yml", "md", "markdown":
                                  return FormatterSpec(executable: "prettier",
                                                       arguments: ["--stdin-filepath", url.path])
        case "swift":            return FormatterSpec(executable: "swift-format", arguments: ["format", "--in-place=false"])
        case "c", "cc", "cxx", "cpp", "h", "hh", "hpp", "hxx", "m", "mm":
                                  return FormatterSpec(executable: "clang-format", arguments: [])
        default:                  return nil
        }
    }

    /// Pipe `text` through the spec's executable; return the result on
    /// success or nil on failure / executable missing.
    public static func run(_ spec: FormatterSpec, on text: String) -> String? {
        guard let exec = LSPServerSpec.which(spec.executable) else { return nil }
        let p = Process()
        p.executableURL = exec
        p.arguments = spec.arguments
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        p.standardInput = stdinPipe
        p.standardOutput = stdoutPipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        // Write input.
        if let data = text.data(using: .utf8) {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? stdinPipe.fileHandleForWriting.close()
        let out = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: out, encoding: .utf8)
    }

    /// Format the active editor's buffer in place.
    public static func formatActiveBuffer() {
        guard let doc = NSDocumentController.shared.currentDocument as? TextDocument,
              let url = doc.fileURL,
              let pane = doc.primaryEditorViewController()?.editorPane,
              let spec = spec(forFileURL: url) else {
            NSSound.beep(); return
        }
        let original = SciGetText(pane.view)
        guard let formatted = run(spec, on: original), formatted != original else { return }
        SciBeginUndoAction(pane.view)
        let len = SciTextLengthBytes(pane.view)
        _ = SciReplaceBytesRange(pane.view, 0, len, formatted)
        SciEndUndoAction(pane.view)
    }
}
