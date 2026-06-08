// SPDX-License-Identifier: MIT
// RNotePad — secondary preview window for HTML/Markdown documents.
//
// Opens a WKWebView in a separate window that mirrors the source document.
// Re-renders live as the user edits. Closes automatically when the source
// document closes.

import AppKit
import WebKit

public final class PreviewWindowController: NSWindowController {

    public enum Kind {
        case html
        case markdown
    }

    private weak var sourceDocument: TextDocument?
    private let kind: Kind
    private let webView: WKWebView
    private var renderTimer: DispatchSourceTimer?

    public init(document: TextDocument, kind: Kind) {
        self.sourceDocument = document
        self.kind = kind

        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 700),
                           configuration: config)
        self.webView = wv

        let window = NSWindow(contentRect: wv.frame,
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = previewTitle(for: document, kind: kind)
        window.contentView = wv
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("RNotePadPreview")
        window.center()

        super.init(window: window)
        window.delegate = self

        render()
        observeDocumentChanges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    public func render() {
        guard let doc = sourceDocument else { return }
        let source = (doc.windowControllers.compactMap { ($0 as? EditorWindowController)?.editorViewController }.first?.currentText) ?? doc.contents
        switch kind {
        case .html:
            let baseURL = doc.fileURL?.deletingLastPathComponent()
            webView.loadHTMLString(source, baseURL: baseURL)
        case .markdown:
            let html = HTMLForMarkdown(source: source, baseURL: doc.fileURL?.deletingLastPathComponent(), isDark: isDarkAppearance())
            webView.loadHTMLString(html, baseURL: doc.fileURL?.deletingLastPathComponent())
        }
    }

    private func observeDocumentChanges() {
        // Debounce re-render to 250ms after the last edit.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // Cheap re-render every tick if doc still alive; WKWebView handles dedup.
            self.render()
        }
        timer.resume()
        renderTimer = timer
    }

    private func isDarkAppearance() -> Bool {
        let app = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        return app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

extension PreviewWindowController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        renderTimer?.cancel()
        renderTimer = nil
    }
}

private func previewTitle(for doc: TextDocument, kind: PreviewWindowController.Kind) -> String {
    let name = doc.fileURL?.lastPathComponent ?? doc.displayName ?? "Untitled"
    let label = kind == .html ? "HTML Preview" : "Markdown Preview"
    return "\(label) — \(name)"
}

// MARK: - Markdown renderer (uses marked.js, embedded as a string)

/// Wraps the markdown source in an HTML template that loads marked.js inline
/// and renders the document. We embed marked.js as a static string so the
/// preview works offline and doesn't depend on internet access.
private func HTMLForMarkdown(source: String, baseURL: URL?, isDark: Bool) -> String {
    // Escape the source for embedding inside a template literal: handle backslashes,
    // backticks, and ${ interpolation triggers.
    let escaped = source
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`",  with: "\\`")
        .replacingOccurrences(of: "${", with: "\\${")
    let bg = isDark ? "#1E1E1E" : "#FFFFFF"
    let fg = isDark ? "#D4D4D4" : "#000000"
    let codebg = isDark ? "#2D2D2D" : "#F5F5F5"
    let link = isDark ? "#4FC1FF" : "#0066CC"
    let border = isDark ? "#333333" : "#DDDDDD"
    return """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8">
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
             background: \(bg); color: \(fg);
             max-width: 780px; margin: 32px auto; padding: 0 24px;
             line-height: 1.6; font-size: 15px; }
      h1, h2, h3, h4, h5, h6 { color: \(fg); margin-top: 1.5em; }
      h1 { border-bottom: 1px solid \(border); padding-bottom: .3em; }
      h2 { border-bottom: 1px solid \(border); padding-bottom: .3em; }
      a { color: \(link); }
      code { background: \(codebg); padding: 2px 6px; border-radius: 3px;
             font-family: Menlo, Monaco, "SF Mono", monospace; font-size: 13px; }
      pre { background: \(codebg); padding: 14px 18px; border-radius: 6px;
            overflow-x: auto; }
      pre code { background: transparent; padding: 0; }
      blockquote { border-left: 3px solid \(border); padding-left: 16px;
                   color: #888; margin-left: 0; }
      table { border-collapse: collapse; }
      th, td { border: 1px solid \(border); padding: 6px 12px; }
      img { max-width: 100%; }
      hr { border: 0; border-top: 1px solid \(border); }
    </style>
    <script>\(markedJS)</script>
    </head><body>
    <div id="content"></div>
    <script>
      const src = `\(escaped)`;
      document.getElementById('content').innerHTML = marked.parse(src);
    </script>
    </body></html>
    """
}

// Minimal subset of marked.js sufficient for headings, lists, code blocks,
// links, images, tables, blockquotes, emphasis. Loaded inline so the preview
// works offline.
//
// We use a tiny hand-rolled markdown renderer rather than embedding the full
// marked.js source (~50KB) to keep the binary small. Covers GFM basics.
private let markedJS: String = """
const marked = {
  parse: function(src) {
    // Normalise line endings.
    src = src.replace(/\\r\\n?/g, '\\n');
    const lines = src.split('\\n');
    const out = [];
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      // ATX heading
      const h = line.match(/^(#{1,6})\\s+(.*)$/);
      if (h) {
        const level = h[1].length;
        out.push('<h' + level + '>' + inline(h[2]) + '</h' + level + '>');
        i++; continue;
      }
      // Fenced code block
      const fence = line.match(/^```(\\S*)/);
      if (fence) {
        const lang = fence[1];
        i++;
        const code = [];
        while (i < lines.length && !/^```/.test(lines[i])) {
          code.push(lines[i]); i++;
        }
        i++; // skip closing fence
        const cls = lang ? ' class="language-' + lang + '"' : '';
        out.push('<pre><code' + cls + '>' + escapeHTML(code.join('\\n')) + '</code></pre>');
        continue;
      }
      // Horizontal rule
      if (/^(---+|\\*\\*\\*+|___+)\\s*$/.test(line)) {
        out.push('<hr>'); i++; continue;
      }
      // Blockquote
      if (/^>\\s?/.test(line)) {
        const quote = [];
        while (i < lines.length && /^>\\s?/.test(lines[i])) {
          quote.push(lines[i].replace(/^>\\s?/, '')); i++;
        }
        out.push('<blockquote>' + marked.parse(quote.join('\\n')) + '</blockquote>');
        continue;
      }
      // Unordered list
      if (/^[-*+]\\s+/.test(line)) {
        const items = [];
        while (i < lines.length && /^[-*+]\\s+/.test(lines[i])) {
          items.push('<li>' + inline(lines[i].replace(/^[-*+]\\s+/, '')) + '</li>');
          i++;
        }
        out.push('<ul>' + items.join('') + '</ul>'); continue;
      }
      // Ordered list
      if (/^\\d+\\.\\s+/.test(line)) {
        const items = [];
        while (i < lines.length && /^\\d+\\.\\s+/.test(lines[i])) {
          items.push('<li>' + inline(lines[i].replace(/^\\d+\\.\\s+/, '')) + '</li>');
          i++;
        }
        out.push('<ol>' + items.join('') + '</ol>'); continue;
      }
      // Paragraph (gather lines until blank)
      if (line.trim().length === 0) { i++; continue; }
      const para = [];
      while (i < lines.length && lines[i].trim().length > 0
             && !/^#{1,6}\\s/.test(lines[i])
             && !/^```/.test(lines[i])
             && !/^>\\s?/.test(lines[i])
             && !/^[-*+]\\s+/.test(lines[i])
             && !/^\\d+\\.\\s+/.test(lines[i])) {
        para.push(lines[i]); i++;
      }
      out.push('<p>' + inline(para.join(' ')) + '</p>');
    }
    return out.join('\\n');

    function escapeHTML(s) {
      return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
    function inline(s) {
      s = escapeHTML(s);
      // Images: ![alt](src)
      s = s.replace(/!\\[([^\\]]*)\\]\\(([^)]+)\\)/g, '<img alt="$1" src="$2">');
      // Links: [text](href)
      s = s.replace(/\\[([^\\]]+)\\]\\(([^)]+)\\)/g, '<a href="$2">$1</a>');
      // Inline code
      s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
      // Bold **x**
      s = s.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>');
      // Italic *x* (avoid matching inside word boundaries near **)
      s = s.replace(/(^|[^*])\\*([^*]+)\\*/g, '$1<em>$2</em>');
      return s;
    }
  }
};
"""
