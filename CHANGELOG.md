# Changelog

All notable FileMorrow changes are documented here.

## 1.7.1 — 2026-07-27

- Default Automatic Organization and Launch at Login to on for new installs.
- Treat the onboarding toggle as one-time consent for unattended hourly
  organization; automatic checks no longer ask again.
- Keep plan-first approval for manual organization and keep Undo Last
  Organization visible after every automatic batch.

## 1.7 — 2026-07-27

- Add a plan-first approval sheet showing file count, size, and destinations
  before any eligible file moves.
- Require approval for hourly checks instead of silently organizing files.
- Make Undo Last Organization explicit in the toolbar, app menu, status, and
  Command-Z shortcut.
- Speed up duplicate discovery with a first/last-block fingerprint before full
  SHA-256 verification.
- Add duplicate-scan stage, file, byte, and progress reporting with a Stop
  control.
- Cache verified hashes during the session and skip unavailable cloud
  placeholders.
- Default first-launch automatic checks and Launch at Login to off.

## 1.6 — 2026-07-27

- Keep the menu-bar companion alive when the main window closes.
- Add a Keep FileMorrow in the Dock setting for menu-bar-only use.
- Add Show Welcome Guide commands in the app menu, menu bar, and Settings.
- Scan all accessible folders inside Downloads for exact SHA-256 duplicates.
- Keep organization top-level-only and duplicate cleanup explicit and recoverable.
- Add polished Finder-folder and menu-bar screenshots.
- Rename the Swift package, executable, source folder, and test folder to FileMorrow.

## 1.5.1 — 2026-07-27

- Rescan automatically whenever FileMorrow becomes active after using Finder.
- Remove deleted file rows and clear their stale inspector selection.

## 1.5 — 2026-07-27

- Added consent-first onboarding for the seven-day rule, folder boundary,
  Format mode, Smart Content, Undo, duplicates, and Apple Intelligence status.
- Prevented automatic organization and Launch at Login registration before
  onboarding is completed.
- Added typed compatibility handling for Apple Intelligence disabled,
  ineligible-device, model-not-ready, available, and unknown states.
- Added a privacy-safe synthetic accuracy suite with generated PDF, PPTX, XLSX,
  and ambiguous-file fixtures.
- Added public screenshots, mode comparison, privacy architecture, and a
  clean-machine checklist.
- Added a concrete private security-reporting channel.

## 1.4 — 2026-07-27

The downloadable build is ad-hoc signed and not notarized. Verify its SHA-256
checksum before using Privacy & Security → Open Anyway.

- Renamed the app to FileMorrow and added “Made by Nabeegh” to About.
- Added a redesigned app icon and color-coded Finder icons for managed folders.
- Added automatic hourly organization for eligible files older than seven days.
- Added Launch at Login and a menu-bar companion.
- Added exact duplicate detection and recoverable cleanup.
- Preserved loose folders and their contents as strictly out of scope.
- Displayed organized files in the read-only library without re-queuing them.
- Added format-only and optional Apple Intelligence classification modes.
- Added custom categories, profiles, previews, teaching and Undo.
