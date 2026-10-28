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

enum ReaderFont: String, CaseIterable, Identifiable {
    case system = "System", serif = "Serif", rounded = "Rounded", monospaced = "Monospaced", georgia = "Georgia"
    var id: Self { self }
    func font(size: Double) -> Font {
        switch self {
        case .system: .system(size: size)
        case .serif: .system(size: size, design: .serif)
        case .rounded: .system(size: size, design: .rounded)
        case .monospaced: .system(size: size, design: .monospaced)
        case .georgia: .custom("Georgia", size: size)
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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if mode == .preview {
                    preview
                } else if mode == .split && geometry.size.width >= 650 {
                    HStack(spacing: 0) {
                        editor
                        Divider()
                        preview
                    }
                } else if mode == .split {
                    VStack(spacing: 0) {
                        editor
                        Divider()
                        preview
                    }
                } else { editor }
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
        }
        .background(.background)
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
            PrintPreview(source: document.text, title: documentTitle)
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
        .frame(idealWidth: 360, idealHeight: 500)
        #if os(macOS)
        .frame(width: 360, height: 500)
        #endif
    }

    private var editor: some View {
        TextEditor(text: $document.text)
            .font(editorFont.font(size: fontSize))
            .foregroundStyle(documentTextColor)
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Color(rgb: backgroundRGB))
            .environment(\.colorScheme, canvasScheme)
            .accessibilityLabel("Markdown source")
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
    }
}

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
