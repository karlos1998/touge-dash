#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcrun >/dev/null 2>&1; then
  printf 'Brakuje Apple Command Line Tools. Uruchom: xcode-select --install\n' >&2
  exit 1
fi

python3 -m venv "$project_dir/.venv"
"$project_dir/.venv/bin/pip" install --editable "$project_dir"

printf '\nGotowe. Uruchom dashboard:\n%s\n' \
  "$project_dir/.venv/bin/emu-dash --web"

