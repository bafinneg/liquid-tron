#!/usr/bin/env bash
# Leak gate. Exit 0 only when all three layers are clean.
#  1. gitleaks over the tree and history
#  2. public pattern list (scripts/leak-patterns.txt): generic shapes that must not appear
#  3. private value list (optional, outside this repo): LT_BLOCKLIST or ~/home-infra/machines/7800x/chezmoi/blocklist.txt
set -u
repo=$(cd "$(dirname "$0")/.." && pwd); cd "$repo" || exit 2
tmp=$(mktemp -d -t ltgate.XXXXXX)
rc=0

echo "[1/3] gitleaks"
if ! gitleaks git --no-banner --redact -c "$repo/.gitleaks.toml" . > "$tmp/gl.txt" 2>&1; then
  grep -E 'RuleID|File' "$tmp/gl.txt" | head -10
  rc=1
fi

echo "[2/3] public patterns"
git grep -I -n -E -f scripts/leak-patterns.txt -- . ':!scripts/leak-patterns.txt' ':!scripts/leak-allow.txt' > "$tmp/pub.txt"
if [[ -s scripts/leak-allow.txt ]]; then grep -v -E -f scripts/leak-allow.txt "$tmp/pub.txt" > "$tmp/pub2.txt"; else cp "$tmp/pub.txt" "$tmp/pub2.txt"; fi
if [[ -s $tmp/pub2.txt ]]; then cut -c1-170 "$tmp/pub2.txt" | head -20; rc=1; fi

echo "[3/3] private values"
bl=${LT_BLOCKLIST:-$HOME/home-infra/machines/7800x/chezmoi/blocklist.txt}
if [[ -f $bl ]]; then
  grep -v -e '^#' -e '^$' "$bl" > "$tmp/bl.txt"
  git grep -I -i -n -F -f "$tmp/bl.txt" -- . > "$tmp/priv.txt"
  if [[ -s $tmp/priv.txt ]]; then cut -c1-170 "$tmp/priv.txt" | head -20; rc=1; fi
else
  echo "  (no private list on this host; layers 1-2 only)"
fi

if [[ $rc -eq 0 ]]; then echo "LEAK GATE PASS"; else echo "LEAK GATE FAIL"; fi
exit $rc
