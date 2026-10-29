-- Window rules — FEAT-workspace-split-monitor.
--
-- The retired named-workspace model routed applications to numbered homes here.
-- The split-monitor workspace model intentionally clears app/workspace affinity:
-- applications launch wherever Brian opens or moves them.
--
-- Keep this file as the future extension point for non-workspace window rules.
-- Dashboard deck: wtfutil kitty lives on the deck special workspace,
-- summoned with SUPER+U. Silent so boot never steals focus.
hl.window_rule({ match = { class = "^(kitty-deck)$" }, workspace = "special:deck silent" })
-- kitty-deck opacity: hyprland.lua opacity-authority block (FEAT-lt26r-3 OD-D).

-- Diablo IV under Wine/XWayland can mis-render when Hyprland stretches it to a
-- 4K fullscreen surface. Keep it in a real 16:9 floating window; the game can
-- then render its 1920x1080 swapchain without the one-quadrant black-screen bug.
hl.window_rule({
    name = "diablo-iv-floating-16x9",
    match = { class = "^diablo iv\\.exe$" },

    float = true,
    size = "1920 1080",
})

-- Repo Grid pop-out (FEAT-lt36 round 4, HQ-0098): Noctalia lt14 plugin window panels (app id dev.noctalia.PanelWindow)
-- float at their declared size, so Brian can drag them anywhere or onto another monitor instead of tiling.
hl.window_rule({
    name = "noctalia-panel-window-float",
    match = { class = "^dev\\.noctalia\\.PanelWindow$" },

    float = true,
    size = "1680 1180",
    center = true,
})
