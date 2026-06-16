// SPDX-License-Identifier: MIT
// Sourcepad — entry point. NSApplication.shared + AppDelegate.

import Foundation
import AppKit

if let flagIndex = CommandLine.arguments.firstIndex(of: "--sourcegraph-mcp") {
    let argumentIndex = CommandLine.arguments.index(after: flagIndex)
    let argument = argumentIndex < CommandLine.arguments.endIndex ? CommandLine.arguments[argumentIndex] : nil
    exit(SourceGraphMCPServer.run(argument: argument))
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
