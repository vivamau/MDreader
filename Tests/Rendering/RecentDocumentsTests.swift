import Foundation
import XCTest
@testable import MDReaderRendering

final class RecentDocumentsTests: XCTestCase {
    @MainActor func testHistoryPersistsDeduplicatesAndLimitsEntries() throws {
        let suite = "MDReaderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = RecentDocuments(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0..<25 {
            let url = directory.appendingPathComponent("\(index).md")
            try Data("# Document".utf8).write(to: url)
            history.record(url)
        }
        XCTAssertEqual(history.items.count, 20)
        XCTAssertEqual(history.items.first?.name, "24.md")
        let reopened = directory.appendingPathComponent("10.md")
        history.record(reopened)
        XCTAssertEqual(history.items.first?.url, reopened)
        XCTAssertEqual(history.items.filter { $0.url == reopened }.count, 1)
        let restored = RecentDocuments(defaults: defaults)
        XCTAssertEqual(restored.items, history.items)
        let entry = try XCTUnwrap(restored.items.first)
        XCTAssertEqual(try restored.resolve(entry).standardizedFileURL, reopened.standardizedFileURL)
        restored.remove(entry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reopened.path))
        restored.clear()
        XCTAssertTrue(RecentDocuments(defaults: defaults).items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reopened.path))
    }

    @MainActor func testInvalidStoredDataAndNonFileURLs() throws {
        let suite = "MDReaderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "recentMarkdownDocuments")
        let history = RecentDocuments(defaults: defaults)
        history.record(try XCTUnwrap(URL(string: "https://example.com/document.md")))
        XCTAssertTrue(history.items.isEmpty)
    }
}
