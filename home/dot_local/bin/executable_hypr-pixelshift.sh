#!/bin/bash
# hypr-pixelshift.sh — OLED burn-in mitigation via Hyprland gap jitter.
#
# Reads baseline gap values once at startup from hyprland.conf (not hardcoded)
# and applies a small random offset every 10 minutes via hyprctl keyword.
# Offset ranges are chosen to be imperceptible while still shifting every
# window's pixel boundary by a few px — enough to break any fixed luminance
# pattern over multi-hour sessions.
#
# Managed by hypr-pixelshift.service (systemd user unit).
set -euo pipefail

HYPRLAND_CONF="${HYPRLAND_CONF:-$HOME/.config/hypr/hyprland.conf}"

if [[ ! -r "$HYPRLAND_CONF" ]]; then
    echo "hypr-pixelshift: cannot read $HYPRLAND_CONF" >&2
    exit 1
fi

# Extract the current gaps_out and gaps_in values from the general block.
# Format in repo: `    gaps_out = 8` / `    gaps_in = 4`. Take first numeric
# token after '=' so we tolerate extra whitespace or trailing comments.
base_out="$(awk '/^[[:space:]]*gaps_out[[:space:]]*=/ { print $3; exit }' "$HYPRLAND_CONF")"
base_in="$(awk '/^[[:space:]]*gaps_in[[:space:]]*=/ { print $3; exit }' "$HYPRLAND_CONF")"

# Fallback to Liquid Tron defaults if parsing failed for any reason.
[[ "$base_out" =~ ^[0-9]+$ ]] || base_out=8
[[ "$base_in"  =~ ^[0-9]+$ ]] || base_in=4

echo "hypr-pixelshift: base gaps_out=$base_out gaps_in=$base_in"

while true; do
    # gaps_out drift: -3..+3 (7 values)
    out_offset=$(( RANDOM % 7 - 3 ))
    # gaps_in drift:  -2..+2 (5 values)
    in_offset=$(( RANDOM % 5 - 2 ))

    out_val=$(( base_out + out_offset ))
    in_val=$(( base_in  + in_offset ))

    # Clamp to non-negative; Hyprland rejects negative gaps.
    (( out_val < 0 )) && out_val=0
    (( in_val  < 0 )) && in_val=0

    hyprctl eval "hl.config({ general = { gaps_out = $out_val } })" >/dev/null
    hyprctl eval "hl.config({ general = { gaps_in = $in_val } })"  >/dev/null

    sleep 600
done
