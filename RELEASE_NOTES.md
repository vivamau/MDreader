# MDReader 0.4.0

Preview release for macOS 14 and later, supporting Apple Silicon and Intel. Build 6.

- Adds a Markdown formatting toolbar with headings, bold, italic, underline, links, quotes, inline and fenced code, and bulleted and numbered lists.
- Applies formatting to the current selection and keeps convenient insertion points when no text is selected.
- Makes the formatting controls easier to use with 20-point icons and larger button targets.
- Uses native resizable split panes on macOS, including the standard resize cursor and smooth live resizing.
- Allows the window to move when dragging the central header area.
- Uses the selected preview font and size in the print preview and printed document.
- Preserves Mermaid diagram sizing during preview layout and printing.

Validation includes the complete regression suite, macOS and iOS Simulator builds, a universal macOS release build, DMG integrity checks, and published asset checksum verification.

## Installation

Download `MDReader-0.4.0-macOS-universal.dmg`, mount it, and drag MDReader to Applications.

This preview is ad-hoc signed, **not Developer ID signed or notarized**. macOS Gatekeeper may block its first launch. The matching `.sha256` file provides the download checksum.

The DMG is for macOS only; iOS source and assets are available in the repository.
