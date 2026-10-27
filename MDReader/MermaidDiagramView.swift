import SwiftUI
import SwiftDraw

struct MermaidDiagramView: View {
    let source: String
    let fontSize: Double
    @Environment(\.colorScheme) private var colorScheme
    @State private var svg: SVG?
    @State private var error: String?
    @State private var width: Double = 760

    private var request: PeleRenderService.Key {
        .init(source: source, dark: colorScheme == .dark, fontSize: fontSize, width: width)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let svg {
                SVGView(svg: svg).resizable().scaledToFit()
                    .accessibilityLabel("Mermaid diagram")
                    .accessibilityValue(source)
            } else if let error {
                Label("Diagram could not be rendered", systemImage: "exclamationmark.triangle")
                    .font(.headline).foregroundStyle(.secondary)
                Text(error).font(.caption).textSelection(.enabled)
            } else {
                ProgressView("Rendering diagram…").padding()
            }
            DisclosureGroup("Mermaid source") {
                ScrollView(.horizontal) {
                    Text(source).font(.system(size: fontSize, design: .monospaced)).textSelection(.enabled)
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { updateWidth(proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, value in updateWidth(value) }
            }
        }
        .task(id: request) {
            svg = nil; error = nil
            do {
                try await Task.sleep(for: .milliseconds(100))
                let rendered = try await PeleRenderService.shared.render(request)
                guard !Task.isCancelled else { return }
                svg = rendered
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func updateWidth(_ value: Double) {
        // Quantize resize events so dragging a divider doesn't render every pixel.
        width = max(160, ((value - 32) / 40).rounded() * 40)
    }
}
