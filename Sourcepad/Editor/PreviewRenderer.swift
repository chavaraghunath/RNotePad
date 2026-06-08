// SPDX-License-Identifier: MIT
// Sourcepad — shared HTML/Markdown/CSS rendering for the preview pane.

import AppKit
import WebKit

public enum PreviewRenderer {
    public enum Kind {
        case html
        case markdown
        case css
    }

    /// Decide which preview, if any, applies to a document filename.
    public static func kind(forFilename filename: String, fallbackLexer: String?) -> Kind? {
        let name = filename.lowercased()
        if name.hasSuffix(".md") || name.hasSuffix(".markdown") || name.hasSuffix(".mdx") {
            return .markdown
        }
        if name.hasSuffix(".html") || name.hasSuffix(".htm") || name.hasSuffix(".xhtml") {
            return .html
        }
        if name.hasSuffix(".css") || name.hasSuffix(".scss") || name.hasSuffix(".less") {
            return .css
        }
        // Untitled — fall back to the active lexer.
        switch fallbackLexer {
        case "markdown": return .markdown
        case "hypertext", "xml": return .html
        case "css": return .css
        default: return nil
        }
    }

    /// Render `source` into `webView`. For HTML, the source loads as-is. For
    /// Markdown, we wrap it in a template that runs a tiny inline parser. For
    /// CSS, the user's CSS is injected into a showcase HTML document that
    /// exercises common selectors.
    public static func render(source: String,
                              kind: Kind,
                              baseURL: URL?,
                              isDark: Bool,
                              into webView: WKWebView) {
        switch kind {
        case .html:
            webView.loadHTMLString(source, baseURL: baseURL)
        case .markdown:
            webView.loadHTMLString(markdownHTML(source: source, isDark: isDark), baseURL: baseURL)
        case .css:
            webView.loadHTMLString(cssShowcaseHTML(source: source, isDark: isDark), baseURL: baseURL)
        }
    }

    // MARK: - Markdown

    private static func markdownHTML(source: String, isDark: Bool) -> String {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`",  with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
        let bg     = isDark ? "#1E1E1E" : "#FFFFFF"
        let fg     = isDark ? "#D4D4D4" : "#000000"
        let codebg = isDark ? "#2D2D2D" : "#F5F5F5"
        let link   = isDark ? "#4FC1FF" : "#0066CC"
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
          h1, h2 { border-bottom: 1px solid \(border); padding-bottom: .3em; }
          a { color: \(link); }
          code { background: \(codebg); padding: 2px 6px; border-radius: 3px;
                 font-family: Menlo, Monaco, "SF Mono", monospace; font-size: 13px; }
          pre { background: \(codebg); padding: 14px 18px; border-radius: 6px; overflow-x: auto; }
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

    // MARK: - CSS showcase

    private static func cssShowcaseHTML(source: String, isDark: Bool) -> String {
        // Escape </ inside CSS to prevent prematurely closing the <style> tag.
        let safeCSS = source.replacingOccurrences(of: "</", with: "<\\/")
        let bg = isDark ? "#1E1E1E" : "#FFFFFF"
        let fg = isDark ? "#D4D4D4" : "#1F2937"
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style id="sourcepad-baseline">
          /* baseline — gives the user CSS something to override */
          html, body { background: \(bg); color: \(fg);
                       font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                       margin: 0; padding: 0; }
          .sp-container { max-width: 920px; margin: 0 auto; padding: 32px; }
          .sp-section { margin: 32px 0; }
          .sp-section > h3 { font-size: 11px; text-transform: uppercase; letter-spacing: 1px;
                             color: #6b7280; margin: 0 0 12px; font-weight: 600; }
          .sp-card { padding: 12px 16px; border-radius: 6px;
                     background: rgba(127, 127, 127, .08); }
          .sp-row { display: flex; gap: 16px; align-items: center; flex-wrap: wrap; }
        </style>
        <style id="sourcepad-user">\(safeCSS)</style>
        </head><body>
        <div class="sp-container">

          <header>
            <h1>Heading H1 — primary title</h1>
            <h2>Heading H2 — section title</h2>
            <h3>Heading H3 — subsection</h3>
            <h4>Heading H4</h4><h5>Heading H5</h5><h6>Heading H6</h6>
          </header>

          <section class="sp-section">
            <h3>Text</h3>
            <p>A paragraph with <strong>strong</strong>, <em>emphasis</em>,
               <a href="#">a link</a>, and <code>inline code</code>. Lorem ipsum dolor sit amet,
               consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore.</p>
            <blockquote>A blockquote stands apart from regular paragraphs.</blockquote>
            <hr>
          </section>

          <section class="sp-section">
            <h3>Lists</h3>
            <div class="sp-row" style="align-items: flex-start;">
              <ul><li>Unordered one</li><li>Unordered two</li><li>Unordered three</li></ul>
              <ol><li>Ordered one</li><li>Ordered two</li><li>Ordered three</li></ol>
              <dl><dt>Term</dt><dd>Definition body</dd></dl>
            </div>
          </section>

          <section class="sp-section">
            <h3>Buttons</h3>
            <div class="sp-row">
              <button>Default</button>
              <button class="primary">Primary</button>
              <button class="secondary">Secondary</button>
              <button disabled>Disabled</button>
              <a href="#" class="btn">Anchor as button</a>
            </div>
          </section>

          <section class="sp-section">
            <h3>Form fields</h3>
            <div class="sp-row">
              <input type="text" placeholder="Text input">
              <input type="email" placeholder="email@example.com">
              <input type="password" placeholder="••••••••">
              <input type="checkbox" id="cb1"><label for="cb1">Checkbox</label>
              <input type="radio" name="r" id="r1"><label for="r1">Radio A</label>
              <input type="radio" name="r" id="r2"><label for="r2">Radio B</label>
              <select><option>Option one</option><option>Option two</option></select>
            </div>
            <textarea placeholder="Multi-line text area"
              style="display:block; margin-top: 12px; width: 100%; min-height: 64px;"></textarea>
          </section>

          <section class="sp-section">
            <h3>Table</h3>
            <table>
              <thead><tr><th>Name</th><th>Role</th><th>Score</th></tr></thead>
              <tbody>
                <tr><td>Alice</td><td>Engineer</td><td>92</td></tr>
                <tr><td>Bob</td><td>Designer</td><td>87</td></tr>
                <tr><td>Carol</td><td>PM</td><td>95</td></tr>
              </tbody>
            </table>
          </section>

          <section class="sp-section">
            <h3>Code</h3>
            <pre><code>function fib(n) {
              if (n &lt; 2) return n;
              return fib(n - 1) + fib(n - 2);
            }</code></pre>
          </section>

          <section class="sp-section">
            <h3>Cards / panels</h3>
            <div class="sp-row">
              <div class="sp-card">A card with <code>.sp-card</code></div>
              <div class="panel">A div with <code>.panel</code></div>
              <div class="alert">An alert</div>
            </div>
          </section>

        </div>
        </body></html>
        """
    }
}

// Tiny GFM-subset markdown→HTML in JS. Headings, fenced code, lists,
// blockquotes, hr, paragraphs, inline code/bold/italic/links/images.
private let markedJS: String = """
const marked = {
  parse: function(src) {
    src = src.replace(/\\r\\n?/g, '\\n');
    const lines = src.split('\\n');
    const out = [];
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      const h = line.match(/^(#{1,6})\\s+(.*)$/);
      if (h) {
        const level = h[1].length;
        out.push('<h' + level + '>' + inline(h[2]) + '</h' + level + '>');
        i++; continue;
      }
      const fence = line.match(/^```(\\S*)/);
      if (fence) {
        const lang = fence[1]; i++;
        const code = [];
        while (i < lines.length && !/^```/.test(lines[i])) { code.push(lines[i]); i++; }
        i++;
        const cls = lang ? ' class="language-' + lang + '"' : '';
        out.push('<pre><code' + cls + '>' + escapeHTML(code.join('\\n')) + '</code></pre>');
        continue;
      }
      if (/^(---+|\\*\\*\\*+|___+)\\s*$/.test(line)) { out.push('<hr>'); i++; continue; }
      if (/^>\\s?/.test(line)) {
        const quote = [];
        while (i < lines.length && /^>\\s?/.test(lines[i])) { quote.push(lines[i].replace(/^>\\s?/, '')); i++; }
        out.push('<blockquote>' + marked.parse(quote.join('\\n')) + '</blockquote>');
        continue;
      }
      if (/^[-*+]\\s+/.test(line)) {
        const items = [];
        while (i < lines.length && /^[-*+]\\s+/.test(lines[i])) {
          items.push('<li>' + inline(lines[i].replace(/^[-*+]\\s+/, '')) + '</li>'); i++;
        }
        out.push('<ul>' + items.join('') + '</ul>'); continue;
      }
      if (/^\\d+\\.\\s+/.test(line)) {
        const items = [];
        while (i < lines.length && /^\\d+\\.\\s+/.test(lines[i])) {
          items.push('<li>' + inline(lines[i].replace(/^\\d+\\.\\s+/, '')) + '</li>'); i++;
        }
        out.push('<ol>' + items.join('') + '</ol>'); continue;
      }
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
    function escapeHTML(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    function inline(s) {
      s = escapeHTML(s);
      s = s.replace(/!\\[([^\\]]*)\\]\\(([^)]+)\\)/g, '<img alt="$1" src="$2">');
      s = s.replace(/\\[([^\\]]+)\\]\\(([^)]+)\\)/g, '<a href="$2">$1</a>');
      s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
      s = s.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>');
      s = s.replace(/(^|[^*])\\*([^*]+)\\*/g, '$1<em>$2</em>');
      return s;
    }
  }
};
"""
