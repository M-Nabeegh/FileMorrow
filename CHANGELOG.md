# Changelog

All notable FileMorrow changes are documented here.

## Unreleased

- Add Check for Updates to the FileMorrow menu, the menu-bar companion and
  Settings. It asks GitHub which release is the latest and opens the download
  page; nothing is downloaded or installed automatically. A daily check is
  available in Settings and is off by default.
- Make the main window easier to use with VoiceOver: metric cards and sidebar
  rows read as one item with their count, decorative icons are skipped, and the
  category switches and progress bars have names.
- Publish only the notes for the version being released instead of the whole
  changelog.

## 1.8.0 — 2026-08-20

- Lower the requirement to macOS 14 Sonoma. Foundation Models is weak-linked
  and only called on macOS 26, so every workflow except Smart Content now runs
  on far more Macs, and the app launches normally where the framework does not
  exist.
- Add Installers: find .dmg and .pkg files for software already on this Mac.
  Packages are verified against the install receipts macOS keeps; disk images
  are matched to the installed app and its version. An installer newer than
  what is installed is never listed, so a pending update is never deleted.
  Nothing is mounted, opened, or run, and installed software is never touched.
- Show total reclaimable space across duplicates, archives, and installers in
  the sidebar and the menu-bar companion.
- Add Extracted Archives: find ZIP files whose contents are already unpacked
  next to them and move just the archive to recoverable Trash. Every entry must
  match the unpacked file's size before an archive is listed, the archive is
  re-verified once more at the moment of deletion, and the unpacked folders are
  never touched.
- Let the user choose which copy of a duplicate group survives cleanup. The
  scanner now proposes the least buried and oldest copy instead of whichever
  path happened to sort first.
- Re-read duplicate bytes from disk before deleting anything, so a file that
  changed between the scan and the confirmation is refused rather than trashed.
- Refuse duplicate cleanup outright when the copy marked to keep has gone.
- Keep deleted categories deleted and removed formats, keywords, and examples
  removed when a profile merges with built-in knowledge on the next launch.
- Never let a single locked or unreadable file stop the rest of an organization
  run; the batch finishes and stays undoable.
- Stop analysis from tracking files by list position, which could target the
  wrong file or crash if the list changed mid-run.
- Write analysis decisions once per run instead of rewriting the whole file per
  file, and prune decisions and first-seen dates for files that no longer exist.
- Cap the move history so undo stays fast on long-running installs.
- Guard the Scan, Analyze, and classification-mode controls while work is in
  flight so they cannot interrupt a running job.
- Stop content extraction from stalling on encrypted or corrupt archives.

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
