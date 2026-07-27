#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
build_dir="$project_dir/.build/release"
output_dir="$project_dir/dist"
app_dir="$output_dir/FileMorrow.app"

cd "$project_dir"
swift build -c release

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp "$build_dir/FileMorrow" "$app_dir/Contents/MacOS/FileMorrow"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Assets/FileMorrow.icns" "$app_dir/Contents/Resources/FileMorrow.icns"
cp "$project_dir/Configuration/default-profile.json" "$app_dir/Contents/Resources/default-profile.json"

if [[ -n "${FILEMORROW_SIGN_IDENTITY:-}" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$FILEMORROW_SIGN_IDENTITY" \
    "$app_dir"
else
  codesign --force --deep --sign - "$app_dir"
fi
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"
