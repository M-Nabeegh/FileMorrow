# FileMorrow

A private, content-aware Downloads organizer for macOS, made by Nabeegh and
powered by the Apple
Foundation Models framework.

FileMorrow keeps fresh files in **Today**, **Yesterday**, and **Last 7
Days** views. Older files enter a review queue where deterministic rules and
Apple Intelligence suggest meaningful folders. Nothing moves until the user
chooses **Organize**, and every batch can be undone.

## Highlights

- On-device classification with Apple Foundation Models
- Predictable **By File Format** mode with no AI queue
- Optional **Smart Content** mode using metadata, extracted content, and Apple Intelligence
- Fast local evidence scoring before invoking the language model
- Content extraction for PDF, DOCX, PPTX, XLSX, ZIP, text, code, and images
- Local OCR with Vision
- Persistent AI decisions and user corrections
- Quick Look file previews and one-click opening in the file’s default app
- A **Teach Organizer** workflow for corrections, filename rules, format rules,
  and reusable on-device model examples
- Separate Awaiting Analysis and Needs Review states
- Analyze-next and continuous Analyze All modes with a Stop control
- Editable, importable, and exportable organization profiles
- User-selectable and fully custom categories
- Confidence-gated organization
- Batch undo and collision-safe moves
- Exact duplicate detection with SHA-256 and recoverable Trash cleanup
- Strict top-level-only scope: folders and every file inside them are never scanned or moved
- Color-coded Finder icons distinguish FileMorrow-managed category folders from ordinary folders
- Menu-bar companion for status, rescanning, duplicate checks, and reopening the app
- Native SwiftUI interface and Settings window
- No analytics, accounts, cloud API keys, or content uploads

## Requirements

- macOS 26 or later
- Apple silicon Mac supported by Apple Intelligence
- Apple Intelligence enabled and its model downloaded
- Xcode 26 or later to build from source

The app checks Foundation Models availability on launch under **Settings →
Compatibility**. If Apple Intelligence is unavailable, deterministic rules,
file previews, and manual teaching continue to work; only model analysis is
disabled with an explanation.

## Build

```bash
swift build -c release
swift test
```

Package a standard ad-hoc-signed macOS application:

```bash
./Scripts/package-app.sh
```

The app is written to `dist/FileMorrow.app`.

Create local ZIP and DMG release artifacts with SHA-256 checksums:

```bash
./Scripts/create-release.sh
```

GitHub release packages are ad-hoc signed and include SHA-256 checksums. They
are not notarized because this independent open-source project does not
currently have an Apple Developer membership.

## Install a GitHub release

1. Download the DMG or ZIP and `SHA256SUMS.txt` from the same release.
2. Verify the checksum with `shasum -a 256 -c SHA256SUMS.txt`.
3. Move FileMorrow to Applications and try to open it once.
4. If macOS blocks it, open **System Settings → Privacy & Security**, scroll to
   **Security**, and choose **Open Anyway**, then authenticate and confirm.

Only override Gatekeeper when the download came from the official FileMorrow
GitHub repository and its SHA-256 checksum matches. Apple notes that software
from an unidentified developer has not been reviewed by Apple, so users should
make this exception only for software they trust. See
[Apple’s Open Anyway instructions](https://support.apple.com/guide/mac-help/mh40616/mac).

## Safety model

FileMorrow defaults to **By File Format** mode: documents, audio, images,
videos, spreadsheets, installers, archives, design files, and code are placed
by known extensions and system file types. This is fast, predictable, and does
not require an analysis queue.

Users can opt into **Smart Content** mode. It considers filename metadata,
extracts a short local evidence sample, and uses Apple's on-device model to
suggest subject folders such as University, Finance, or Medical. These are
suggestions: the model can make mistakes, so important files should be reviewed.
Low-confidence items remain in **Needs Review**. Organization
creates `~/Downloads/<Category>` and records every
move for undo.

FileMorrow persists each top-level file's first-seen date locally. Moving
or undoing a file therefore does not reset the seven-day eligibility window.

The organizer and duplicate finder operate only on loose regular files directly
inside `~/Downloads`. Existing, newly created, and newly downloaded folders are
always left in place, and the app never enters or modifies their contents.

## Menu bar

The menu-bar companion remains available when the main window is closed. It can
reopen the app, rescan Downloads, check and organize eligible files, check for
duplicates, open Settings, or quit. By default the app launches at login and
checks hourly. Only loose files older than the configured age (seven days by
default) are moved. Deterministic format matches move automatically; uncertain
files remain for review. Both automatic organization and Launch at Login can be
disabled in Settings.

**All Downloads** also presents files directly inside FileMorrow-managed
category folders as a read-only library. Managed folders carry a hidden marker;
arbitrary user/downloaded folders are never entered. Organized files are labeled
and excluded from the seven-day queue so they cannot be moved twice.

## Project structure

- `AppState.swift` — application state and workflows
- `ContentExtractor.swift` — PDF, Office, archive, text, and OCR evidence
- `AIClassifier.swift` — structured on-device classification
- `RuleClassifier.swift` — deterministic and semantic fast path
- `PersistenceStore.swift` — decisions and move history
- `OrganizerService.swift` — collision-safe move and undo
- `Views.swift` — native macOS interface
- `Configuration/default-profile.json` — general-purpose format and category catalog

## Custom categories

Open **Settings → Categories** to choose which categories are active, edit their
format and keyword guidance, or add completely new categories. Profiles can be
imported and exported as JSON, making them easy to share or version. See
[`docs/PROFILES.md`](docs/PROFILES.md) for the schema and classification order.

## Preview and teach

Select a file to see its native Quick Look preview. **Open File** launches it in
the user’s default app. **Teach Organizer…** corrects the current file and adds
it as an example for the on-device model. A user can optionally provide a
reusable filename phrase or explicitly map the file extension to that category.
Extension rules are opt-in because broad formats such as PDF and PPTX can cover
many different subjects.

## Privacy

File contents stay on the Mac. The project does not include telemetry,
networking, advertising, or third-party analytics.

## License

MIT
