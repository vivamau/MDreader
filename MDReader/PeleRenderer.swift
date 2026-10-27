import Foundation
import JavaScriptCore
import SwiftDraw

enum PeleRenderError: LocalizedError {
    case unavailable, invalid(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "The bundled Pele renderer could not be loaded."
        case let .invalid(message): message
        }
    }
}

/// Each engine is confined to its caller's thread/actor. No DOM, web view, or network access.
final class PeleEngine {
    private let context: JSContext

    init() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "pele.global", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { throw PeleRenderError.unavailable }
        self.context = context
        context.evaluateScript(script)
        guard context.exception == nil, context.objectForKeyedSubscript("pele")?.isUndefined == false else {
            throw PeleRenderError.unavailable
        }
    }

    func render(_ source: String, dark: Bool = false, fontSize: Double = 16, width: Double = 760) throws -> SVG {
        guard source.utf8.count <= 50_000 else {
            throw PeleRenderError.invalid("This diagram exceeds the 50 KB rendering limit.")
        }
        context.exception = nil
        let options: [String: Any] = [
            "responsive": false, "fontSize": fontSize, "fontFamily": "Helvetica",
            "fontFamilyMono": "Menlo", "maxWidth": width, "autoDirection": false,
            "images": false, "links": false, "limit": 50_000, "outputLimit": 2_000_000, "maxEdges": 500
        ]
        let result = context.objectForKeyedSubscript("pele")?.invokeMethod("render", withArguments: [source, options])
        if let exception = context.exception {
            throw PeleRenderError.invalid(exception.toString() ?? "Invalid Mermaid diagram.")
        }
        guard let xml = result?.forProperty("svg")?.toString(),
              let svg = SVG(data: Data(Self.resolveTheme(xml, dark: dark, fontSize: fontSize).utf8)),
              svg.size.width.isFinite, svg.size.height.isFinite,
              svg.size.width > 0, svg.size.height > 0,
              svg.size.width <= 30_000, svg.size.height <= 30_000 else {
            throw PeleRenderError.invalid("The diagram could not be displayed by the native SVG renderer.")
        }
        return svg
    }

    /// Materialize Pele's CSS variables for native SVG readers, which have no browser CSS environment.
    static func resolveTheme(_ xml: String, dark: Bool, fontSize: Double) -> String {
        let palette: [String: String] = [
            "_bg": dark ? "#18181b" : "#ffffff", "_fg": dark ? "#f4f4f5" : "#1f1f1f",
            "_m": dark ? "#a1a1aa" : "#6e6e6e", "_l": dark ? "#e4e4e7" : "#1f1f1f",
            "_s": dark ? "#27272a" : "#f3f3f3", "_a": dark ? "#3f3f46" : "#e6e6e6",
            "_b": dark ? "#a1a1aa" : "#8a8a8a", "_c": dark ? "#93b4ff" : "#5b7bd5",
            "_r": "4", "_fm": "Menlo", "_w": "normal", "_hw": "bold", "_tw": "bold",
            "pele-font": "Helvetica", "pele-font-mono": "Menlo"
        ]
        var xml = xml
        let pattern = try! NSRegularExpression(pattern: #"var\(--([a-zA-Z0-9_-]+)(?:,([^()]*))?\)"#)
        for _ in 0..<8 {
            let matches = pattern.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            if matches.isEmpty { break }
            for match in matches.reversed() {
                guard let range = Range(match.range, in: xml), let keyRange = Range(match.range(at: 1), in: xml) else { continue }
                let key = String(xml[keyRange])
                let fallback = Range(match.range(at: 2), in: xml).map { String(xml[$0]) } ?? "inherit"
                xml.replaceSubrange(range, with: palette[key] ?? fallback)
            }
        }
        // Pele emits the root font size through CSS shorthand; native readers need explicit attributes.
        if let range = xml.range(of: "<svg ") {
            xml.replaceSubrange(range, with: "<svg font-size=\"\(fontSize)\" font-family=\"Helvetica\" ")
        }
        return xml
    }
}

actor PeleRenderService {
    static let shared = PeleRenderService()
    private var engine: PeleEngine?
    private var cache: [Key: SVG] = [:]
    struct Key: Hashable, Sendable {
        let source: String
        let dark: Bool
        let fontSize: Double
        let width: Double
    }

    func render(_ key: Key) throws -> SVG {
        if let cached = cache[key] { return cached }
        if engine == nil { engine = try PeleEngine() }
        let svg = try engine!.render(key.source, dark: key.dark, fontSize: key.fontSize, width: key.width)
        if cache.count >= 24 { cache.removeAll() }
        cache[key] = svg
        return svg
    }
}
