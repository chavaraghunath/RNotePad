// SPDX-License-Identifier: MIT
// Sourcepad — surface a one-click installer for missing language servers.
//
// When the user opens a file whose LSPServerSpec has no resolvable
// executable, we show a non-blocking sheet: "Install <DisplayName>?"
// with the install command. Hitting Install runs the command in a
// child shell with output piped into a sheet so the user can see what
// happened. We never run the command silently.
//
// Phase 7 keeps this best-effort — if the command fails (missing npm /
// brew / cargo etc.), we surface the error and let the user fix their
// toolchain. We don't try to install the package manager itself.

import AppKit

public final class LSPInstaller {

    public static let shared = LSPInstaller()

    /// Specs we've already prompted the user about during this session
    /// (whether they accepted, declined, or it's still running). We don't
    /// re-prompt for the same server on every file open.
    private var promptedThisSession: Set<String> = []

    private init() {}

    /// Prompt the user to install the given missing server. No-op if the
    /// server is actually present, or if we already prompted this session.
    public func promptIfMissing(_ spec: LSPServerSpec, parentWindow: NSWindow?) {
        if spec.locate() != nil { return }
        if promptedThisSession.contains(spec.languageId) { return }
        promptedThisSession.insert(spec.languageId)

        let alert = NSAlert()
        alert.messageText = "Install \(spec.displayName)?"
        alert.informativeText = "Sourcepad's LSP integration for this language needs `\(spec.executableName)`. Run:\n\n    \(spec.installHint)\n\nThis runs in a child shell; output streams to a progress sheet."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")

        let respond: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard resp == .alertFirstButtonReturn else { return }
            self?.runInstall(spec: spec, parentWindow: parentWindow)
        }

        if let parentWindow {
            alert.beginSheetModal(for: parentWindow, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }

    /// Run the install command in a login shell so PATH / nvm / pyenv all
    /// resolve. Stream stdout+stderr into a progress sheet.
    private func runInstall(spec: LSPServerSpec, parentWindow: NSWindow?) {
        let sheet = NSAlert()
        sheet.messageText = "Installing \(spec.displayName)…"
        sheet.informativeText = "$ \(spec.installHint)\n\n(starting…)"
        sheet.alertStyle = .informational
        sheet.addButton(withTitle: "Hide")

        // We need a live-updating text area for output. NSAlert doesn't
        // give us streaming text easily, so attach a scrollable text view
        // as the accessoryView.
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = "$ \(spec.installHint)\n"
        let scroll = NSScrollView(frame: textView.frame)
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        sheet.accessoryView = scroll

        // Build the process. Use `/bin/zsh -lc` so PATH expansions work.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", spec.installHint]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let append: (String) -> Void = { text in
            DispatchQueue.main.async {
                textView.string.append(text)
                textView.scrollToEndOfDocument(nil)
            }
        }
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            if let s = String(data: chunk, encoding: .utf8) { append(s) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            if let s = String(data: chunk, encoding: .utf8) { append(s) }
        }
        proc.terminationHandler = { p in
            append("\n[exit \(p.terminationStatus)]\n")
        }
        do {
            try proc.run()
        } catch {
            append("\n[failed to launch: \(error)]\n")
        }

        if let parentWindow {
            sheet.beginSheetModal(for: parentWindow) { _ in
                if proc.isRunning { proc.terminate() }
            }
        } else {
            sheet.runModal()
            if proc.isRunning { proc.terminate() }
        }
    }
}
