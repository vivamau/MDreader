#if os(macOS)
import AppKit
import XCTest
@testable import MDReaderRendering

final class AppearanceTests: XCTestCase {
    @MainActor func testSystemAppearanceIgnoresWindowOverride() {
        let app = NSApplication.shared
        let original = app.appearance
        defer { app.appearance = original }
        app.appearance = NSAppearance(named: .darkAqua)
        let system = SystemAppearance(application: app)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        WindowAppearance.apply(to: window, colorScheme: .light)
        XCTAssertEqual(system.colorScheme, .dark)
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        app.appearance = NSAppearance(named: .aqua)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(system.colorScheme, .light)
        app.appearance = NSAppearance(named: .darkAqua)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(system.colorScheme, .dark)
    }

    @MainActor func testSystemClearsOverridesAndTracksApplicationAppearance() {
        let app = NSApplication.shared
        let original = app.appearance
        defer { app.appearance = original }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        // Register the window with AppKit so live application-appearance changes propagate.
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        app.appearance = NSAppearance(named: .darkAqua)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        WindowAppearance.apply(to: window, colorScheme: .light)
        XCTAssertEqual(window.appearance?.name, .aqua)
        WindowAppearance.apply(to: window, colorScheme: nil)
        XCTAssertNil(window.appearance)
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        app.appearance = NSAppearance(named: .aqua)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        WindowAppearance.apply(to: window, colorScheme: .dark)
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        WindowAppearance.apply(to: window, colorScheme: nil)
        XCTAssertNil(window.appearance)
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
    }
}
#endif
