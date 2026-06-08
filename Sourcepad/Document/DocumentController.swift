// SPDX-License-Identifier: MIT
// Sourcepad — custom NSDocumentController to intercept file opens.
//
// AppKit's default 'odoc' Apple Event handler routes straight to
// NSDocumentController.openDocument(withContentsOf:display:completionHandler:),
// bypassing the app delegate's application(_:open:) entirely for document-based
// apps. Subclassing the controller is the only reliable hook.
//
// We also ensure the new document's window is brought to the front, because
// our programmatic NSWindowController doesn't reliably do so by itself.

import AppKit

@objc(SPDocumentController)
public final class DocumentController: NSDocumentController {

    public override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        DebugLog.log("DocumentController.openDocument: \(url.path)")
        super.openDocument(withContentsOf: url, display: displayDocument) { doc, alreadyOpen, error in
            if let error {
                DebugLog.log("  open failed: \(error)")
            } else {
                DebugLog.log("  opened: \(String(describing: doc)) alreadyOpen=\(alreadyOpen) wcCount=\(doc?.windowControllers.count ?? -1)")
                if let doc {
                    DispatchQueue.main.async {
                        if doc.windowControllers.isEmpty {
                            DebugLog.log("  no WCs — calling makeWindowControllers")
                            doc.makeWindowControllers()
                        }
                        for wc in doc.windowControllers {
                            DebugLog.log("  WC: window=\(String(describing: wc.window)) visible=\(wc.window?.isVisible ?? false)")
                            wc.showWindow(nil)
                            wc.window?.makeKeyAndOrderFront(nil)
                            DebugLog.log("  WC after show: visible=\(wc.window?.isVisible ?? false)")
                        }
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
            completionHandler(doc, alreadyOpen, error)
        }
    }
}
