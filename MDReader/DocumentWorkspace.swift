import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct DocumentWorkspace: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @EnvironmentObject private var recents: RecentDocuments
    @EnvironmentObject private var projects: DocumentProjects
    #if os(macOS)
    @Environment(\.openDocument) private var openDocument
    @StateObject private var documentWindow = DocumentWindowReference()
    #endif
    @AppStorage("sidebarProjectsExpanded") private var projectsExpanded = true
    @AppStorage("sidebarRecentsExpanded") private var recentsExpanded = true
    @SceneStorage("sidebarVisible") private var sidebarVisible = true
    @SceneStorage("expandedProjectIDs") private var expandedProjectIDs = ""
    private var columns: Binding<NavigationSplitViewVisibility> {
        Binding(get: { sidebarVisible ? .all : .detailOnly }, set: { visibility in
            if visibility == .detailOnly { sidebarVisible = false }
            else if visibility == .all || visibility == .doubleColumn { sidebarVisible = true }
        })
    }
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var showingImporter = false
    @State private var opening = false
    @State private var openError: String?

    @State private var projectName = ""
    @State private var namingProject = false
    @State private var renamingID: UUID?
    @State private var importerProject: UUID?
    @State private var dropTarget: UUID?
    @State private var showingNewFile = false
    @State private var newFileProject: UUID?
    @State private var newDocument = MarkdownDocument()

    var body: some View {
        NavigationSplitView(columnVisibility: columns, preferredCompactColumn: $compactColumn) {
            VStack(spacing: 0) {
                HStack {
                    Text("Library").font(.headline)
                    Spacer()
                    Menu {
                        Button("New Project…", systemImage: "folder.badge.plus") { beginNaming() }
                        Button("Open File…", systemImage: "doc") { importerProject = nil; showingImporter = true }
                        Button("Clear Recent Files") { recents.clear() }.disabled(recents.items.isEmpty)
                    } label: {
                        Label("Library actions", systemImage: "plus.circle").labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }.padding()
                List {
                    Section("Projects", isExpanded: $projectsExpanded) {
                        Button("New Project…", systemImage: "folder.badge.plus") { beginNaming() }
                        if let error = projects.loadError {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                        ForEach(projects.items) { project in
                            DisclosureGroup(isExpanded: projectExpansion(project.id)) {
                                if project.files.isEmpty {
                                    Text("Drop files on this project or use Add File.").font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(project.files) { item in
                                    fileRow(item)
                                        .draggable(ProjectFileDrag(projectID: project.id, fileID: item.id))
                                        .contextMenu {
                                            Button("Remove from Project") { perform { try projects.removeFile(item, from: project.id) } }
                                        }
                                }
                                Menu("Add File", systemImage: "plus") { projectActions(project) }
                            } label: {
                                Label(project.name, systemImage: "folder")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                    .background(dropTarget == project.id ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                    .dropDestination(for: ProjectFileDrag.self) { files, _ in
                                        do { return try projects.move(files, to: project.id) }
                                        catch { openError = error.localizedDescription; return false }
                                    } isTargeted: { targeted in
                                        if targeted { dropTarget = project.id }
                                        else if dropTarget == project.id { dropTarget = nil }
                                    }
                                    .help("Drop a file here to move it into this project")
                                    .contextMenu { projectActions(project) }
                            }
                        }
                    }
                    Section("Recent Files", isExpanded: $recentsExpanded) {
                        if recents.items.isEmpty {
                            Text("Files you open or save will appear here.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(recents.items) { item in
                            fileRow(item)
                                .contextMenu {
                                    Menu("Add to Project") {
                                        ForEach(projects.items) { project in
                                            Button(project.name) { perform { try projects.add(item, to: project.id) } }
                                        }
                                    }.disabled(projects.items.isEmpty)
                                    Button("Remove from Recent Files") { recents.remove(item) }
                                }
                        }
                    }
                }.listStyle(.sidebar)
                if opening { ProgressView("Opening file…").padding() }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            EditorView(document: $document, documentTitle: fileURL?.lastPathComponent ?? "Untitled")
        }
        #if os(macOS)
        .background(DocumentWindowReader(reference: documentWindow).frame(width: 0, height: 0))
        .onChange(of: document.text, initial: true) { _, text in documentWindow.updateText(text) }
        .focusedSceneValue(\.documentSave, DocumentSaveActions(
            save: { documentWindow.save() }, saveAs: { documentWindow.save(asNewFile: true) },
            isSaving: documentWindow.saving))
        #endif
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.markdownDocument, .plainText]) { result in
            switch result {
            case let .success(url):
                if let projectID = importerProject {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    addURL(url, to: projectID)
                } else { openURL(url) }
                importerProject = nil
            case let .failure(error): openError = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $showingNewFile, document: newDocument,
                      contentType: .markdownDocument, defaultFilename: "Untitled.md") { result in
            defer { newFileProject = nil }
            switch result {
            case let .success(url):
                guard let projectID = newFileProject else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                recents.record(url)
                guard let entry = recents.items.first(where: { $0.url == url.standardizedFileURL }) else { return }
                do {
                    guard projects.items.contains(where: { $0.id == projectID }) else {
                        openError = "The file was saved, but its project was removed. You can find the file in Recent Files."
                        return
                    }
                    try projects.add(entry, to: projectID)
                    openURL(url)
                } catch {
                    openError = "The file was saved, but could not be added to the project: \(error.localizedDescription)"
                }
            case let .failure(error): openError = error.localizedDescription
            }
        }
        .sheet(isPresented: $namingProject) {
            VStack(alignment: .leading, spacing: 16) {
                Text(renamingID == nil ? "New Project" : "Rename Project").font(.headline)
                TextField("Project name", text: $projectName).textFieldStyle(.roundedBorder)
                    .onSubmit { saveProjectName() }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { namingProject = false }
                    Button("Save") { saveProjectName() }
                        .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(minWidth: 280)
        }
        .alert("Unable to Complete Action", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("Open File…") { importerProject = nil; showingImporter = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "")
        }
        .onChange(of: fileURL, initial: true) { _, url in
            recents.seedSystemHistoryIfNeeded()
            if let url { recents.record(url) }
        }
    }

    private func projectExpansion(_ id: UUID) -> Binding<Bool> {
        Binding(get: {
            expandedProjectIDs.split(separator: ",").contains(Substring(id.uuidString))
        }, set: { expanded in
            var identifiers = Set(expandedProjectIDs.split(separator: ",").map(String.init))
            if expanded { identifiers.insert(id.uuidString) }
            else { identifiers.remove(id.uuidString) }
            expandedProjectIDs = identifiers.sorted().joined(separator: ",")
        })
    }

    private func fileRow(_ item: RecentDocument) -> some View {
        Button { open(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).lineLimit(1).foregroundStyle(.primary)
                    Text(item.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if item.url == fileURL?.standardizedFileURL { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(opening).help(item.url.path)
    }

    @ViewBuilder private func projectActions(_ project: DocumentProject) -> some View {
        Button("New Markdown File…", systemImage: "doc.badge.plus") {
            newDocument = MarkdownDocument()
            newFileProject = project.id
            showingNewFile = true
        }.disabled(opening)
        Button("Add Current File") { if let fileURL { addURL(fileURL, to: project.id) } }
            .disabled(fileURL == nil)
        Button("Choose File…") { importerProject = project.id; showingImporter = true }
        Menu("Add Recent File") {
            ForEach(recents.items) { item in
                Button(item.name) { perform { try projects.add(item, to: project.id) } }
            }
        }.disabled(recents.items.isEmpty)
        Divider()
        Button("Rename Project…") { beginNaming(project) }
        Button("Remove Project", role: .destructive) { perform { try projects.remove(project.id) } }
    }

    private func beginNaming(_ project: DocumentProject? = nil) {
        renamingID = project?.id
        projectName = project?.name ?? ""
        namingProject = true
    }

    private func saveProjectName() {
        guard !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        namingProject = false
        perform {
            if let renamingID { try projects.rename(renamingID, name: projectName) }
            else { try projects.create(name: projectName) }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { openError = error.localizedDescription }
    }

    private func addURL(_ url: URL, to projectID: UUID) {
        recents.record(url)
        if let entry = recents.items.first(where: { $0.url == url.standardizedFileURL }) {
            perform { try projects.add(entry, to: projectID) }
        }
    }

    private func open(_ item: RecentDocument) {
        guard item.url != fileURL?.standardizedFileURL else {
            // Selecting the current document must not change sidebar visibility.
            #if os(iOS)
            compactColumn = .detail
            #endif
            return
        }
        do { openURL(try recents.resolve(item), replacing: item) }
        catch { openError = error.localizedDescription }
    }

    private func openURL(_ url: URL, replacing oldItem: RecentDocument? = nil) {
        guard !opening else { return }
        opening = true
        Task { @MainActor in
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
                opening = false
            }
            do {
                #if os(macOS)
                // Capture the originating document window before opening changes focus.
                let sourceWindow = documentWindow.window
                if let sourceWindow { DocumentWindowReference.configure(sourceWindow) }
                try await openDocument(at: url)
                if let sourceWindow,
                   let destination = NSDocumentController.shared.document(for: url)?.windowControllers.compactMap(\.window).first {
                    DocumentWindowReference.activate(destination, in: sourceWindow)
                }
                #else
                try await openInDocumentBrowser(url)
                #endif
                if let oldItem, oldItem.url != url.standardizedFileURL { recents.remove(oldItem) }
                recents.record(url)
                if let oldItem, let refreshed = recents.items.first(where: { $0.url == url.standardizedFileURL }) {
                    try projects.refresh(oldItem, with: refreshed)
                }
            } catch { openError = error.localizedDescription }
        }
    }
}

#if os(iOS)
@MainActor
private func openInDocumentBrowser(_ url: URL) async throws {
    func browser(in controller: UIViewController) -> UIDocumentBrowserViewController? {
        if let browser = controller as? UIDocumentBrowserViewController { return browser }
        for child in controller.children {
            if let found = browser(in: child) { return found }
        }
        if let presented = controller.presentedViewController { return browser(in: presented) }
        return nil
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
    guard let documentBrowser = scenes.flatMap(\.windows).compactMap(\.rootViewController)
        .compactMap({ browser(in: $0) }).first else {
        throw NSError(domain: "MDReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "The document browser is unavailable. Return to the document browser and open the file there."])
    }
    let revealed: URL = try await withCheckedThrowingContinuation { continuation in
        documentBrowser.revealDocument(at: url, importIfNeeded: false) { revealed, error in
            if let error { continuation.resume(throwing: error) }
            else if let revealed { continuation.resume(returning: revealed) }
            else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
        }
    }
    // Dismiss the current document through its normal lifecycle before selecting another.
    if documentBrowser.presentedViewController != nil {
        await withCheckedContinuation { continuation in
            documentBrowser.dismiss(animated: true) { continuation.resume() }
        }
    }
    documentBrowser.delegate?.documentBrowser?(documentBrowser, didPickDocumentsAt: [revealed])
}
#endif
