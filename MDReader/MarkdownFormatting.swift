import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum MarkdownFormatCommand {
    case heading(Int)
    case bold
    case italic
    case underline
    case inlineCode
    case link
    case quote
    case bulletedList
    case numberedList
    case codeBlock
}

private struct MarkdownEdit {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

@MainActor
private enum MarkdownFormatter {
    static func apply(_ command: MarkdownFormatCommand, to text: Binding<String>) {
        #if os(macOS)
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            let edit = makeEdit(command, text: textView.string, selection: textView.selectedRange())
            textView.insertText(edit.replacement, replacementRange: edit.range)
            textView.setSelectedRange(edit.selection)
            return
        }
        #else
        if let textView = activeTextView() {
            let edit = makeEdit(command, text: textView.text ?? "", selection: textView.selectedRange)
            textView.replace(textView.textRange(from: textView.position(from: textView.beginningOfDocument, offset: edit.range.location)!, to: textView.position(from: textView.beginningOfDocument, offset: edit.range.location + edit.range.length)!)!, withText: edit.replacement)
            textView.selectedRange = edit.selection
            return
        }
        #endif

        let edit = makeEdit(command, text: text.wrappedValue, selection: NSRange(location: (text.wrappedValue as NSString).length, length: 0))
        text.wrappedValue = (text.wrappedValue as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    private static func makeEdit(_ command: MarkdownFormatCommand, text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString

        func wrapped(prefix: String, suffix: String, placeholder: String) -> MarkdownEdit {
            let selected = selection.length > 0 ? source.substring(with: selection) : placeholder
            let replacement = prefix + selected + suffix
            let selectedRange = NSRange(
                location: selection.location + prefix.utf16.count,
                length: selected.utf16.count
            )
            return MarkdownEdit(range: selection, replacement: replacement, selection: selectedRange)
        }

        func lines(_ transform: ([String]) -> [String]) -> MarkdownEdit {
            let target = source.lineRange(for: selection)
            let original = source.substring(with: target)
            let hasTrailingNewline = original.hasSuffix("\n")
            var values = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if hasTrailingNewline, values.last == "" { values.removeLast() }
            var replacement = transform(values).joined(separator: "\n")
            if hasTrailingNewline { replacement += "\n" }
            return MarkdownEdit(
                range: target,
                replacement: replacement,
                selection: NSRange(location: target.location, length: replacement.utf16.count)
            )
        }

        switch command {
        case let .heading(level):
            return lines { values in
                values.map { line in
                    let stripped = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                    return String(repeating: "#", count: level) + " " + stripped
                }
            }
        case .bold: return wrapped(prefix: "**", suffix: "**", placeholder: "bold text")
        case .italic: return wrapped(prefix: "*", suffix: "*", placeholder: "italic text")
        case .underline: return wrapped(prefix: "<u>", suffix: "</u>", placeholder: "underlined text")
        case .inlineCode: return wrapped(prefix: "`", suffix: "`", placeholder: "code")
        case .link: return wrapped(prefix: "[", suffix: "](https://)", placeholder: "link text")
        case .quote:
            return lines { $0.map { $0.isEmpty ? ">" : "> " + $0 } }
        case .bulletedList:
            return lines { $0.map { $0.isEmpty ? "- " : "- " + $0.replacingOccurrences(of: #"^[-*+]\s+"#, with: "", options: .regularExpression) } }
        case .numberedList:
            return lines { values in
                values.enumerated().map { index, line in
                    let stripped = line.replacingOccurrences(of: #"^\d+[.)]\s+"#, with: "", options: .regularExpression)
                    return "\(index + 1). \(stripped)"
                }
            }
        case .codeBlock:
            return wrapped(prefix: "```\n", suffix: "\n```", placeholder: "code")
        }
    }

    #if os(iOS)
    private static func activeTextView() -> UITextView? {
        func find(in view: UIView) -> UITextView? {
            if let textView = view as? UITextView, textView.isFirstResponder { return textView }
            for child in view.subviews {
                if let result = find(in: child) { return result }
            }
            return nil
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .compactMap { $0.rootViewController?.view }
            .compactMap(find)
            .first
    }
    #endif
}

struct MarkdownFormattingBar: View {
    @Binding var text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Menu {
                    ForEach(1...3, id: \.self) { level in
                        Button("Heading \(level)") { apply(.heading(level)) }
                    }
                } label: {
                    Label("Heading", systemImage: "textformat.size")
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                }
                .help("Add a heading")

                formatButton("Bold", symbol: "bold", command: .bold)
                formatButton("Italic", symbol: "italic", command: .italic)
                formatButton("Underline", symbol: "underline", command: .underline)
                formatButton("Inline Code", symbol: "chevron.left.forwardslash.chevron.right", command: .inlineCode)
                formatButton("Link", symbol: "link", command: .link)

                Divider().frame(height: 18)

                formatButton("Quote", symbol: "text.quote", command: .quote)
                formatButton("Bulleted List", symbol: "list.bullet", command: .bulletedList)
                formatButton("Numbered List", symbol: "list.number", command: .numberedList)
                formatButton("Code Block", symbol: "curlybraces", command: .codeBlock)
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 20, weight: .medium))
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown formatting")
    }

    private func formatButton(_ title: String, symbol: String, command: MarkdownFormatCommand) -> some View {
        Button(title, systemImage: symbol) { apply(command) }
            .labelStyle(.iconOnly)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .help(title)
            .accessibilityLabel(title)
    }

    private func apply(_ command: MarkdownFormatCommand) {
        MarkdownFormatter.apply(command, to: $text)
    }
}
