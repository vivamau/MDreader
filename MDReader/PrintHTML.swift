import Foundation

enum PrintHTML {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func inline(_ text: String) -> String {
        guard let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return escape(text) }
        return attributed.runs.map { run in
            var html = escape(String(attributed[run.range].characters))
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { html = "<code>\(html)</code>" }
            if intent.contains(.stronglyEmphasized) { html = "<strong>\(html)</strong>" }
            if intent.contains(.emphasized) { html = "<em>\(html)</em>" }
            if intent.contains(.strikethrough) { html = "<del>\(html)</del>" }
            return html
        }.joined()
    }

    static func document(
        _ source: String,
        title: String,
        fontChoice: ReaderFont = .system,
        fontSize: Double = 11,
        diagramHTML: ((String) -> String?)? = nil
    ) -> String {
        let body = MarkdownBlocks.parse(source).map { block -> String in
            switch block {
            case let .heading(level, text): return "<h\(level)>\(inline(text))</h\(level)>"
            case let .paragraph(text), let .item(text): return "<p>\(inline(text))</p>"
            case let .quote(text): return "<blockquote>\(inline(text))</blockquote>"
            case let .mermaid(text):
                return diagramHTML?(text) ?? "<p>Mermaid diagram source</p><pre>\(escape(text))</pre>"
            case let .code(text): return "<pre><code>\(escape(text))</code></pre>"
            case .rule: return "<hr>"
            case let .table(headers, alignments, rows):
                func row(_ cells: [String], tag: String) -> String {
                    "<tr>" + cells.enumerated().map { index, text in
                        let alignment = alignments[index] == .right ? "right" : alignments[index] == .center ? "center" : "left"
                        return "<\(tag) style=\"text-align:\(alignment)\">\(inline(text))</\(tag)>"
                    }.joined() + "</tr>"
                }
                return "<table><thead>\(row(headers, tag: "th"))</thead><tbody>\(rows.map { row($0, tag: "td") }.joined())</tbody></table>"
            }
        }.joined(separator: "\n")
        let family: String
        switch fontChoice {
        case .system: family = "-apple-system, BlinkMacSystemFont, sans-serif"
        case .serif: family = "ui-serif, Georgia, serif"
        case .rounded: family = "ui-rounded, -apple-system, sans-serif"
        case .monospaced: family = "ui-monospace, Menlo, monospace"
        case .georgia: family = "Georgia, serif"
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <title>\(escape(title))</title><style>
        :root { color-scheme: light; } body { font: \(fontSize)pt \(family); line-height: 1.45; color: #111; background: white; margin: 24px; }
        h1,h2,h3,h4,h5,h6 { break-after: avoid; } p { white-space: pre-wrap; }
        table { border-collapse: collapse; width: 100%; table-layout: fixed; margin: 16px 0; font-size: 9pt; }
        th,td { border: 1px solid #bbb; padding: 6px; vertical-align: top; overflow-wrap: anywhere; }
        th { background: #eee; } thead { display: table-header-group; } tr { break-inside: avoid; }
        pre { white-space: pre-wrap; overflow-wrap: anywhere; padding: 10px; background: #f3f3f3; }
        code { font-family: ui-monospace, monospace; } blockquote { border-left: 3px solid #aaa; margin-left: 0; padding-left: 12px; }
        @media print { body { margin: 0; } }
        </style></head><body>\(body)</body></html>
        """
    }
}
