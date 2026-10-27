import Foundation

/// A small, offline block parser. Inline formatting is handled by Apple's Markdown parser.
enum MarkdownBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case code(String)
    case mermaid(String)
    case quote(String)
    case item(String)
    case rule
    case table(headers: [String], alignments: [TableAlignment], rows: [[String]])
}

enum TableAlignment: Equatable {
    case left, center, right
}

enum MarkdownBlocks {
    /// Split on unescaped pipes, preserving empty cells and Markdown escapes.
    private static func tableCells(_ line: String) -> [String]? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        var cells: [String] = []
        var cell = ""
        var backslashes = 0
        var hasDelimiter = false
        var endsWithDelimiter = false
        for character in text {
            if character == "|" && backslashes % 2 == 0 {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
                hasDelimiter = true
                endsWithDelimiter = true
            } else {
                if character == "|" && backslashes % 2 == 1 {
                    cell.removeLast() // GFM escapes pipes even inside inline code.
                }
                cell.append(character)
                endsWithDelimiter = false
            }
            backslashes = character == "\\" ? backslashes + 1 : 0
        }
        guard hasDelimiter else { return nil }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        if text.first == "|" { cells.removeFirst() }
        if endsWithDelimiter { cells.removeLast() }
        return cells.isEmpty ? nil : cells
    }

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var fence: Character?
        var fenceLength = 0
        var mermaidFence = false
        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            defer { index += 1 }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let first = trimmed.first
            let run = trimmed.prefix { $0 == first }.count
            if let marker = fence {
                if first == marker && run >= fenceLength && trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty {
                    blocks.append(mermaidFence ? .mermaid(code.joined(separator: "\n")) : .code(code.joined(separator: "\n")))
                    code.removeAll(); fence = nil
                } else { code.append(line) }
                continue
            }
            if (first == "`" || first == "~") && run >= 3 {
                flush(); fence = first; fenceLength = run
                mermaidFence = trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces).lowercased() == "mermaid"
                continue
            }
            if trimmed.isEmpty { flush(); continue }
            if index + 1 < lines.count,
               let headers = tableCells(line),
               let separators = tableCells(lines[index + 1]),
               headers.count == separators.count,
               separators.allSatisfy({ $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil }) {
                flush()
                let alignments: [TableAlignment] = separators.map {
                    $0.hasSuffix(":") ? ($0.hasPrefix(":") ? .center : .right) : .left
                }
                index += 2
                var rows: [[String]] = []
                while index < lines.count, let cells = tableCells(lines[index]) {
                    rows.append(Array((cells + Array(repeating: "", count: headers.count)).prefix(headers.count)))
                    index += 1
                }
                index -= 1
                blocks.append(.table(headers: headers, alignments: alignments, rows: rows))
                continue
            }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flush(); blocks.append(.heading(hashes, String(trimmed.dropFirst(hashes + 1)))); continue
            }
            if ["---", "***", "___"].contains(trimmed) {
                flush(); blocks.append(.rule); continue
            }
            if trimmed.hasPrefix("> ") {
                flush(); blocks.append(.quote(String(trimmed.dropFirst(2)))); continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flush(); blocks.append(.item("• " + trimmed.dropFirst(2))); continue
            }
            if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                flush(); blocks.append(.item(trimmed)); continue
            }
            paragraph.append(line)
        }
        flush()
        if fence != nil { blocks.append(mermaidFence ? .mermaid(code.joined(separator: "\n")) : .code(code.joined(separator: "\n"))) }
        return blocks
    }
}
