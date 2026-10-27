#if os(macOS)
import AppKit
import XCTest
@testable import MDReaderRendering

final class CloseTestDocument: NSDocument {
    nonisolated(unsafe) var text = "original"
    override class var autosavesInPlace: Bool { true }
    override class var readableTypes: [String] { ["public.plain-text"] }
    override class var writableTypes: [String] { ["public.plain-text"] }
    override func data(ofType typeName: String) throws -> Data { Data(text.utf8) }
    override func read(from data: Data, ofType typeName: String) throws {
        text = String(decoding: data, as: UTF8.self)
    }
}

final class DocumentCloseTests: XCTestCase {
    @MainActor private func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    @MainActor func testNativeConfirmationSaveCancelAndDiscardAfterAutosave() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "NSCloseAlwaysConfirmsChanges")
        defaults.set(true, forKey: "NSCloseAlwaysConfirmsChanges")
        defer {
            if let old { defaults.set(old, forKey: "NSCloseAlwaysConfirmsChanges") }
            else { defaults.removeObject(forKey: "NSCloseAlwaysConfirmsChanges") }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("original".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try CloseTestDocument(contentsOf: url, ofType: "public.plain-text")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        document.addWindowController(controller)
        window.makeKeyAndOrderFront(nil)
        defer { document.updateChangeCount(.changeCleared); document.close() }
        document.text = "modified"
        document.updateChangeCount(.changeDone)

        for choice in ["Cancel", "Discard", "Save"] {
            if choice == "Save" {
                document.text = "modified"
                document.updateChangeCount(.changeDone)
            }
            if choice == "Discard" {
                document.text = "discard this edit"
                document.updateChangeCount(.changeDone)
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    document.autosave(withImplicitCancellability: false) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "discard this edit")
            }
            let review = DocumentCloseReview()
            let result = Task { await review.confirm([document]) }
            for _ in 0..<100 where window.attachedSheet == nil {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard let sheet = window.attachedSheet, let view = sheet.contentView else {
                XCTFail("Missing confirmation for \(choice), edited=\(document.isDocumentEdited)")
                result.cancel()
                return
            }
            let available = buttons(in: view)
            let button = available.first {
                choice == "Discard" ? ["Don't Save", "Don’t Save", "Revert Changes"].contains($0.title) : $0.title == choice
            }
            guard let button else {
                XCTFail("Missing close choice; buttons: \(available.map(\.title))")
                window.endSheet(sheet, returnCode: .cancel)
                _ = await result.value
                return
            }
            button.performClick(nil)
            let allowed = await result.value
            XCTAssertEqual(allowed, choice != "Cancel")
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), choice == "Save" ? "modified" : "original")
            if choice == "Cancel" { XCTAssertTrue(document.isDocumentEdited) }
        }
    }
}
#endif
