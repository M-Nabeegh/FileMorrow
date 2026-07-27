# Organization Profiles

FileMorrow uses a portable JSON profile as the shared source of truth for
format rules, local content scoring, Apple Intelligence guidance, UI categories,
and destination folders.

The shipped profile is
[`Configuration/default-profile.json`](../Configuration/default-profile.json).
On first launch, the app copies it to:

```text
~/Library/Application Support/DownloadsButler/organization-profile.json
```

Use **Settings → Categories** to enable, disable, add, edit, delete, import, or
export categories. Editing through the app is recommended, but the JSON format
is intentionally readable and versionable.

## Category fields

- `id`: stable identifier stored with decisions
- `name`: user-facing category name
- `folderName`: destination category folder directly under Downloads
- `icon`: SF Symbol name
- `color`: semantic color name
- `description`: guidance passed to Apple Intelligence
- `enabled`: whether the category participates in classification
- `extensions`: normalized extensions without leading dots
- `filenameKeywords`: high-signal terms checked before the file format
- `contentKeywords`: evidence used by the fast local classifier
- `examples`: representative filenames passed to Apple Intelligence
- `contentAware`: whether content may override the extension category
- `extensionConfidence`: confidence assigned to a format-only match

## Classification order

1. Strong filename subject matches
2. Known extension and Uniform Type Identifier
3. Local extracted-content scoring
4. Apple Intelligence using the active numbered profile
5. Needs Review only when the evidence remains ambiguous

Generic containers such as PDF, DOCX, XLSX, and ZIP should normally stay
content-aware. Specific formats such as images, video, audio, installers,
design sources, code, and diagnostics can safely use high extension confidence.

## Sharing profiles

Profiles contain category definitions, not file contents or classification
history. They can be exported, committed to a repository, and shared with other
users. A community profile should avoid personal names and use examples that do
not expose private information.
