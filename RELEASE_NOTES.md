# MDReader 0.2.0

Preview release for macOS 14 and later, supporting Apple Silicon and Intel. Build 3.

- Restores the previous document session on startup, with an empty `untitled.md` in Split view when no session is available.
- Removes the startup file picker and preserves restored editor modes.
- Removes the duplicate toolbar theme toggle; theme selection remains in Settings.

Validation: universal macOS build, DMG integrity and SHA-256 checks, and all 22 regression tests passed.

## Installation

Download `MDReader-0.2.0-macOS-universal.dmg`, mount it, and drag MDReader to Applications.

This preview is ad-hoc signed, **not Developer ID signed or notarized**. macOS Gatekeeper may block its first launch. The matching `.sha256` file provides the download checksum.

The DMG is for macOS only; iOS source and assets are available in the repository.
