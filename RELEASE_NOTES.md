# MDReader 0.2.1

Preview release for macOS 14 and later, supporting Apple Silicon and Intel. Build 4.

- Adds a trash icon beside filenames in Projects and Recent Files, turning red on hover.
- Requires confirmation before deleting a file and removes its references from all projects and Recent Files.
- On Mac, moves files to Trash and honors Save/Discard/Cancel for open documents.
- On iOS, deletion is permanent; the currently displayed document must be closed first.

Validation: universal macOS build, DMG integrity and SHA-256 checks, and all 23 regression tests passed. macOS and iOS Simulator debug builds also passed.

## Installation

Download `MDReader-0.2.1-macOS-universal.dmg`, mount it, and drag MDReader to Applications.

This preview is ad-hoc signed, **not Developer ID signed or notarized**. macOS Gatekeeper may block its first launch. The matching `.sha256` file provides the download checksum.

The DMG is for macOS only; iOS source and assets are available in the repository.
