#!/usr/bin/env bash
# Toggle wvkbd-mobintl (on-screen keyboard, wlroots).
# Bound to Super+I. Safe to invoke when wvkbd is not installed —
# `command -v` guard avoids a confusing layer-shell pop on missing binary.
set -euo pipefail

if ! command -v wvkbd-mobintl >/dev/null; then
  notify-send "Virtual keyboard" "wvkbd-mobintl not installed (yay -S wvkbd-git)" || true
  exit 1
fi

if pgrep -x wvkbd-mobintl >/dev/null; then
  pkill -x wvkbd-mobintl
else
  setsid -f wvkbd-mobintl -L 360 >/dev/null 2>&1
fi
