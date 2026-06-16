// SPDX-License-Identifier: MIT
// Sourcepad — entry point. NSApplication.shared + AppDelegate.

import Foundation
import AppKit

if let flagIndex = CommandLine.arguments.firstIndex(of: "--sourcegraph-mcp") {
    let argumentIndex = CommandLine.arguments.index(after: flagIndex)
    let argument = argumentIndex < CommandLine.arguments.endIndex ? CommandLine.arguments[argumentIndex] : nil
    exit(SourceGraphMCPServer.run(argument: argument))
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
