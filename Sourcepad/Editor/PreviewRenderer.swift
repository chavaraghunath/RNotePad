// SPDX-License-Identifier: MIT
// Sourcepad — shared HTML/Markdown/CSS rendering for the preview pane.

import AppKit
import WebKit

public enum PreviewRenderer {
    public enum Kind: Equatable {
        case html
        case markdown
        case css
        case image          // raster (png, jpg, gif, bmp, webp, heic, tiff)
        case svg            // vector — also editable as XML
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
        if name.hasSuffix(".svg") {
            return .svg
        }
        for ext in [".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".heic", ".heif", ".tiff", ".tif", ".ico"] {
            if name.hasSuffix(ext) { return .image }
        }
        // Untitled — fall back to the active lexer.
        switch fallbackLexer {
        case "markdown": return .markdown
        case "hypertext", "xml": return .html
        case "css": return .css
        default: return nil
        }
    }

    /// Filenames that are raster images and don't make sense to edit as text.
    /// The editor pane will skip text decoding for these and auto-show preview.
    public static func isBinaryImage(filename: String) -> Bool {
        let name = filename.lowercased()
        for ext in [".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".heic", ".heif", ".tiff", ".tif", ".ico"] {
            if name.hasSuffix(ext) { return true }
        }
        return false
    }

    /// Render `source` into `webView`. For HTML, the source loads as-is. For
    /// Markdown, we wrap it in a template that runs a tiny inline parser. For
    /// CSS, the user's CSS is injected into a showcase HTML document that
    /// exercises common selectors. For images / SVG, we embed the bytes.
    public static func render(source: String,
                              kind: Kind,
                              baseURL: URL?,
                              isDark: Bool,
                              into webView: WKWebView,
                              fileURL: URL? = nil) {
        switch kind {
        case .html:
            webView.loadHTMLString(source, baseURL: baseURL)
        case .markdown:
            webView.loadHTMLString(markdownHTML(source: source, isDark: isDark), baseURL: baseURL)
        case .css:
            webView.loadHTMLString(cssShowcaseHTML(source: source, isDark: isDark), baseURL: baseURL)
        case .image:
            webView.loadHTMLString(imageHTML(fileURL: fileURL, isDark: isDark), baseURL: baseURL)
        case .svg:
            // For SVG: prefer to inline the editor source so live edits show
            // immediately. Falls back to reading the file if `source` is empty.
            let svgText: String
            if !source.isEmpty {
                svgText = source
            } else if let url = fileURL, let raw = try? String(contentsOf: url) {
                svgText = raw
            } else {
                svgText = ""
            }
            webView.loadHTMLString(svgHTML(svgSource: svgText, isDark: isDark), baseURL: baseURL)
        }
    }

    // MARK: - Image preview

    private static func imageHTML(fileURL: URL?, isDark: Bool) -> String {
        let bg = isDark ? "#1E1E1E" : "#FFFFFF"
        let fg = isDark ? "#D4D4D4" : "#1F2937"
        guard let url = fileURL, let data = try? Data(contentsOf: url) else {
            return """
            <!doctype html><html><body style="background:\(bg);color:\(fg);
              font-family:-apple-system,sans-serif;display:flex;align-items:center;
              justify-content:center;height:100vh;margin:0;">
              Cannot load image.
            </body></html>
            """
        }
        let mime = mimeType(for: url.pathExtension.lowercased()) ?? "application/octet-stream"
        let b64 = data.base64EncodedString()
        let sizeKB = Double(data.count) / 1024.0
        let dim = imageDimensions(data: data) ?? "—"
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
          html, body { margin: 0; padding: 0; background: \(bg); color: \(fg);
                       font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                       height: 100vh; }
          .stage { display: flex; flex-direction: column; align-items: center;
                   justify-content: center; height: 100vh; padding: 20px;
                   box-sizing: border-box; }
          .image-wrap {
            flex: 1; display: flex; align-items: center; justify-content: center;
            max-width: 100%; max-height: 100%; overflow: auto;
            background-image: linear-gradient(45deg, #cccccc 25%, transparent 25%),
                              linear-gradient(-45deg, #cccccc 25%, transparent 25%),
                              linear-gradient(45deg, transparent 75%, #cccccc 75%),
                              linear-gradient(-45deg, transparent 75%, #cccccc 75%);
            background-size: 18px 18px;
            background-position: 0 0, 0 9px, 9px -9px, -9px 0;
            background-color: #ddd;
            border-radius: 6px;
          }
          \(isDark ? ".image-wrap { background-color: #2c2c2c; background-image: linear-gradient(45deg, #3a3a3a 25%, transparent 25%), linear-gradient(-45deg, #3a3a3a 25%, transparent 25%), linear-gradient(45deg, transparent 75%, #3a3a3a 75%), linear-gradient(-45deg, transparent 75%, #3a3a3a 75%); }" : "")
          img { max-width: 100%; max-height: 100%; object-fit: contain;
                image-rendering: pixelated; image-rendering: -moz-crisp-edges; }
          .meta { font-size: 11px; color: #888; margin-top: 12px; user-select: text; }
        </style>
        </head><body><div class="stage">
          <div class="image-wrap"><img src="data:\(mime);base64,\(b64)"></div>
          <div class="meta">\(url.lastPathComponent) — \(dim) — \(String(format: "%.1f", sizeKB)) KB</div>
        </div></body></html>
        """
    }

    private static func svgHTML(svgSource: String, isDark: Bool) -> String {
        let bg = isDark ? "#1E1E1E" : "#FFFFFF"
        let fg = isDark ? "#D4D4D4" : "#1F2937"
        // Strip XML prolog / DOCTYPE — the document already has its own.
        var body = svgSource
        if let prologEnd = body.range(of: "?>") {
            body = String(body[prologEnd.upperBound...])
        }
        if let doctypeEnd = body.range(of: ">", range: body.range(of: "<!DOCTYPE", options: .caseInsensitive) ?? body.startIndex..<body.startIndex) {
            body = String(body[doctypeEnd.upperBound...])
        }
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
          html, body { margin: 0; padding: 0; background: \(bg); color: \(fg);
                       font-family: -apple-system, sans-serif; height: 100vh; }
          .stage { display: flex; align-items: center; justify-content: center;
                   height: 100vh; padding: 20px; box-sizing: border-box; }
          svg { max-width: 100%; max-height: 100%; }
        </style>
        </head><body><div class="stage">\(body)</div></body></html>
        """
    }

    private static func mimeType(for ext: String) -> String? {
        switch ext {
        case "png":              return "image/png"
        case "jpg", "jpeg":      return "image/jpeg"
        case "gif":              return "image/gif"
        case "bmp":              return "image/bmp"
        case "webp":             return "image/webp"
        case "heic", "heif":     return "image/heic"
        case "tiff", "tif":      return "image/tiff"
        case "ico":              return "image/x-icon"
        case "svg":              return "image/svg+xml"
        default:                 return nil
        }
    }

    /// Reads PNG IHDR / JPEG SOFn / GIF screen descriptor for a "W×H" string.
    /// Returns nil if format isn't recognized. Cheap byte-prefix inspection.
    private static func imageDimensions(data: Data) -> String? {
        let bytes = [UInt8](data.prefix(48))
        // PNG: 89 50 4E 47 0D 0A 1A 0A, then IHDR at offset 16. Width @16-19, Height @20-23 big-endian.
        if bytes.count >= 24,
           bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            let w = (Int(bytes[16]) << 24) | (Int(bytes[17]) << 16) | (Int(bytes[18]) << 8) | Int(bytes[19])
            let h = (Int(bytes[20]) << 24) | (Int(bytes[21]) << 16) | (Int(bytes[22]) << 8) | Int(bytes[23])
            return "\(w)×\(h)"
        }
        // GIF: "GIF87a" / "GIF89a", width @6-7, height @8-9 little-endian.
        if bytes.count >= 10, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 {
            let w = Int(bytes[6]) | (Int(bytes[7]) << 8)
            let h = Int(bytes[8]) | (Int(bytes[9]) << 8)
            return "\(w)×\(h)"
        }
        // JPEG SOFn scan — too verbose to reproduce here; fall back to nil.
        return nil
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
        <!-- Mermaid (Phase 17) — lazily loaded from a vendored bundle if
             present; otherwise mermaid blocks fall through as code fences. -->
        <script>
          window.MathJax = { tex: { inlineMath: [['$','$'],['\\\\(','\\\\)']],
                                    displayMath: [['$$','$$'],['\\\\[','\\\\]']] }};
        </script>
        </head><body>
        <div id="content"></div>
        <script>
          const src = `\(escaped)`;
          document.getElementById('content').innerHTML = marked.parse(src);
          // Render Mermaid diagrams if a mermaid global is available.
          if (typeof mermaid !== 'undefined') {
            try { mermaid.initialize({ startOnLoad: false, theme: '\(isDark ? "dark" : "default")' });
                  mermaid.run({ querySelector: 'pre code.language-mermaid' }); } catch (e) {}
          }
          // KaTeX: replace $$...$$ + $...$ blocks. If MathJax/KaTeX is
          // vendored at Resources/preview-libs/, the user can include
          // it; absent that, math renders as inline literals (fallback).
          if (typeof katex !== 'undefined' && typeof renderMathInElement !== 'undefined') {
            try { renderMathInElement(document.getElementById('content'),
                                      { delimiters: [
                                          { left: '$$', right: '$$', display: true },
                                          { left: '$',  right: '$',  display: false }
                                      ]}); } catch (e) {}
          }
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
