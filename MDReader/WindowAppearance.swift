import SwiftUI

#if os(macOS)
import AppKit

/// Let AppKit restore native documents (including autosaved drafts) before
/// handling its request for an untitled document on an otherwise empty launch.
@MainActor
final class DocumentLaunchDelegate: NSObject, NSApplicationDelegate {
    private var reviewingTermination = false
    override init() {
        super.init()
        // This is an app-local preference, not a change to the global macOS setting.
        UserDefaults.standard.set(true, forKey: "NSQuitAlwaysKeepsWindows")
        UserDefaults.standard.set(true, forKey: "NSCloseAlwaysConfirmsChanges")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if reviewingTermination { return .terminateLater }
        let documents = NSDocumentController.shared.documents
        guard !documents.isEmpty else { return .terminateNow }
        reviewingTermination = true
        Task { @MainActor in
            let review = DocumentCloseReview()
            let canQuit = await review.confirm(documents)
            reviewingTermination = false
            sender.reply(toApplicationShouldTerminate: canQuit)
        }
        return .terminateLater
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.documents.isEmpty
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        let controller = NSDocumentController.shared
        guard controller.documents.isEmpty else { return true }
        do {
            try controller.openUntitledDocumentAndDisplay(true)
            return true
        } catch {
            sender.presentError(error)
            return false
        }
    }
}

/// Ask each native document to save, discard, or cancel without closing its
/// window first, so a successful quit can still preserve the session layout.
@MainActor
final class DocumentCloseReview: NSObject {
    private var continuation: CheckedContinuation<Bool, Never>?

    func confirm(_ documents: [NSDocument]) async -> Bool {
        // Autosaving can clear isDocumentEdited while close confirmation is still
        // required. Let NSDocument decide, including for apparently clean files.
        for document in documents {
            let allowed = await withCheckedContinuation { continuation in
                self.continuation = continuation
                document.canClose(withDelegate: self,
                                  shouldClose: #selector(document(_:shouldClose:contextInfo:)),
                                  contextInfo: nil)
            }
            if !allowed { return false }
            // An approved unsaved draft was discarded (Save gives it a URL).
            // Close it so native session restoration cannot resurrect its edits.
            if document.fileURL == nil { document.close() }
        }
        return true
    }

    @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: shouldClose)
    }
}

/// Keep document opens in the originating window's native tab group.
@MainActor
final class DocumentWindowReference: NSObject, ObservableObject {
    weak var window: NSWindow?
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var saving = false
    private var titleObservation: NSKeyValueObservation?
    private var currentText: String?
    private var savedText: String?
    private var pendingSaveText: String?

    func updateText(_ text: String) {
        if savedText == nil { savedText = text }
        currentText = text
        refreshIndicator()
    }

    func saveCompleted(snapshot: String, successfully: Bool) {
        if successfully { savedText = snapshot }
        refreshIndicator()
    }

    private func refreshIndicator() {
        hasUnsavedChanges = currentText != savedText
        guard let window else { return }
        // A text prefix is visible in native tabs even when accessory views are hidden.
        window.tab.title = (hasUnsavedChanges ? "● " : "") + window.title
        window.tab.toolTip = hasUnsavedChanges ? "Unsaved changes — " + window.title : window.title
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        titleObservation = window.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshIndicator() }
        }
        refreshIndicator()
    }

    func save(asNewFile: Bool = false) {
        guard !saving, let window, let currentText else { return }
        let nativeDocument = (window.windowController?.document as? NSDocument)
            ?? NSDocumentController.shared.documents.first { document in
                document.windowControllers.contains { $0.window === window }
            }
        guard let document = nativeDocument else {
            NSApp.presentError(NSError(domain: "MDReader", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The document is not ready to save. Please try again."]))
            return
        }
        saving = true
        pendingSaveText = currentText
        if asNewFile {
            document.runModalSavePanel(for: .saveAsOperation, delegate: self,
                                      didSave: #selector(document(_:didSave:contextInfo:)), contextInfo: nil)
        } else {
            document.save(withDelegate: self, didSave: #selector(document(_:didSave:contextInfo:)), contextInfo: nil)
        }
    }

    @objc private func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if let snapshot = pendingSaveText { saveCompleted(snapshot: snapshot, successfully: didSave) }
        pendingSaveText = nil
        saving = false
    }

    static func configure(_ window: NSWindow) {
        NSWindow.allowsAutomaticWindowTabbing = true
        window.isRestorable = true
        window.tabbingIdentifier = "MDReader.Documents"
        window.tabbingMode = .preferred
    }

    static func activate(_ destination: NSWindow, in source: NSWindow) {
        configure(source)
        configure(destination)
        if destination !== source && !(source.tabbedWindows ?? []).contains(where: { $0 === destination }) {
            source.addTabbedWindow(destination, ordered: .above)
        }
        destination.makeKeyAndOrderFront(nil)
    }
}

struct DocumentSaveActions {
    var save: () -> Void
    var saveAs: () -> Void
    var isSaving: Bool
}
private struct DocumentSaveKey: FocusedValueKey {
    typealias Value = DocumentSaveActions
}
extension FocusedValues {
    var documentSave: DocumentSaveActions? {
        get { self[DocumentSaveKey.self] }
        set { self[DocumentSaveKey.self] = newValue }
    }
}
struct DocumentSaveCommands: Commands {
    @FocusedValue(\.documentSave) private var actions
    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") { actions?.save() }.keyboardShortcut("s")
                .disabled(actions == nil || actions?.isSaving == true)
            Button("Save As…") { actions?.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(actions == nil || actions?.isSaving == true)
        }
    }
}

struct DocumentWindowReader: NSViewRepresentable {
    let reference: DocumentWindowReference
    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.reference = reference
        return view
    }
    func updateNSView(_ view: WindowView, context: Context) {
        view.reference = reference
        view.captureWindow()
    }
    final class WindowView: NSView {
        weak var reference: DocumentWindowReference?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            captureWindow()
        }
        func captureWindow() {
            guard let window else { return }
            reference?.attach(to: window)
            DocumentWindowReference.configure(window)
        }
    }
}

/// Observe the application appearance, which is independent of document-window overrides.
@MainActor
final class SystemAppearance: ObservableObject {
    @Published private(set) var colorScheme: ColorScheme
    private var observation: NSKeyValueObservation?

    init(application: NSApplication? = nil) {
        let application = application ?? NSApplication.shared
        colorScheme = Self.scheme(for: application.effectiveAppearance)
        observation = application.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
            let scheme = Self.scheme(for: app.effectiveAppearance)
            DispatchQueue.main.async { self?.colorScheme = scheme }
        }
    }

    nonisolated private static func scheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

/// Clear the native override for System instead of relying on a nil SwiftUI preference.
struct WindowAppearance: NSViewRepresentable {
    let colorScheme: ColorScheme?

    static func apply(to window: NSWindow, colorScheme: ColorScheme?) {
        let name: NSAppearance.Name? = colorScheme.map { $0 == .dark ? .darkAqua : .aqua }
        guard window.appearance?.name != name else { return }
        window.appearance = name.flatMap(NSAppearance.init(named:))
    }

    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }
    func updateNSView(_ view: AppearanceView, context: Context) {
        view.colorScheme = colorScheme
        view.applyAppearance()
    }

    final class AppearanceView: NSView {
        var colorScheme: ColorScheme?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
        }
        func applyAppearance() {
            if let window { WindowAppearance.apply(to: window, colorScheme: colorScheme) }
        }
    }
}
#else
import UIKit

struct WindowAppearance: UIViewRepresentable {
    let colorScheme: ColorScheme?

    func makeUIView(context: Context) -> AppearanceView { AppearanceView() }
    func updateUIView(_ view: AppearanceView, context: Context) {
        view.colorScheme = colorScheme
        view.applyAppearance()
    }

    final class AppearanceView: UIView {
        var colorScheme: ColorScheme?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyAppearance()
        }
        func applyAppearance() {
            guard let window else { return }
            let style: UIUserInterfaceStyle = colorScheme.map { $0 == .dark ? .dark : .light } ?? .unspecified
            if window.overrideUserInterfaceStyle != style { window.overrideUserInterfaceStyle = style }
        }
    }
}
#endif
