// SPDX-License-Identifier: MIT
// RNotePad — entry point. NSApplication.shared + AppDelegate.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
