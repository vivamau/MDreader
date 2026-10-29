# MDReader 0.3.0

Preview release for macOS 14 and later, supporting Apple Silicon and Intel. Build 5.

- Makes the Markdown editor slightly darker than the preview while preserving the background selected in Settings.
- Keeps the tab and toolbar header on a native translucent material instead of extending the document color behind it.
- Renders Mermaid diagrams in both the in-app print preview and the macOS system print dialog using high-resolution attachments.
- Refreshes the native print preview when Markdown changes.
- Enlarges the Settings popover just enough to display its controls without routine scrolling.

Validation includes the complete regression suite, macOS and iOS Simulator builds, a universal macOS release build, DMG integrity checks, and published asset checksum verification.

## Installation

Download `MDReader-0.3.0-macOS-universal.dmg`, mount it, and drag MDReader to Applications.

This preview is ad-hoc signed, **not Developer ID signed or notarized**. macOS Gatekeeper may block its first launch. The matching `.sha256` file provides the download checksum.

The DMG is for macOS only; iOS source and assets are available in the repository.
