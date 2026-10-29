#!/bin/bash
set -euo pipefail

# Toggle float/tile for every normal window on the active workspace.
# If any window is tiled → float all. Otherwise (all floating) → tile all.
# Replaces the deprecated `workspaceopt allfloat` dispatcher, which is
# non-functional in Hyprland 0.54.x.

ws=$(hyprctl activeworkspace -j | jq -r '.id')
mapfile -t addrs < <(hyprctl -j clients | jq -r --argjson ws "$ws" \
    '.[] | select(.workspace.id == $ws) | .address')

[ "${#addrs[@]}" -eq 0 ] && exit 0

any_tiled=0
for addr in "${addrs[@]}"; do
    floating=$(hyprctl -j clients | jq -r --arg a "$addr" \
        '.[] | select(.address == $a) | .floating')
    [ "$floating" = "false" ] && { any_tiled=1; break; }
done

if [ "$any_tiled" -eq 1 ]; then
    target="enable"
    msg="All windows floating"
else
    target="disable"
    msg="All windows tiled"
fi

batch=""
for addr in "${addrs[@]}"; do
    batch+="dispatch hl.dsp.window.float({action=\"$target\", window=\"address:$addr\"});"
done
hyprctl --batch "$batch" >/dev/null

notify-send -u low -i preferences-system-windows "Workspace $ws" "$msg"
