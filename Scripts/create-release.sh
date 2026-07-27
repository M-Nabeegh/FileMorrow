#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$project_dir/Info.plist")
release_dir="$project_dir/dist/release"
app="$project_dir/dist/FileMorrow.app"

cd "$project_dir"
if [[ "${SKIP_PACKAGE:-0}" != "1" ]]; then
  "$project_dir/Scripts/package-app.sh"
fi

if [[ ! -d "$app" ]]; then
  print -u2 "FileMorrow.app is missing. Run Scripts/package-app.sh first."
  exit 1
fi

rm -rf "$release_dir"
mkdir -p "$release_dir"

zip_path="$release_dir/FileMorrow-$version-macOS.zip"
dmg_path="$release_dir/FileMorrow-$version-macOS.dmg"

ditto -c -k --keepParent "$app" "$zip_path"
hdiutil create \
  -volname "FileMorrow" \
  -srcfolder "$app" \
  -format UDZO \
  -ov \
  "$dmg_path" >/dev/null

(
  cd "$release_dir"
  shasum -a 256 "$(basename "$zip_path")" "$(basename "$dmg_path")" > SHA256SUMS.txt
)

codesign --verify --deep --strict "$app"
print "$release_dir"
