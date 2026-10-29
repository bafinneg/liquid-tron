#!/bin/bash
# hypr-lock-drift.sh — OLED-safe lock wrapper
# aesthetic-oled-burnin-mitigation Chunk 3.
#
# Flow:
#   1. Generate tmp hyprlock config with randomized input-field position
#   2. Launch a kitty window running unimatrix (matrix rain) in background
#   3. Drift loop: nudge the kitty window ±20px every 30 seconds
#   4. Run hyprlock -c <tmp_conf> in foreground (blocks until unlock)
#   5. Trap cleanup on EXIT: kill background procs, remove tmp config
#
# Visibility caveat: hyprlock paints an opaque overlay layer, so the
# matrix rain behind it may not actually show through. In that case the
# lock is still maximally OLED-safe (pure black background + invisible
# drifting input field). Runtime verification pending.

set -euo pipefail

canonical="${HOME}/.config/hypr/hyprlock.conf"
tmp_conf="$(mktemp /tmp/hyprlock-drift.XXXXXX.conf)"

# Randomize input-field position — x ∈ [-400, +400], y ∈ [-200, +200]
# Conservative range: keeps the 400×40 field fully on-screen on a 4K panel.
rand_x=$((RANDOM % 801 - 400))
rand_y=$((RANDOM % 401 - 200))

# Logomark image drift — ±40px per lock for OLED safety (FEAT-liquid-tron-logomark S2).
logo_rand_x=$((RANDOM % 81 - 40))
logo_rand_y=$((RANDOM % 81 - 40))
logo_x=$((120 + logo_rand_x))
logo_y=$((-120 + logo_rand_y))

sed -e "s|^    position = 0, -10\$|    position = ${rand_x}, ${rand_y}|" \
    -e "s|^    position = 120, -120\$|    position = ${logo_x}, ${logo_y}|" \
    "$canonical" > "$tmp_conf"

# Launch kitty with unimatrix matrix rain. Spec-literal flags:
#   -c cyan   — pure #0abdc6 accent
#   -s 95     — spec-specified speed (note: spec prose says "slowest" but
#               unimatrix -s scale is 0=slowest / 100=fastest; 95 is
#               near-fastest — flagged for Brian review)
#   -l o      — spec-specified character set (note: "o" = "AaSn" per
#               unimatrix(1), not lowercase-only as spec prose claims —
#               flagged for Brian review)
#   -i        — ignore keyboard so unimatrix doesn't react to keystrokes
kitty --class=hyprlock-matrix \
      -e unimatrix -i -c cyan -s 95 -l o &
kitty_pid=$!

# Drift loop — nudge the kitty window ±20px every 30s. Best-effort:
# suppress errors if the window isn't addressable or not floating.
drift_loop() {
    sleep 2  # let kitty register with hyprland
    hyprctl dispatch togglefloating class:hyprlock-matrix >/dev/null 2>&1 || true
    while kill -0 "$kitty_pid" 2>/dev/null; do
        dx=$((RANDOM % 41 - 20))
        dy=$((RANDOM % 41 - 20))
        hyprctl dispatch movewindowpixel "${dx} ${dy},class:hyprlock-matrix" \
            >/dev/null 2>&1 || true
        sleep 30
    done
}
drift_loop &
drift_pid=$!

cleanup() {
    kill "$drift_pid" 2>/dev/null || true
    kill "$kitty_pid" 2>/dev/null || true
    rm -f "$tmp_conf"
}
trap cleanup EXIT

# Foreground — blocks until unlock
hyprlock -c "$tmp_conf"

# Trigger unlock splash overlay in quickshell
date +%s > /tmp/mocr-unlock-trigger
