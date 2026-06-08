// SPDX-License-Identifier: MIT
// Sourcepad — right pane of the editor split. A WKWebView that renders
// HTML / Markdown / CSS-showcase content. Preserves scroll position across
// re-renders so live preview while typing doesn't jump back to the top.

import AppKit
import WebKit

public final class PreviewPaneViewController: NSViewController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var pendingScroll: CGFloat = 0
    private var hasPendingScroll: Bool = false

    public override func loadView() {
        let frame = NSRect(x: 0, y: 0, width: 480, height: 600)
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: frame, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = self
        self.view = wv
        self.webView = wv
    }

    public func render(source: String, kind: PreviewRenderer.Kind, baseURL: URL?, isDark: Bool, fileURL: URL? = nil) {
        guard let webView else { return }
        webView.evaluateJavaScript("window.scrollY || 0") { [weak self] result, _ in
            guard let self else { return }
            let y = (result as? NSNumber).map { CGFloat(truncating: $0) } ?? 0
            self.pendingScroll = y
            self.hasPendingScroll = y > 0
            PreviewRenderer.render(source: source, kind: kind, baseURL: baseURL,
                                   isDark: isDark, into: self.webView, fileURL: fileURL)
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard hasPendingScroll else { return }
        let y = pendingScroll
        hasPendingScroll = false
        // Restore the previous scroll position after the page has laid out.
        webView.evaluateJavaScript("window.scrollTo(0, \(y))")
    }
}
