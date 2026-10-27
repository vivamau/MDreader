#if os(macOS)
import AppKit
import XCTest
@testable import MDReaderRendering

final class DocumentWindowTests: XCTestCase {
    @MainActor func testTabDotAppearsImmediatelyAndSurvivesAutosave() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Note.md"
        defer { window.close() }
        let reference = DocumentWindowReference()
        reference.attach(to: window)
        reference.updateText("original")
        XCTAssertEqual(window.tab.title, "Note.md")
        reference.updateText("modified")
        XCTAssertTrue(reference.hasUnsavedChanges)
        XCTAssertEqual(window.tab.title, "● Note.md")
        // Native autosave changes must not clear the explicit-save indicator.
        window.isDocumentEdited = true
        window.isDocumentEdited = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(window.tab.title, "● Note.md")
        reference.saveCompleted(snapshot: "modified", successfully: false)
        XCTAssertTrue(reference.hasUnsavedChanges)
        // Edits made during an asynchronous save still need saving.
        reference.updateText("newer edit")
        reference.saveCompleted(snapshot: "modified", successfully: true)
        XCTAssertTrue(reference.hasUnsavedChanges)
        reference.saveCompleted(snapshot: "newer edit", successfully: true)
        XCTAssertFalse(reference.hasUnsavedChanges)
        XCTAssertEqual(window.tab.title, "Note.md")
        reference.updateText("another edit")
        reference.updateText("newer edit")
        XCTAssertFalse(reference.hasUnsavedChanges)
        window.title = "Renamed.md"
        reference.updateText("changed again")
        XCTAssertEqual(window.tab.title, "● Renamed.md")
    }

    @MainActor func testExplicitNativeSaveClearsTabDotAfterWritingFile() async throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("original".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try CloseTestDocument(contentsOf: url, ofType: "public.plain-text")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        document.addWindowController(NSWindowController(window: window))
        defer { document.updateChangeCount(.changeCleared); document.close() }
        let reference = DocumentWindowReference()
        reference.attach(to: window)
        reference.updateText("original")
        document.text = "saved edit"
        document.updateChangeCount(.changeDone)
        reference.updateText(document.text)
        XCTAssertTrue(reference.hasUnsavedChanges)
        reference.save()
        for _ in 0..<100 where reference.saving { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(reference.saving)
        XCTAssertFalse(reference.hasUnsavedChanges)
        XCTAssertFalse(window.tab.title.hasPrefix("● "))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "saved edit")
    }

    @MainActor func testOpeningUsesSameTabGroupAndPreservesEditedWindow() throws {
        _ = NSApplication.shared
        let automaticTabbing = NSWindow.allowsAutomaticWindowTabbing
        defer { NSWindow.allowsAutomaticWindowTabbing = automaticTabbing }
        let source = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let destination = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        source.isReleasedWhenClosed = false
        destination.isReleasedWhenClosed = false
        defer { destination.close(); source.close() }
        source.isDocumentEdited = true
        source.makeKeyAndOrderFront(nil)
        DocumentWindowReference.activate(destination, in: source)
        XCTAssertTrue(source.tabbedWindows?.contains(where: { $0 === destination }) == true)
        XCTAssertTrue(source.isDocumentEdited)
        XCTAssertEqual(destination.tabbingMode, .preferred)
        XCTAssertEqual(source.tabbingIdentifier, destination.tabbingIdentifier)
        DocumentWindowReference.activate(destination, in: source)
        XCTAssertEqual(source.tabbedWindows?.count, 2)
        DocumentWindowReference.activate(source, in: source)
        XCTAssertEqual(source.tabbedWindows?.count, 2)
    }
}
#endif
