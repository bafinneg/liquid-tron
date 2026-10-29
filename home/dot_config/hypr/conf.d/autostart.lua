-- Autostart — FEAT-workspace-split-monitor.
--
-- Apps launch without workspace placement. The previous named-workspace model
-- previously forced Zen-AI, Discord, and kitty-system into hidden workspaces;
-- the split-monitor model leaves placement to Brian.
--
-- `exec-once` only fires on Hyprland start (not on `hyprctl reload`), so adding
-- or editing lines here does not duplicate already-running processes.

hl.on("hyprland.start", function()
    -- LT26-01 (ED10, rule 5): each command now gets an initial-workspace token (Delta T1, §4); order kept as written.
    -- vesktop is the daily Discord client (native Wayland, Liquid Tron quickCss
    -- in dotfiles/vesktop). Stock discord package stays installed as fallback.
    hl.exec_cmd("vesktop")
    hl.exec_cmd("kitty --class=kitty-system --session=~/.config/kitty/system.conf")
    -- Dashboard deck — wtfutil in a kitty session parked on special:deck.
    hl.exec_cmd("kitty --class=kitty-deck -o font_size=22 --session=~/.config/kitty/deck.conf")

    -- Clipboard history — cliphist watchers (FEAT-liquid-tron-desktop-polish-2 C2).
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Session restore — must be last so quickshell and exec-once apps above are
    -- already dispatched before restore runs. FEAT-session-restore.
    hl.exec_cmd("~/.config/hypr/scripts/session-restore.sh")
end)
