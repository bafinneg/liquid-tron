#!/bin/bash
# wallpaper-rotate.sh — OLED-safe wallpaper rotation wrapper.
#
# Called by wallpaper-rotate.service every 30 minutes. Guards against
# waypaper's fallback behavior: when `waypaper --folder X --random` finds
# zero images in X, it silently reverts to the folder baked into
# ~/.config/waypaper/config.ini and randomizes from there — which on this
# box is the full ~/Pictures/Wallpapers set (not OLED-safe).
#
# This wrapper refuses to invoke waypaper unless the curated folder has
# at least one image. On empty-folder the service exits 0 cleanly so the
# timer keeps scheduling future fires.
set -euo pipefail

folder="${WALLPAPER_ROTATE_FOLDER:-$HOME/Pictures/Wallpapers/tron-compute-oled-safe}"

if [[ ! -d "$folder" ]]; then
    echo "wallpaper-rotate: folder missing: $folder" >&2
    exit 1
fi

# Count image files at the top level. Match waypaper's supported formats.
count=$(find "$folder" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) \
    | wc -l)

if (( count == 0 )); then
    echo "wallpaper-rotate: $folder is empty — skipping rotation (curate wallpapers to activate)"
    exit 0
fi

exec /usr/bin/waypaper --random --folder "$folder"
