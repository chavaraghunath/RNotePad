// SPDX-License-Identifier: MIT
// RNotePad — entry point. NSApplication.shared + AppDelegate.

import AppKit

// Instantiate our subclassed NSDocumentController BEFORE NSApplication.shared
// is accessed, so it becomes the shared instance (NSDocumentController claims
// the shared slot on first init).
_ = DocumentController()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
