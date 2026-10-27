// swift-tools-version:6.0
// Local manifest: upstream source is unchanged; CLI and upstream test targets are omitted.
import PackageDescription
let package = Package(name: "SwiftDraw", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "SwiftDraw", targets: ["SwiftDraw"])], targets: [
.target(name: "SwiftDraw", dependencies: ["SwiftDrawDOM"], path: "SwiftDraw/Sources", swiftSettings: [.enableUpcomingFeature("ExistentialAny"), .enableUpcomingFeature("InternalImportsByDefault"), .enableUpcomingFeature("MemberImportVisibility"), .swiftLanguageMode(.v6)]),
.target(name: "SwiftDrawDOM", path: "DOM/Sources")])
