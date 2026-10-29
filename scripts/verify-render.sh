#!/usr/bin/env bash
# Host render == Stow originals (byte-identical) for every migrated module. Exit 0 = PASS.
set -euo pipefail
exec python3 -I "$(dirname "$0")/verify_render.py" "$@"
