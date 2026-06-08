// SPDX-License-Identifier: MIT
// RNotePad — a trivial NSView subclass whose only job is to forward
// viewDidChangeEffectiveAppearance to a closure (NSViewController doesn't
// receive this call, but NSView does).

import AppKit

final class AppearanceForwardingView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}
