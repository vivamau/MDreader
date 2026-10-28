# MDReader

A native SwiftUI Markdown document editor for macOS 14+, iPhone, and iPad (iOS/iPadOS 17+). Pele and SwiftDraw are vendored for offline rendering; no network services are used.

## Run

Open `MDReader.xcodeproj` in Xcode, select the MDReader scheme, choose My Mac or an iPhone/iPad simulator, and press Run. For a physical iOS device, select your development team under Signing & Capabilities and replace `org.example.MDReader` with your own bundle identifier.

On Mac, use File → New / Open and Save (⌘N / ⌘O / ⌘S). On iPhone and iPad, use the system document browser to create or open files in Files, including configured iCloud Drive locations. DocumentGroup handles document lifecycle and automatic saving. No custom iCloud container is required.

## Features

- Open, edit, and save UTF-8 `.md`, `.markdown`, and `.mdown` documents; also open plain text.
- Edit, preview, and adaptive split view.
- Monospaced editor with adjustable font size, native text editing, and word/character counts.
- Mermaid diagrams in fenced `mermaid` blocks, rendered offline with Pele 1.11.0 and native SwiftDraw SVG display.
- Offline preview: headings, paragraphs, simple lists, block quotes, fenced code, dividers, pipe tables with column alignment and horizontal scrolling, and Apple's inline Markdown formatting (including links).
- Saved System, Light, and Dark appearance options in the header settings panel, selectable preview text, and accessibility labels. System follows the device appearance; the preference is shared across document windows.

The preview is a lightweight Markdown subset, not a full CommonMark/GFM renderer. Task-list controls, nested list layout, images, and embedded HTML are not rendered. Editing preserves the source text regardless of preview support. Files are written as UTF-8; other input encodings report an error rather than being silently replaced.

## Printing

Use the printer toolbar button in any view mode, or File → Print (⌘P) on Mac. Review the rendered document, then choose Print to open the native print dialog (AirPrint on iPhone/iPad). On Mac the print dialog also offers Save as PDF. Print output uses a fixed, readable paper font and black text on white, independent of the editor's theme and font size. Tables wrap to the page width. The preview shows content; the native dialog handles page layout and printer selection. Mac printing uses AppKit text layout and native tables; iPhone/iPad use the local UIKit markup formatter. Printing does not load a web view or require network-client permissions. The Mac sandbox enables only the printing capability in addition to user-selected file access.

## Validation

Build for both platforms without signing:

```sh
xcodebuild -project MDReader.xcodeproj -scheme MDReader -destination 'generic/platform=macOS' -derivedDataPath /tmp/MDReader-build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MDReader.xcodeproj -scheme MDReader -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/MDReader-ios-build CODE_SIGNING_ALLOWED=NO build
swiftc MDReader/MarkdownBlocks.swift MDReader/PrintHTML.swift Tests/main.swift -o /tmp/MDReader-parser-tests
/tmp/MDReader-parser-tests
```

Before distribution, configure signing, supply app icons, and exercise creating, opening, editing, closing, and reopening documents on devices. Also verify undo/redo and Files provider behavior. App Store packaging is not configured.

The document architecture follows [Apple's document-based SwiftUI guidance](https://developer.apple.com/documentation/swiftui/building-a-document-based-app-with-swiftui/).

## Mermaid / Pele

Use a fenced block tagged `mermaid`:

````markdown
```mermaid
flowchart LR
    A[Write] --> B[Preview]
```
````

[Examples/Mermaid.md](Examples/Mermaid.md) contains flowchart, sequence, state, and pie examples. Diagrams render in Preview and Split, follow the selected appearance and font size, and adapt to the available width. Expand **Mermaid source** to inspect the source. Invalid syntax displays an error instead of dropping the document. Normal fenced code is unchanged.

Pele runs in JavaScriptCore on a background actor. SVG is displayed natively with SwiftDraw; there is no web view, CDN, or network entitlement. External diagram images and clickable links are disabled. The app limits individual diagrams to 50 KB of source, 500 flowchart edges, and 2 MB of SVG output. SwiftDraw is an SVG subset, so advanced SVG effects or complex typography may differ from Pele in a browser. Diagram syntax support follows the bundled Pele release.

Printing uses vector diagram attachments on Mac and local PNG attachments for AirPrint. Invalid diagrams retain their source in print output.

Dependencies are committed under `MDReader/Resources` and `Vendor/SwiftDraw`, with licenses and pinned provenance. SwiftDraw's source is unchanged; its local package manifest includes only the library targets. Xcode builds do not need npm or a package download.

Run the rendering and native print regression tests with:

```sh
swift test
```

For local visual fixtures:

```sh
mkdir -p /tmp/MDReader-pele-artifacts
MDREADER_TEST_ARTIFACTS=/tmp/MDReader-pele-artifacts swift test
```

## Reading settings

Click the gear in the header to choose separate editor and preview fonts (System, Serif, Rounded, Monospaced, or Georgia), font size, appearance, and separate background and font colors for light and dark mode. Changes apply immediately and persist across launches and document windows. Selected font colors apply to the editor and Markdown text, including headings, tables, quotes, and code blocks; diagrams keep their own light/dark palette. Code blocks stay monospaced, and print output retains its paper-friendly layout. Reset to Defaults restores the original choices.

## Recent files

The left sidebar lists the 20 most recently opened or saved files, newest first, and remembers them across launches. Use the native sidebar control beside the window controls to show or hide it on Mac. On Mac, the initial list imports the app’s existing system recent-file history. Selecting a file uses the system document-opening flow (opening or selecting a native document tab in the current Mac window).

**Open File…** opens the file picker. The sidebar’s menu clears history; a file’s context menu removes just that entry. Neither action deletes files. Saved access bookmarks let the sandbox reopen previously selected documents; if a file is unavailable or access has expired, use Open File to locate it again.

## Projects

Use **Library → + → New Project…** to create a named group. Expand the project and use its menu to add the current saved file, choose a file from disk, or add a recent file. Recent-file context menus also offer **Add to Project**. Project menus include rename and removal; file context menus remove individual memberships. Save an untitled document before adding it.

Projects contain references to the original files, and the same file can belong to multiple projects. Removing a project or membership never deletes the Markdown file. Project memberships persist independently of the 20-file recent history. Selecting a project file uses the same native document-opening flow as recent files.

Project metadata and sandbox access bookmarks are saved atomically in `MDReader/projects.json` within the app’s Application Support directory. This versioned local archive is shared across document windows. No SQLite dependency or document-content database is needed for these groups. A failed save reports an error without publishing the change; an unreadable archive is preserved instead of silently overwritten. Projects are local to this installation and do not sync between devices.

Drag a file row from one project onto another project’s name to move its membership. The destination highlights during a drag and can be collapsed or empty. If it already contains the file, the drop keeps a single entry. Other project memberships and the file on disk remain unchanged; the move is saved in one atomic archive update.

To create a document inside a project, choose **Add File → New Markdown File…**. Select a name and location in the system save picker. MDReader saves an empty UTF-8 Markdown file, adds it to the project and recent history, then opens it for editing. Cancelling the picker leaves the project unchanged. If saving succeeds but project storage fails, the saved file remains available in Recent Files.

The **Projects** and **Recent Files** section headings can each be collapsed or expanded using their disclosure controls. Their states are remembered across launches and shared across document windows.

On Mac, opening a file from the Library, a project, or the new-file picker selects a native document tab inside the originating window. The previous document stays in its own tab with its edits and native save/close handling intact. Document windows prefer native tabbing for standard document opens as well.

## Startup and restoration

On Mac, MDReader opts into native secure document/window restoration and keeps windows on normal quit using an app-local preference. Relaunch restores the previous document session through AppKit, including its native autosaved-document recovery. After launch and window restoration finish, if no document is open, MDReader creates an empty `untitled.md` in Split view instead of showing an Open dialog. Restored windows retain their saved editor mode. Explicitly closing a document removes it from the native session; recent history is not treated as an open session.

The editor mode, sidebar visibility, and expanded individual projects use per-scene storage. Appearance, fonts, and the Projects/Recent Files section expansion settings continue to use their existing persisted preferences. Restoration should be checked by quitting normally with Command-Q and relaunching; it is not a backup mechanism for force quits or unavailable files.

## Save confirmation on Mac

Closing a changed document tab uses the native save confirmation. Quitting reviews each document before termination and stops if the user cancels or saving fails. Save keeps the changes; Don’t Save discards them through AppKit, including reverting automatic saves. Unchanged documents close without a prompt. This confirmation preference is set only for MDReader; it does not change other apps’ settings. Discarded untitled drafts are closed so they are not restored on the next launch.

## macOS releases

Download packaged builds from [GitHub Releases](https://github.com/vivamau/MDreader/releases). These preview artifacts are ad-hoc signed and are not notarized.

To build a universal Apple Silicon/Intel DMG with Xcode installed:

```sh
./scripts/package-macos.sh version.number
```

The script verifies both architectures, the app signature, and the disk image, then writes the DMG and SHA-256 checksum under `dist/`. Generated artifacts are excluded from Git. Release binaries are attached to a GitHub release instead of being committed to source history. After pushing the matching version tag, `python3 scripts/publish-github.py 0.1.1` uploads both files and publishes a prerelease; it uses the configured Git credential helper and never prints credentials. Update `RELEASE_NOTES.md` and the Xcode version/build settings before a new version.
