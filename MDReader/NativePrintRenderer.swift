#if os(macOS)
import AppKit
import SwiftDraw

/// Uses AppKit's text layout and pagination, without a web content process.
@MainActor
enum NativePrintRenderer {
    static func attributedDocument(_ source: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 11)
        var pele: PeleEngine?

        func inline(_ text: String, font: NSFont) -> NSMutableAttributedString {
            let result = NSMutableAttributedString()
            guard let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
                return NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
            }
            for run in parsed.runs {
                let intent = run.inlinePresentationIntent ?? []
                var runFont = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : font
                if intent.contains(.stronglyEmphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask) }
                var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: NSColor.black]
                if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
            }
            return result
        }

        func append(_ text: String, font: NSFont = NSFont.systemFont(ofSize: 11), style: NSMutableParagraphStyle = NSMutableParagraphStyle(), literal: Bool = false) {
            let content = literal ? NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black]) : inline(text, font: font)
            content.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: NSColor.black]))
            content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: content.length))
            result.append(content)
        }

        for block in MarkdownBlocks.parse(source) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 8
            switch block {
            case let .heading(level, text):
                append(text, font: .boldSystemFont(ofSize: level == 1 ? 22 : level == 2 ? 18 : 14), style: style)
            case let .paragraph(text), let .item(text): append(text, style: style)
            case let .mermaid(text):
                do {
                    if pele == nil { pele = try PeleEngine() }
                    let svg = try pele!.render(text, width: 540)
                    let scale = min(1, 520 / svg.size.width, 650 / svg.size.height)
                    let size = CGSize(width: svg.size.width * scale, height: svg.size.height * scale)
                    guard let data = try? svg.pdfData(), let image = NSImage(data: data) else {
                        throw PeleRenderError.invalid("Could not prepare diagram for printing.")
                    }
                    image.size = size
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
                    result.append(NSAttributedString(attachment: attachment))
                    append("", style: style)
                } catch {
                    append("Diagram could not be rendered: \(error.localizedDescription)", style: style)
                    append(text, font: .monospacedSystemFont(ofSize: 10, weight: .regular), style: style, literal: true)
                }
            case let .code(text): append(text, font: .monospacedSystemFont(ofSize: 10, weight: .regular), style: style, literal: true)
            case let .quote(text):
                style.headIndent = 12; style.firstLineHeadIndent = 12
                append(text, style: style)
            case .rule: append("────────────────────", style: style, literal: true)
            case let .table(headers, alignments, rows):
                let table = NSTextTable()
                table.numberOfColumns = headers.count
                table.collapsesBorders = true
                table.layoutAlgorithm = .fixedLayoutAlgorithm
                for (rowIndex, cells) in ([headers] + rows).enumerated() {
                    for (column, text) in cells.enumerated() {
                        let cell = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                        cell.setValue(100 / CGFloat(headers.count), type: .percentageValueType, for: .width)
                        cell.setWidth(5, type: .absoluteValueType, for: .padding)
                        cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                        cell.setBorderColor(.gray)
                        cell.verticalAlignment = .top
                        if rowIndex == 0 { cell.backgroundColor = NSColor(white: 0.93, alpha: 1) }
                        let paragraph = NSMutableParagraphStyle()
                        paragraph.textBlocks = [cell]
                        paragraph.alignment = alignments[column] == .right ? .right : alignments[column] == .center ? .center : .left
                        append(text, font: rowIndex == 0 ? .boldSystemFont(ofSize: 10) : bodyFont, style: paragraph)
                    }
                }
                append("", style: style)
            }
        }
        return result
    }

    static func textView(source: String, width: CGFloat) -> NSTextView {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.isEditable = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.backgroundColor = .white
        view.textColor = .black
        view.appearance = NSAppearance(named: .aqua)
        view.textContainerInset = NSSize(width: 0, height: 8)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textStorage?.setAttributedString(attributedDocument(source))
        if let container = view.textContainer, let layout = view.layoutManager {
            layout.ensureLayout(for: container)
            view.setFrameSize(NSSize(width: width, height: max(1, layout.usedRect(for: container).height + 16)))
        }
        return view
    }

    static func printDocument(source: String, title: String) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 36; info.bottomMargin = 36
        info.leftMargin = 36; info.rightMargin = 36
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        let view = textView(source: source, width: max(72, info.paperSize.width - info.leftMargin - info.rightMargin))
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }
}

#endif
