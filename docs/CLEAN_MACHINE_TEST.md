# Clean-machine test matrix

Run this matrix before each public release on a second, Apple
Intelligence-eligible Mac. Use a fresh macOS user account and synthetic files
only.

| State | Expected result |
|---|---|
| Empty settings, first launch | Welcome sheet appears before automatic organization can run |
| Format mode | Works without Apple Intelligence and creates only top-level managed category folders |
| Apple Intelligence disabled | Compatibility explains how to enable it; Smart Content does not run |
| Device not eligible | Compatibility explains the hardware requirement; Format mode remains available |
| Model not ready | Compatibility reports a temporary model state; Format mode remains available |
| Apple Intelligence enabled and ready | Smart Content analyzes synthetic fixtures on device |
| File younger than seven days | Remains loose in Downloads |
| File older than seven days | Moves only after setup and only when approved |
| Downloaded folder | Folder and all contents remain untouched |
| Undo | Last organization batch returns without overwriting an existing filename |
| Duplicates | Exact hashes group together; selected extras move to Trash |

Local preflight:

```bash
swift test
./Scripts/clean-profile-smoke-test.sh
```

The script launches the packaged app with a temporary home, empty preferences,
and empty Downloads directory. It proves clean-profile startup without changing
the developer's real settings. It cannot substitute for the two physical
Apple Intelligence states above; record the second-Mac result in the release
notes before calling a release fully compatibility-tested.
