#!/usr/bin/env bash
# A fresh machine with no host data file must render cleanly, with placeholders only and no private values.
# Runs under a fake HOME so chezmoi's homeDir cannot be this host's.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
bl=${LT_BLOCKLIST:-$HOME/home-infra/machines/7800x/chezmoi/blocklist.txt}
tmp=$(mktemp -d -t lt-generic.XXXXXX)
dest=$tmp/out
if ! HOME=/home/user "$repo/scripts/render.sh" "$dest"; then echo "GENERIC FAIL (render error)"; exit 1; fi
n=$(find "$dest" \( -type f -o -type l \) | wc -l)
echo "generic render: $n files"
fail=0
if [[ $n -le 800 ]]; then echo "too few files"; fail=1; fi
if [[ -f $bl ]]; then
  grep -v -e '^#' -e '^$' "$bl" > "$tmp/bl.txt"
  ( cd "$dest" && grep -rIl -i -F -f "$tmp/bl.txt" . ) > "$tmp/priv.txt"
  if [[ -s $tmp/priv.txt ]]; then head -5 "$tmp/priv.txt"; fail=1; fi
fi
( cd "$dest" && grep -rIn -E -f "$repo/scripts/leak-patterns.txt" . ) | grep -v -F '/home/user/' > "$tmp/pub.txt"
if [[ -s $repo/scripts/leak-allow.txt ]]; then grep -v -E -f "$repo/scripts/leak-allow.txt" "$tmp/pub.txt" > "$tmp/pub2.txt"; else cp "$tmp/pub.txt" "$tmp/pub2.txt"; fi
if [[ -s $tmp/pub2.txt ]]; then cut -c1-170 "$tmp/pub2.txt" | head -5; fail=1; fi
if ! grep -rIq -F 'LEFT-SERIAL' "$dest"; then echo "placeholder serials missing"; fail=1; fi
if [[ $fail -eq 0 ]]; then echo "GENERIC PASS"; else echo "GENERIC FAIL"; fi
exit $fail
