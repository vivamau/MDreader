import SwiftUI

@main
struct MDReaderApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(DocumentLaunchDelegate.self) private var launchDelegate
    #endif
    @StateObject private var recents = RecentDocuments()
    @StateObject private var projects = DocumentProjects()
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentWorkspace(document: file.$document, fileURL: file.fileURL)
                .environmentObject(recents)
                .environmentObject(projects)
        }
        .commands {
            DocumentPrintCommands()
            #if os(macOS)
            DocumentSaveCommands()
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
    }
}
