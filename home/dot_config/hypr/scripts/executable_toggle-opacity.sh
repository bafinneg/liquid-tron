#!/bin/bash
set -euo pipefail

# Window opacity: SUPER+O toggle and the shared apply primitive (FEAT-lt26r-3 OD-D).
#
# The values live ONLY in hyprland.lua between "BEGIN opacity-authority" and "END opacity-authority" and in
# kitty.conf (background_opacity). This script carries no opacity literals; it parses those files.
#
# Usage:
#   toggle-opacity.sh                 SUPER+O: toggle the forced-opaque hold (marker hypr-opacity-opaque)
#   toggle-opacity.sh apply opaque    force every window and Kitty opaque
#   toggle-opacity.sh apply configured  restore the configured look from hyprland.lua and kitty.conf
#
# Two holds can force opacity: SUPER+O (hypr-opacity-opaque) and gaming (gaming-mode-set-opacity, owned by
# system-mode-toggle). The configured look returns only when neither hold remains, so either order ends opaque
# while one hold is active and restores the configured look after both are released.
# Markers live in /tmp so the configured look returns after a reboot.

STATE_DIR="${OPACITY_STATE_DIR:-/tmp}"
STATE_FILE="$STATE_DIR/hypr-opacity-opaque"
GAMING_FILE="$STATE_DIR/gaming-mode-set-opacity"
HYPR_LUA="${OPACITY_HYPR_LUA:-$HOME/.config/hypr/hyprland.lua}"
KITTY_CONF="${OPACITY_KITTY_CONF:-$HOME/.config/kitty/kitty.conf}"

# Print one action per line: "eval <lua>", "dispatch <lua>" or "kitty <alpha>".
plan() {
    local target="$1"
    hyprctl clients -j | /usr/bin/python3 -I -c '
import json, re, sys
target, lua_path, kitty_path = sys.argv[1:4]
text = open(lua_path).read()
m = re.search(r"BEGIN opacity-authority.*?\n(.*?)\n[^\n]*END opacity-authority", text, re.S)
if not m:
    sys.exit("opacity-authority block not found in " + lua_path)
block = m.group(1)
def num(key):
    v = re.search(r"^\s*" + key + r"\s*=\s*([0-9.]+)\s*,", block, re.M)
    if not v:
        sys.exit("opacity-authority: missing " + key)
    return v.group(1)
classes = [(r, a, i) for r, a, i in re.findall(r"\{\s*\"([^\"]+)\"\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\}", block)]
kitty = None
for line in open(kitty_path):
    k = re.match(r"^\s*background_opacity\s+([0-9.]+)\s*$", line)
    if k:
        kitty = k.group(1)
if kitty is None:
    sys.exit("background_opacity not set in " + kitty_path)
one = "1.0"
glob = {"active_opacity": num("active"), "inactive_opacity": num("inactive"), "fullscreen_opacity": num("fullscreen")}
if target == "opaque":
    glob = {k: one for k in glob}
for key, val in glob.items():
    print("eval hl.config({ decoration = { %s = %s } })" % (key, val))
for c in json.load(sys.stdin):
    addr, cls = c.get("address", ""), c.get("class", "")
    if target == "opaque":
        act = ina = one
    else:
        act, ina = num("active"), num("inactive")
        for regex, a, i in classes:
            if re.search(regex, cls):
                act, ina = a, i
                break
    for prop, val in (("opacity", act), ("opacity_inactive", ina)):
        print("dispatch hl.dsp.window.set_prop({ prop = \"%s\", value = \"%s override\", window = \"address:%s\" })" % (prop, val, addr))
print("kitty " + (one if target == "opaque" else kitty))
' "$target" "$HYPR_LUA" "$KITTY_CONF"
}

apply() {
    local target="$1" kind rest actions
    actions=$(plan "$target")
    while IFS= read -r line; do
        kind=${line%% *}
        rest=${line#* }
        case "$kind" in
            eval) hyprctl eval "$rest" >/dev/null ;;
            dispatch) hyprctl dispatch "$rest" >/dev/null ;;
            kitty) kitty @ --to unix:/tmp/kitty-socket set-background-opacity "$rest" 2>/dev/null || true ;;
        esac
    done <<<"$actions"
}

case "${1:-toggle}" in
    apply)
        [[ ${2:-} == opaque || ${2:-} == configured ]] || { echo "usage: toggle-opacity.sh apply opaque|configured" >&2; exit 64; }
        apply "$2"
        ;;
    toggle)
        if [ -f "$STATE_FILE" ]; then
            rm -f "$STATE_FILE"
            if [ -f "$GAMING_FILE" ]; then
                apply opaque
            else
                apply configured
            fi
        else
            touch "$STATE_FILE"
            apply opaque
        fi
        ;;
    *)
        echo "usage: toggle-opacity.sh [toggle | apply opaque|configured]" >&2
        exit 64
        ;;
esac
