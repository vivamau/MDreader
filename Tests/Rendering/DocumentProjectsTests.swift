import Foundation
import XCTest
@testable import MDReaderRendering

final class DocumentProjectsTests: XCTestCase {
    @MainActor func testMembershipSurvivesRelaunchAndRemovalNeverDeletesFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("document.md")
        try Data("# Test".utf8).write(to: url)
        let archive = folder.appendingPathComponent("projects.json")
        let store = DocumentProjects(storageURL: archive)
        XCTAssertNil(store.loadError)
        let first = try store.create(name: "  Research  ")
        let second = try store.create(name: "Writing")
        let file = RecentDocument(url: url, bookmark: Data([1, 2]), openedAt: Date())
        try store.add(file, to: first)
        try store.add(file, to: first)
        try store.add(file, to: second)
        XCTAssertEqual(store.items[0].files.count, 1)
        XCTAssertEqual(store.items[0].name, "Research")
        try store.rename(first, name: "Notes")
        XCTAssertThrowsError(try store.rename(first, name: "  "))
        let restored = DocumentProjects(storageURL: archive)
        XCTAssertEqual(restored.items, store.items)
        try restored.removeFile(file, from: first)
        XCTAssertEqual(restored.items[1].files, [file])
        try restored.remove(second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(DocumentProjects(storageURL: archive).items, restored.items)
    }

    @MainActor func testCorruptArchiveIsPreservedAndFailedSaveDoesNotPublish() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("projects.json")
        let data = Data("broken archive".utf8)
        try data.write(to: url)
        let store = DocumentProjects(storageURL: url)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.create(name: "New"))
        XCTAssertEqual(try Data(contentsOf: url), data)
        let blocked = DocumentProjects(storageURL: url.appendingPathComponent("impossible.json"))
        XCTAssertThrowsError(try blocked.create(name: "New"))
        XCTAssertTrue(blocked.items.isEmpty)
    }

    @MainActor func testDragMovesOnlySourceMembershipAndPersists() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appendingPathComponent("projects.json")
        let store = DocumentProjects(storageURL: archive)
        let source = try store.create(name: "Source")
        let target = try store.create(name: "Target")
        let other = try store.create(name: "Other")
        let url = folder.appendingPathComponent("note.md")
        try Data("unchanged".utf8).write(to: url)
        let file = RecentDocument(url: url, bookmark: Data([1]), openedAt: Date())
        try store.add(file, to: source)
        try store.add(file, to: other)
        let payload = ProjectFileDrag(projectID: source, fileID: file.id)
        XCTAssertTrue(try store.move([payload], to: target))
        XCTAssertEqual(store.items.map(\.files), [[], [file], [file]])
        XCTAssertEqual(DocumentProjects(storageURL: archive).items, store.items)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "unchanged")
        // Dropping into a project that already contains the file deduplicates.
        XCTAssertTrue(try store.move([ProjectFileDrag(projectID: other, fileID: file.id)], to: target))
        XCTAssertEqual(store.items.map(\.files), [[], [file], []])
        XCTAssertTrue(try store.move([ProjectFileDrag(projectID: target, fileID: file.id)], to: target))
        XCTAssertEqual(store.items[1].files, [file])
        // Stale drags and missing targets must leave the archive untouched.
        let before = try Data(contentsOf: archive)
        XCTAssertFalse(try store.move([payload], to: target))
        XCTAssertFalse(try store.move([ProjectFileDrag(projectID: target, fileID: file.id)], to: UUID()))
        XCTAssertEqual(try Data(contentsOf: archive), before)
        // Failed persistence cannot remove the source membership in memory.
        try FileManager.default.removeItem(at: archive)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.move([ProjectFileDrag(projectID: target, fileID: file.id)], to: source))
        XCTAssertEqual(store.items.map(\.files), [[], [file], []])
    }

    @MainActor func testMovedFileRefreshesEveryProject() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DocumentProjects(storageURL: folder.appendingPathComponent("projects.json"))
        let first = try store.create(name: "A")
        let second = try store.create(name: "B")
        let old = RecentDocument(url: folder.appendingPathComponent("old.md"), bookmark: nil, openedAt: Date())
        let new = RecentDocument(url: folder.appendingPathComponent("new.md"), bookmark: Data([3]), openedAt: Date())
        try store.add(old, to: first)
        try store.add(old, to: second)
        try store.add(new, to: first)
        try store.refresh(old, with: new)
        XCTAssertEqual(store.items.map(\.files), [[new], [new]])
    }
}
