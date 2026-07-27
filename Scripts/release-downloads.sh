#!/bin/zsh
set -euo pipefail

repository="${1:-M-Nabeegh/FileMorrow}"
payload=$(curl --fail --silent --show-error \
  "https://api.github.com/repos/${repository}/releases")

count=$(printf '%s' "$payload" | /usr/bin/python3 -c '
import json
import sys

releases = json.load(sys.stdin)
print(sum(asset.get("download_count", 0) for release in releases for asset in release.get("assets", [])))
')

printf '%s release asset downloads\n' "$count"
