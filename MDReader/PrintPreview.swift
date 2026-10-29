import SwiftUI
import SwiftDraw
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PrintActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var printDocument: (() -> Void)? {
        get { self[PrintActionKey.self] }
        set { self[PrintActionKey.self] = newValue }
    }
}

struct DocumentPrintCommands: Commands {
    @FocusedValue(\.printDocument) private var printDocument
    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Print…") { printDocument?() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(printDocument == nil)
        }
    }
}

struct PrintPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var printError: String?
    let source: String
    let title: String
    let fontChoice: ReaderFont
    let fontSize: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Print Preview").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                #if os(macOS)
                Button("Print…", systemImage: "printer") {
                    NativePrintRenderer.printDocument(
                        source: source,
                        title: title,
                        fontChoice: fontChoice,
                        fontSize: fontSize
                    )
                }
                #else
                AirPrintButton(
                    source: source,
                    title: title,
                    fontChoice: fontChoice,
                    fontSize: fontSize,
                    error: $printError
                )
                    .frame(width: 90, height: 36)
                #endif
            }.padding()
            Divider()
            #if os(macOS)
            NativePrintPreview(source: source, fontChoice: fontChoice, fontSize: fontSize)
            #else
            MarkdownPreview(source: source, fontSize: fontSize, fontChoice: fontChoice)
                .environment(\.colorScheme, .light)
            #endif
            if let printError { Text(printError).foregroundStyle(.red).padding() }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }
}

#if os(macOS)
private struct NativePrintPreview: NSViewRepresentable {
    let source: String
    let fontChoice: ReaderFont
    let fontSize: Double
    final class Coordinator {
        var configuration = Configuration(source: "", fontChoice: .system, fontSize: 0)
    }
    struct Configuration: Equatable {
        let source: String
        let fontChoice: ReaderFont
        let fontSize: Double
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.documentView = NativePrintRenderer.textView(
            source: source,
            width: 540,
            fontChoice: fontChoice,
            fontSize: fontSize
        )
        context.coordinator.configuration = Configuration(source: source, fontChoice: fontChoice, fontSize: fontSize)
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let configuration = Configuration(source: source, fontChoice: fontChoice, fontSize: fontSize)
        guard context.coordinator.configuration != configuration else { return }
        nsView.documentView = NativePrintRenderer.textView(
            source: source,
            width: 540,
            fontChoice: fontChoice,
            fontSize: fontSize
        )
        context.coordinator.configuration = configuration
    }
}
#else
/// UIKit's markup formatter paginates local HTML directly; no WKWebView load is needed.
private struct AirPrintButton: UIViewRepresentable {
    let source: String
    let title: String
    let fontChoice: ReaderFont
    let fontSize: Double
    @Binding var error: String?

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Print…", for: .normal)
        button.setImage(UIImage(systemName: "printer"), for: .normal)
        button.addAction(UIAction { [weak button] _ in
            guard let button else { return }
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.jobName = title
            info.outputType = .general
            controller.printInfo = info
            let pele = try? PeleEngine()
            controller.printFormatter = UIMarkupTextPrintFormatter(markupText: PrintHTML.document(
                source,
                title: title,
                fontChoice: fontChoice,
                fontSize: fontSize
            ) { text in
                guard let svg = try? pele?.render(text, width: 540) else { return nil }
                let scale = min(1, 520 / svg.size.width, 650 / svg.size.height)
                let size = CGSize(width: svg.size.width * scale, height: svg.size.height * scale)
                guard let data = svg.rasterize(size: size, scale: 2).pngData() else { return nil }
                return "<img alt=\"Mermaid diagram\" style=\"max-width:100%;height:auto\" width=\"\(Int(size.width))\" src=\"data:image/png;base64,\(data.base64EncodedString())\">"
            })
            let completion: UIPrintInteractionController.CompletionHandler = { _, _, failure in
                if let failure { error = failure.localizedDescription }
            }
            let presented = controller.present(from: button.bounds, in: button, animated: true, completionHandler: completion)
            if !presented { error = "Printing is not available on this device." }
        }, for: .touchUpInside)
        return button
    }
    func updateUIView(_ uiView: UIButton, context: Context) {}
}
#endif
