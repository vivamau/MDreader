import Foundation
import Combine
import CoreTransferable
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct RecentDocument: Codable, Identifiable, Equatable {
    var id: String { url.absoluteString }
    var url: URL
    var bookmark: Data?
    var openedAt: Date
    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().lastPathComponent }
}

@MainActor
final class RecentDocuments: ObservableObject {
    @Published private(set) var items: [RecentDocument]
    private let defaults: UserDefaults
    private let key = "recentMarkdownDocuments"
    static let limit = 20

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([RecentDocument].self, from: $0) } ?? []
    }

    func record(_ url: URL) {
        guard url.isFileURL else { return }
        let url = url.standardizedFileURL
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #endif
        let bookmark = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        let previous = items.first { $0.url == url }
        items.removeAll { $0.url == url }
        items.insert(RecentDocument(url: url, bookmark: bookmark ?? previous?.bookmark, openedAt: Date()), at: 0)
        items = Array(items.prefix(Self.limit))
        persist()
    }

    func resolve(_ item: RecentDocument) throws -> URL {
        guard let bookmark = item.bookmark else { return item.url }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        return try URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
        // Opening the resolved URL records a fresh bookmark, including after moves or stale data.
    }

    func remove(_ item: RecentDocument) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func seedSystemHistoryIfNeeded() {
        guard !defaults.bool(forKey: "recentMarkdownDocumentsSeeded") else { return }
        defaults.set(true, forKey: "recentMarkdownDocumentsSeeded")
        #if os(macOS)
        if items.isEmpty {
            for url in NSDocumentController.shared.recentDocumentURLs.prefix(Self.limit).reversed() {
                record(url)
            }
        }
        #endif
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
}

struct DocumentProject: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var files: [RecentDocument]
}

struct ProjectFileDrag: Codable, Transferable {
    let projectID: UUID
    let fileID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "org.mdreader.project-file", conformingTo: .data))
    }
}

/// Project membership owns references, never the documents themselves.
@MainActor
final class DocumentProjects: ObservableObject {
    @Published private(set) var items: [DocumentProject] = []
    @Published private(set) var loadError: String?
    private let storageURL: URL
    private struct Archive: Codable {
        var version = 1
        var projects: [DocumentProject]
    }
    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MDReader", isDirectory: true).appendingPathComponent("projects.json")
        do {
            let data = try Data(contentsOf: self.storageURL)
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard archive.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            items = archive.projects
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // First launch: the archive does not exist yet.
        } catch { loadError = "Unable to load projects: \(error.localizedDescription)" }
    }
    @discardableResult
    func create(name: String) throws -> UUID {
        let project = DocumentProject(id: UUID(), name: try validated(name), files: [])
        try commit(items + [project])
        return project.id
    }
    func rename(_ id: UUID, name: String) throws {
        let name = try validated(name)
        var updated = items
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].name = name
        try commit(updated)
    }
    func remove(_ id: UUID) throws { try commit(items.filter { $0.id != id }) }
    func add(_ file: RecentDocument, to id: UUID) throws {
        var updated = items
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        if let existing = updated[index].files.firstIndex(where: { $0.id == file.id }) {
            updated[index].files[existing] = file
        } else { updated[index].files.append(file) }
        try commit(updated)
    }
    /// Resolve IDs against live state and commit both sides of a drop together.
    @discardableResult
    func move(_ files: [ProjectFileDrag], to destination: UUID) throws -> Bool {
        guard !files.isEmpty, let target = items.firstIndex(where: { $0.id == destination }) else { return false }
        var updated = items
        for payload in files {
            guard let source = updated.firstIndex(where: { $0.id == payload.projectID }),
                  let file = updated[source].files.first(where: { $0.id == payload.fileID }) else { return false }
            if source == target { continue }
            if !updated[target].files.contains(where: { $0.id == file.id }) {
                updated[target].files.append(file)
            }
            updated[source].files.removeAll { $0.id == file.id }
        }
        if updated != items { try commit(updated) }
        return true
    }

    func removeFile(_ file: RecentDocument, from id: UUID) throws {
        var updated = items
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].files.removeAll { $0.id == file.id }
        try commit(updated)
    }
    func removeFileEverywhere(_ file: RecentDocument, resolvedURL: URL) throws {
        var updated = items
        for index in updated.indices {
            updated[index].files.removeAll {
                $0.id == file.id || $0.url.standardizedFileURL == resolvedURL.standardizedFileURL
            }
        }
        if updated != items { try commit(updated) }
    }

    func refresh(_ old: RecentDocument, with file: RecentDocument) throws {
        var updated = items
        for index in updated.indices where updated[index].files.contains(where: { $0.id == old.id }) {
            updated[index].files.removeAll { $0.id == old.id || $0.id == file.id }
            updated[index].files.append(file)
        }
        if updated != items { try commit(updated) }
    }
    private func validated(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw NSError(domain: "MDReader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Enter a project name."])
        }
        return name
    }
    private func commit(_ updated: [DocumentProject]) throws {
        // Never replace an archive that could not be read.
        if let loadError { throw NSError(domain: "MDReader", code: 3, userInfo: [NSLocalizedDescriptionKey: loadError]) }
        let data = try JSONEncoder().encode(Archive(projects: updated))
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: storageURL, options: .atomic)
        items = updated
    }
}
