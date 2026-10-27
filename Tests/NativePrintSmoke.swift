#if os(macOS)
import AppKit

@main
struct NativePrintSmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let source = CommandLine.arguments.count > 1
            ? try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            : "# Print check\n\n**Bold** text\n\n| A | B |\n|---|---|\n| Left | Right |"
        let start = Date()
        let view = NativePrintRenderer.textView(source: source, width: 540)
        precondition(view.frame.height.isFinite && view.frame.height > 0)
        precondition(!view.string.isEmpty)
        var tableCells = 0
        view.textStorage!.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: view.textStorage!.length)) { value, _, _ in
            if let paragraph = value as? NSParagraphStyle, !paragraph.textBlocks.isEmpty { tableCells += 1 }
        }
        precondition(tableCells > 0, "Expected native table cells")
        print("Native preview laid out successfully: \(tableCells) table cells, \(Int(view.frame.height))pt height, \(Date().timeIntervalSince(start)) seconds")
    }
}
#endif
