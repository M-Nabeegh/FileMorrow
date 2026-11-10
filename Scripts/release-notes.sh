#!/bin/zsh
# Prints the CHANGELOG.md section for one version, for use as GitHub release notes.
#   Scripts/release-notes.sh 1.8.0
set -euo pipefail

project_dir=${0:A:h:h}
version=${1:?Usage: release-notes.sh <version>}
version=${version#v}

notes=$(awk -v version="$version" '
  /^## / {
    if (printing) exit
    if ($2 == version) { printing = 1; next }
  }
  printing { print }
' "$project_dir/CHANGELOG.md" | sed -e :a -e '/./,$!d' -e '/^\n*$/{$d;N;ba' -e '}')

if [[ -z "${notes//[[:space:]]/}" ]]; then
  print -u2 "CHANGELOG.md has no section for $version."
  exit 1
fi

print -r -- "$notes"
