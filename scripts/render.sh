#!/usr/bin/env bash
# render.sh <dest-dir> [data-file]  - apply this source into a scratch destination (never $HOME).
set -euo pipefail
dest=${1:?dest}; data=${2:-}
repo=$(cd "$(dirname "$0")/.." && pwd)
case $(realpath -m "$dest") in "$(realpath "$HOME")"|/) echo "refusing to render into HOME" >&2; exit 2;; esac
state=$(mktemp -d)   # scratch dir under TMPDIR; pruned by the host
cfg=$state/empty.toml; : > "$cfg"; [[ -n $data ]] && cfg=$data
mkdir -p "$dest"
chezmoi --no-tty --source "$repo" --config "$cfg" --destination "$dest" \
  --persistent-state "$state/state.boltdb" apply --force --exclude=scripts < /dev/null > /dev/null
