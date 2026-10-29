#!/bin/bash
set -euo pipefail

# Toggle window-open defaults: floating 1920x1080 vs Hyprland's normal
# tiled/dwindle behavior. State file lives in /tmp so mode resets on
# reboot (matches toggle-opacity.sh convention).
#
# ON  mode: new windows float at 1920x1080.
# OFF mode: default dwindle tiling — first window on a workspace fills it.
STATE_FILE="/tmp/hypr-float-mode-on"

if [ -f "$STATE_FILE" ]; then
    # ON → OFF: drop runtime-added rules by re-parsing the on-disk config.
    hyprctl reload
    rm "$STATE_FILE"
    notify-send -u low -i preferences-system "Window mode" "Default: tiled (dwindle)"
else
    # OFF → ON: layer runtime rules on top.
    hyprctl eval 'hl.window_rule({ name = "toggle-window-mode-float", match = { class = ".+" }, float = true })'
    hyprctl eval 'hl.window_rule({ name = "toggle-window-mode-size", match = { class = ".+" }, size = "1920 1080" })'
    touch "$STATE_FILE"
    notify-send -u low -i preferences-system "Window mode" "Default: floating 1920x1080"
fi
