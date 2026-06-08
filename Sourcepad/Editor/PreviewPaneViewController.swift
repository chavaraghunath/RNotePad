// SPDX-License-Identifier: MIT
// Sourcepad — right pane of the editor split. A WKWebView that renders
// HTML or Markdown.

import AppKit
import WebKit

public final class PreviewPaneViewController: NSViewController {

    private var webView: WKWebView!

    public override func loadView() {
        let frame = NSRect(x: 0, y: 0, width: 480, height: 600)
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: frame, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")  // let our container show through
        self.view = wv
        self.webView = wv
    }

    public func render(source: String, kind: PreviewRenderer.Kind, baseURL: URL?, isDark: Bool) {
        guard webView != nil else { return }
        PreviewRenderer.render(source: source, kind: kind, baseURL: baseURL, isDark: isDark, into: webView)
    }
}
