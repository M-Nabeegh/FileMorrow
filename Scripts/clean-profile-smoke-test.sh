#!/bin/zsh
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
profile_dir=$(mktemp -d "${TMPDIR:-/tmp}/filemorrow-clean-profile.XXXXXX")
log_file="$profile_dir/filemorrow.log"
app_pid=""

cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  rm -rf "$profile_dir"
}
trap cleanup EXIT

mkdir -p "$profile_dir/Downloads" "$profile_dir/Library/Preferences"
"$project_dir/Scripts/package-app.sh"

HOME="$profile_dir" \
CFFIXED_USER_HOME="$profile_dir" \
"$project_dir/dist/FileMorrow.app/Contents/MacOS/FileMorrow" \
  >"$log_file" 2>&1 &
app_pid=$!

sleep 4
if ! kill -0 "$app_pid" 2>/dev/null; then
  echo "FileMorrow exited during the clean-profile launch."
  sed -n '1,120p' "$log_file"
  exit 1
fi

echo "Clean-profile smoke test passed: the packaged app remained running with empty settings and Downloads."
