// SPDX-License-Identifier: MIT
// Sourcepad — entry point. NSApplication.shared + AppDelegate.

import Foundation
import AppKit

if let flagIndex = CommandLine.arguments.firstIndex(of: "--sourcegraph-mcp") {
    let argumentIndex = CommandLine.arguments.index(after: flagIndex)
    let argument = argumentIndex < CommandLine.arguments.endIndex ? CommandLine.arguments[argumentIndex] : nil
    exit(SourceGraphMCPServer.run(argument: argument))
}

// Headless full index pass over a folder (no GUI). Resolves the matching
// indexed workspace if there is one (so its on-disk DB is updated and
// --sourcegraph-mcp picks it up); otherwise indexes into a temp DB. Prints
// file + symbol counts. Useful for backfills, scripting, and tests.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--reindex") {
    let next = CommandLine.arguments.index(after: flagIndex)
    guard next < CommandLine.arguments.endIndex else {
        FileHandle.standardError.write(Data("usage: --reindex <folder>\n".utf8)); exit(2)
    }
    let target = URL(fileURLWithPath: CommandLine.arguments[next]).standardizedFileURL

    WorkspaceManager.shared.loadAll()
    let targetPath = target.path
    let existing = WorkspaceManager.shared.workspaces.first { ws in
        ws.roots.contains { r in
            let p = r.standardizedFileURL.path
            return targetPath == p || targetPath.hasPrefix(p + "/") || p.hasPrefix(targetPath + "/")
        }
    }
    let ws = existing ?? Workspace(name: target.lastPathComponent, roots: [target])
    // For a real indexed workspace, write its on-disk DB so --sourcegraph-mcp
    // picks the symbols up. For an ad-hoc folder, use a TEMP DB so we don't
    // orphan an unresolvable .db in the user's Workspaces directory.
    let dbURL: URL
    if existing != nil {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        dbURL = support.appendingPathComponent("Sourcepad/Workspaces", isDirectory: true)
            .appendingPathComponent("\(ws.id).db", isDirectory: false)
    } else {
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sourcepad-reindex-\(ws.id).db", isDirectory: false)
    }
    guard let index = ProjectIndex(databaseURL: dbURL) else {
        FileHandle.standardError.write(Data("could not open index\n".utf8)); exit(1)
    }
    FileHandle.standardError.write(Data("indexing \(targetPath) (workspace \(ws.id))…\n".utf8))
    let coord = IndexerCoordinator(workspace: ws, index: index)
    coord.indexSynchronously()
    print("files=\(index.fileCount()) symbols=\(index.allSymbols().count)")
    index.close()
    exit(0)
}

// Hidden diagnostic: extract + print symbols from a source file (tests the
// Tree-sitter symbol extractor end-to-end with grammars linked).
if let flagIndex = CommandLine.arguments.firstIndex(of: "--extract-symbols") {
    let next = CommandLine.arguments.index(after: flagIndex)
    guard next < CommandLine.arguments.endIndex else { FileHandle.standardError.write(Data("usage: --extract-symbols <file>\n".utf8)); exit(2) }
    let path = CommandLine.arguments[next]
    guard let lang = TreeSitterLanguage.forFilename((path as NSString).lastPathComponent) else {
        print("no tree-sitter grammar for \(path)"); exit(0)
    }
    let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    for s in SymbolExtractor.extract(source: source, language: lang) {
        print("\(s.kind)\t\(s.name)\t\(s.line + 1):\(s.col)")
    }
    exit(0)
}

// Hidden diagnostic: print the MCP merge each CLI WOULD receive, without writing
// anything. Used to verify the sync engine against real configs safely.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--mcp-preview") {
    let next = CommandLine.arguments.index(after: flagIndex)
    let root = next < CommandLine.arguments.endIndex ? CommandLine.arguments[next] : NSHomeDirectory()
    for entry in MCPSyncEngine.previewAll(workspaceRoot: root) {
        print("===== \(entry.cli) (present: \(entry.present)) =====")
        print(entry.merged ?? "<absent / nil>")
        print()
    }
    print("--- idempotency ---")
    for r in MCPSyncEngine.idempotencyCheck(workspaceRoot: root) {
        print("\(r.cli): \(r.idempotent ? "OK" : "NOT IDEMPOTENT")")
    }
    exit(0)
}

// Instantiate our subclassed NSDocumentController BEFORE NSApplication.shared
// is accessed, so it becomes the shared instance (NSDocumentController claims
// the shared slot on first init).
_ = DocumentController()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
