import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private enum EditorMode: String, CaseIterable, Identifiable {
    case edit = "Edit", split = "Split", preview = "Preview"
    var id: Self { self }
}

private enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

private extension Color {
    init(rgb: Int) {
        self.init(.sRGB, red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }
    var rgb: Int? {
        #if os(macOS)
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let components = (color.redComponent, color.greenComponent, color.blueComponent)
        #else
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        let components = (red, green, blue)
        #endif
        func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return (byte(components.0) << 16) | (byte(components.1) << 8) | byte(components.2)
    }
}

struct EditorView: View {
    @Binding var document: MarkdownDocument
    var documentTitle: String = "Markdown Document"
    @Environment(\.colorScheme) private var systemColorScheme
    #if os(macOS)
    @StateObject private var systemAppearance = SystemAppearance()
    #endif
    @State private var showingSettings = false
    @State private var showingPrint = false
    @SceneStorage("editorMode") private var mode: EditorMode = .split
    @SceneStorage("editorSplitFraction") private var savedSplitFraction = 0.5
    @State private var splitFraction = 0.5
    @AppStorage("editorFontSize") private var fontSize = 15.0
    @AppStorage("appTheme") private var theme: AppTheme = .system
    @AppStorage("editorFontFamily") private var editorFont: ReaderFont = .monospaced
    @AppStorage("previewFontFamily") private var previewFont: ReaderFont = .system
    @AppStorage("lightBackgroundRGB") private var lightBackground = 0xFFFFFF
    @AppStorage("darkBackgroundRGB") private var darkBackground = 0x1C1C1E
    @AppStorage("lightFontRGB") private var lightFontColor = 0x1F1F1F
    @AppStorage("darkFontRGB") private var darkFontColor = 0xF4F4F5

    private var resolvedTheme: ColorScheme {
        #if os(macOS)
        theme.colorScheme ?? systemAppearance.colorScheme
        #else
        theme.colorScheme ?? systemColorScheme
        #endif
    }
    private var backgroundRGB: Int {
        resolvedTheme == .dark ? darkBackground : lightBackground
    }
    private var editorBackgroundRGB: Int {
        // Keep the chosen color and hue, but separate the source editor from the
        // rendered page by blending a small amount of black into each channel.
        func darken(_ channel: Int) -> Int { Int((Double(channel) * 0.94).rounded()) }
        return (darken((backgroundRGB >> 16) & 255) << 16)
            | (darken((backgroundRGB >> 8) & 255) << 8)
            | darken(backgroundRGB & 255)
    }
    private var documentTextColor: Color {
        Color(rgb: resolvedTheme == .dark ? darkFontColor : lightFontColor)
    }
    private var canvasScheme: ColorScheme {
        // Choose the higher-contrast text appearance even for a custom background.
        func linear(_ value: Int) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear((backgroundRGB >> 16) & 255)
            + 0.7152 * linear((backgroundRGB >> 8) & 255) + 0.0722 * linear(backgroundRGB & 255)
        return luminance > 0.179 ? .light : .dark
    }
    private var preview: some View {
        MarkdownPreview(source: document.text, fontSize: fontSize, fontChoice: previewFont, canvasBackground: Color(rgb: backgroundRGB), textColor: documentTextColor)
            .environment(\.colorScheme, canvasScheme)
    }


    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                if mode == .preview {
                    preview
                } else if mode == .split {
                    splitView(size: geometry.size)
                } else { editor }
            }
            Divider()
            HStack(spacing: 16) {
                Label("Markdown", systemImage: "doc.plaintext")
                Spacer()
                Text("\(document.text.split(whereSeparator: { $0.isWhitespace }).count) words")
                Text("\(document.text.count) characters")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.background)
        }
        .background(.background)
        .onAppear { splitFraction = savedSplitFraction }
        #if os(macOS)
        // Always provide a resolved preference: nil can leave SwiftUI's window chrome stale.
        .preferredColorScheme(resolvedTheme)
        #else
        .background {
            WindowAppearance(colorScheme: theme.colorScheme)
                .frame(width: 0, height: 0)
        }
        #endif
        .focusedSceneValue(\.printDocument, { showingPrint = true })
        .sheet(isPresented: $showingPrint) {
            PrintPreview(
                source: document.text,
                title: documentTitle,
                fontChoice: previewFont,
                fontSize: fontSize
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Picker("View", selection: $mode) {
                        ForEach(EditorMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    .help("Choose editor, split view, or preview")

                    Button("Print…", systemImage: "printer") { showingPrint = true }
                        .labelStyle(.iconOnly)
                        .help("Print the rendered Markdown document")

                    Button("Settings", systemImage: "gearshape") { showingSettings.toggle() }
                        .labelStyle(.iconOnly)
                        .help("Settings")
                        .popover(isPresented: $showingSettings) { settings }

                }
            }
        }
        #if os(macOS)
        // Mask the document canvas at the toolbar/tab boundary. The native
        // material stays translucent without inheriting the selected page color.
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
        .environment(\.colorScheme, resolvedTheme)
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 350)
        #endif
    }

    private func colorBinding(_ value: Binding<Int>) -> Binding<Color> {
        Binding(get: { Color(rgb: value.wrappedValue) }, set: { color in
            if let rgb = color.rgb { value.wrappedValue = rgb }
        })
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done") { showingSettings = false }
            }.padding()
            Divider()
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        ForEach(AppTheme.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    ColorPicker("Light background", selection: colorBinding($lightBackground), supportsOpacity: false)
                    ColorPicker("Light font color", selection: colorBinding($lightFontColor), supportsOpacity: false)
                    ColorPicker("Dark background", selection: colorBinding($darkBackground), supportsOpacity: false)
                    ColorPicker("Dark font color", selection: colorBinding($darkFontColor), supportsOpacity: false)
                }
                Section("Fonts") {
                    Picker("Editor font", selection: $editorFont) {
                        ForEach(ReaderFont.allCases) { font in Text(font.rawValue).font(font.font(size: 14)).tag(font) }
                    }
                    Picker("Preview font", selection: $previewFont) {
                        ForEach(ReaderFont.allCases) { font in Text(font.rawValue).font(font.font(size: 14)).tag(font) }
                    }
                    Stepper("Font size: \(Int(fontSize)) pt", value: $fontSize, in: 11...32)
                }
                Section {
                    Button("Reset to Defaults") {
                        theme = .system; editorFont = .monospaced; previewFont = .system
                        fontSize = 15; lightBackground = 0xFFFFFF; darkBackground = 0x1C1C1E
                        lightFontColor = 0x1F1F1F; darkFontColor = 0xF4F4F5
                    }
                }
            }
            .formStyle(.grouped)
        }
        .font(.body)
        .foregroundStyle(.primary)
        .frame(idealWidth: 360, idealHeight: 560)
        #if os(macOS)
        .frame(width: 360, height: 560)
        #endif
    }

    private var editor: some View {
        VStack(spacing: 0) {
            MarkdownFormattingBar(text: $document.text)
            Divider()
            TextEditor(text: $document.text)
                .font(editorFont.font(size: fontSize))
                .foregroundStyle(documentTextColor)
                .scrollContentBackground(.hidden)
                .padding(12)
                .accessibilityLabel("Markdown source")
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
        }
        .background(Color(rgb: editorBackgroundRGB))
        .environment(\.colorScheme, canvasScheme)
    }

    @ViewBuilder
    private func splitView(size: CGSize) -> some View {
        #if os(macOS)
        // Use AppKit's split-view implementation through SwiftUI. It owns the
        // drag loop and cursor rects, so resizing remains smooth even while the
        // preview is laying out diagrams and other expensive content.
        if size.width >= 650 {
            HSplitView {
                editor.frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
                preview.frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VSplitView {
                editor.frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
                preview.frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
            }
        }
        #else
        if size.width >= 650 {
            let available = max(1, size.width - ResizableSplitDivider.thickness)
            HStack(spacing: 0) {
                editor.frame(width: available * splitFraction)
                ResizableSplitDivider(
                    orientation: .columns,
                    totalLength: available,
                    fraction: $splitFraction,
                    onCommit: { savedSplitFraction = $0 }
                )
                preview.frame(width: available * (1 - splitFraction))
            }
        } else {
            let available = max(1, size.height - ResizableSplitDivider.thickness)
            VStack(spacing: 0) {
                editor.frame(height: available * splitFraction)
                ResizableSplitDivider(
                    orientation: .rows,
                    totalLength: available,
                    fraction: $splitFraction,
                    onCommit: { savedSplitFraction = $0 }
                )
                preview.frame(height: available * (1 - splitFraction))
            }
        }
        #endif
    }
}

#if os(iOS)
private struct ResizableSplitDivider: View {
    enum Orientation { case columns, rows }
    static let thickness: CGFloat = 12

    let orientation: Orientation
    let totalLength: CGFloat
    @Binding var fraction: Double
    let onCommit: (Double) -> Void
    @State private var dragStart: Double?
    @State private var hovering = false
    @State private var dragging = false

    private var minimumFraction: Double {
        min(0.4, Double((orientation == .columns ? 220 : 140) / max(1, totalLength)))
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(hovering || dragging ? 0.65 : 0.3))
                .frame(
                    width: orientation == .columns ? 1 : nil,
                    height: orientation == .rows ? 1 : nil
                )
        }
        .frame(
            width: orientation == .columns ? Self.thickness : nil,
            height: orientation == .rows ? Self.thickness : nil
        )
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = fraction
                        dragging = true
                    }
                    let translation = orientation == .columns ? value.translation.width : value.translation.height
                    let proposed = (dragStart ?? fraction) + Double(translation / max(1, totalLength))
                    fraction = min(1 - minimumFraction, max(minimumFraction, proposed))
                }
                .onEnded { _ in
                    dragStart = nil
                    dragging = false
                    onCommit(fraction)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Resize editor and preview")
        .accessibilityValue("Editor \(Int(fraction * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let proposed = fraction + (direction == .increment ? 0.05 : -0.05)
            fraction = min(1 - minimumFraction, max(minimumFraction, proposed))
            onCommit(fraction)
        }
    }
}
#endif

struct MarkdownPreview: View {
    let source: String
    let fontSize: Double
    var fontChoice: ReaderFont = .system
    var canvasBackground: Color = .white
    var textColor: Color = .primary
    @State private var blocks: [MarkdownBlock] = []

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if source.isEmpty {
                    ContentUnavailableView("Your words, beautifully rendered", systemImage: "doc.richtext", description: Text("Write Markdown in the editor to see a preview here."))
                        .padding(.top, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            blockView(block)
                        }
                    }
                    .font(fontChoice.font(size: fontSize))
                    .foregroundStyle(textColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, max(16, geometry.size.width * 0.05))
                    .padding(.vertical, 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(canvasBackground)
        .task(id: source) {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            blocks = MarkdownBlocks.parse(source)
        }
        .accessibilityLabel("Markdown preview")
    }

    private func inline(_ text: String) -> Text {
        let value = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        return Text(value ?? AttributedString(text))
    }

    private func tableCell(_ text: String, alignment: TableAlignment, header: Bool) -> some View {
        let horizontal: Alignment = alignment == .center ? .center : alignment == .right ? .trailing : .leading
        let multiline: TextAlignment = alignment == .center ? .center : alignment == .right ? .trailing : .leading
        return inline(text)
            .font(fontChoice.font(size: fontSize))
            .fontWeight(header ? .semibold : .regular)
            .multilineTextAlignment(multiline)
            .frame(minWidth: 60, maxWidth: 300, alignment: horizontal)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .overlay(Rectangle().strokeBorder(.secondary.opacity(0.12), lineWidth: 0.5))
            .accessibilityAddTraits(header ? .isHeader : [])
    }

    @ViewBuilder private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inline(text)
                .font(fontChoice.font(size: fontSize * (level == 1 ? 2 : level == 2 ? 1.6 : 1.25)))
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
        case let .paragraph(text), let .item(text):
            inline(text).font(fontChoice.font(size: fontSize)).lineSpacing(5)
        case let .mermaid(text):
            MermaidDiagramView(source: text, fontSize: fontSize)
        case let .code(text):
            ScrollView(.horizontal) {
                Text(text).font(.system(size: fontSize, design: .monospaced)).padding(16)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        case let .quote(text):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.4)).frame(width: 3)
                inline(text).foregroundStyle(textColor).italic()
            }.fixedSize(horizontal: false, vertical: true)
        case let .table(headers, alignments, rows):
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(headers.indices, id: \.self) { column in
                            tableCell(headers[column], alignment: alignments[column], header: true)
                        }
                    }
                    .background(Color.secondary.opacity(0.12))
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(headers.indices, id: \.self) { column in
                                tableCell(rows[row][column], alignment: alignments[column], header: false)
                            }
                        }
                        .background(Color.secondary.opacity(row.isMultiple(of: 2) ? 0.035 : 0.075))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.25)))
                .padding(.bottom, 8)
            }
        case .rule:
            Divider()
        }
    }
}
