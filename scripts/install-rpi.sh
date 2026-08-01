#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sudo apt-get update
sudo apt-get install -y bluez python3-venv python3-pygame

python3 -m venv --system-site-packages "$project_dir/.venv"
"$project_dir/.venv/bin/pip" install --editable "$project_dir"

printf '\nInstalled. Test the display with:\n%s\n' \
  "$project_dir/.venv/bin/python -m emu_dash --demo"

