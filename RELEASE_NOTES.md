# MDReader 0.5.0

Preview release for macOS 14 and later, supporting Apple Silicon and Intel. Build 7.

- Adds a Mermaid snippet menu to the Markdown formatting toolbar.
- Includes ready-to-edit Flowchart, Sequence Diagram, State Diagram, and Pie Chart templates.
- Inserts each snippet as a complete fenced Mermaid block that renders immediately in Preview and Split view.
- Selects the first meaningful placeholder after insertion so the diagram can be customized without repositioning the cursor.
- Keeps the snippet menu available on both macOS and iOS/iPadOS.

Validation includes the complete regression suite, macOS and iOS Simulator builds, a universal macOS release build, DMG integrity checks, and published asset checksum verification.

## Installation

Download `MDReader-0.5.0-macOS-universal.dmg`, mount it, and drag MDReader to Applications.

This preview is ad-hoc signed, **not Developer ID signed or notarized**. macOS Gatekeeper may block its first launch. The matching `.sha256` file provides the download checksum.

The DMG is for macOS only; iOS source and assets are available in the repository.
