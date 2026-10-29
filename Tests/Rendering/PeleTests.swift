import XCTest
@testable import MDReaderRendering

final class PeleTests: XCTestCase {
    func testFences() {
        XCTAssertEqual(MarkdownBlocks.parse("```mermaid\nflowchart LR\n A --> B\n```"), [.mermaid("flowchart LR\n A --> B")])
        XCTAssertEqual(MarkdownBlocks.parse("~~~MERMAID\r\nsequenceDiagram\r\n A->>B: Hi\r\n~~~"), [.mermaid("sequenceDiagram\n A->>B: Hi")])
        XCTAssertEqual(MarkdownBlocks.parse("```swift\nlet x = 1\n```"), [.code("let x = 1")])
        XCTAssertEqual(MarkdownBlocks.parse("```mermaid\nflowchart LR"), [.mermaid("flowchart LR")])
    }

    func testNativeRendering() throws {
        let engine = try PeleEngine()
        let sources = [
            "flowchart LR\n A[Start] --> B{Ready?}\n B --> C[Done]",
            "sequenceDiagram\n Alice->>Bob: Hello\n Bob-->>Alice: Hi",
            "classDiagram\n Animal <|-- Duck\n Animal : +int age",
            "stateDiagram-v2\n [*] --> Idle\n Idle --> Running",
            "pie title Pets\n \"Dogs\" : 4\n \"Cats\" : 3",
            "gantt\n title Plan\n dateFormat YYYY-MM-DD\n section Build\n Work :a1, 2026-10-01, 5d"
        ]
        for source in sources {
            for dark in [false, true] {
                let svg = try engine.render(source, dark: dark)
                XCTAssertGreaterThan(svg.size.width, 0)
                XCTAssertGreaterThan(svg.size.height, 0)
                XCTAssertFalse(try svg.pdfData().isEmpty)
            }
        }
    }

    func testInvalidSourceAndLimits() throws {
        let engine = try PeleEngine()
        XCTAssertThrowsError(try engine.render("not a diagram"))
        XCTAssertThrowsError(try engine.render(String(repeating: "x", count: 50_001)))
        XCTAssertThrowsError(try engine.render("flowchart LR\n A[unfinished"))
    }

    func testThemeResolution() {
        let xml = "<svg fill=\"var(--_fg)\" stroke=\"var(--_b)\"><text>A</text></svg>"
        let dark = PeleEngine.resolveTheme(xml, dark: true, fontSize: 20)
        XCTAssertTrue(dark.contains("#f4f4f5"))
        XCTAssertTrue(dark.contains("font-size=\"20.0\""))
        XCTAssertFalse(dark.contains("var("))
    }

    func testPrintFallbackAndImageHook() {
        let source = "```mermaid\nflowchart LR\n A --> B\n```"
        XCTAssertTrue(PrintHTML.document(source, title: "Test").contains("Mermaid diagram source"))
        XCTAssertTrue(PrintHTML.document(source, title: "Test", diagramHTML: { _ in "<img alt=\"diagram\">" }).contains("<img alt=\"diagram\">"))
        let styled = PrintHTML.document("Body", title: "Test", fontChoice: .georgia, fontSize: 18)
        XCTAssertTrue(styled.contains("font: 18.0pt Georgia, serif"))
    }
}

#if os(macOS)
import AppKit
extension PeleTests {
    @MainActor func testNativePrintIncludesDiagramAttachment() throws {
        _ = NSApplication.shared
        let source = "# Diagram\n\n```mermaid\nflowchart LR\n A --> B\n```\n\n| A | B |\n|---|---|\n| x | y |"
        let view = NativePrintRenderer.textView(source: source, width: 540)
        XCTAssertGreaterThan(view.frame.height, 0)
        let storage = try XCTUnwrap(view.textStorage)
        var attachments = 0
        var diagramImage: NSImage?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment,
               let image = (attachment.attachmentCell as? NSTextAttachmentCell)?.image,
               image.isValid, image.tiffRepresentation?.isEmpty == false {
                attachments += 1
                diagramImage = image
            }
        }
        XCTAssertEqual(attachments, 1)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(diagramImage?.tiffRepresentation)))
        let containsInk = stride(from: 0, to: bitmap.pixelsHigh, by: 4).contains { y in
            stride(from: 0, to: bitmap.pixelsWide, by: 4).contains { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return color.alphaComponent > 0.1
                    && min(color.redComponent, color.greenComponent, color.blueComponent) < 0.9
            }
        }
        XCTAssertTrue(containsInk, "The print attachment should contain rendered diagram pixels.")
    }

    @MainActor func testNativePrintUsesSelectedFontAndSize() throws {
        _ = NSApplication.shared
        let document = NativePrintRenderer.attributedDocument("Print body", fontChoice: .georgia, fontSize: 18)
        let selectedFont = try XCTUnwrap(document.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(selectedFont.pointSize, 18, accuracy: 0.1)
        XCTAssertTrue(selectedFont.familyName?.localizedCaseInsensitiveContains("Georgia") == true)
    }

    @MainActor func testVisualFixtures() throws {
        _ = NSApplication.shared
        guard let directory = ProcessInfo.processInfo.environment["MDREADER_TEST_ARTIFACTS"] else { return }
        let engine = try PeleEngine()
        let source = "flowchart LR\n A[Write Markdown] --> B{Valid?}\n B -->|Yes| C[Render diagram]\n B -->|No| D[Show error]"
        for dark in [false, true] {
            let svg = try engine.render(source, dark: dark)
            let rendered = svg.rasterize()
            let image = NSImage(size: rendered.size)
            image.lockFocus()
            (dark ? NSColor(white: 0.095, alpha: 1) : NSColor.white).setFill()
            NSRect(origin: .zero, size: image.size).fill()
            rendered.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            image.unlockFocus()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(dark ? "pele-dark.png" : "pele-light.png"))
        }
    }
}
#endif
