// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "MDReaderRendering", platforms: [.macOS(.v14), .iOS(.v17)], dependencies: [.package(path: "Vendor/SwiftDraw")], targets: [
    .target(name: "MDReaderRendering", dependencies: [.product(name: "SwiftDraw", package: "SwiftDraw")], path: "MDReader", exclude: ["DocumentWorkspace.swift", "MDReaderApp.swift", "EditorView.swift", "MermaidDiagramView.swift", "MarkdownDocument.swift", "PrintPreview.swift", "Info.plist", "MDReader.entitlements", "Resources/Pele-PROVENANCE.md"], sources: ["MarkdownBlocks.swift", "PrintHTML.swift", "PeleRenderer.swift", "NativePrintRenderer.swift", "WindowAppearance.swift", "RecentDocuments.swift"], resources: [.copy("Resources/pele.global.js"), .copy("Resources/Pele-LICENSE.txt"), .copy("Resources/SwiftDraw-LICENSE.txt")], swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "RenderingTests", dependencies: ["MDReaderRendering"], path: "Tests/Rendering")
])
