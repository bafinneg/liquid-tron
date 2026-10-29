-- System Map — keybind
-- Sourced from hyprland.conf. Not theme-managed (no colors here).
--
-- SUPER+Tab → Liquid Tron System Map on the center PG42UQ (FEAT-lt26r-5). The trigger owns admission,
-- repeat-trigger dismissal, and fullscreen/game/lock/power suppression.
hl.bind("SUPER + Tab", hl.dsp.exec_cmd("~/.local/bin/hypr-overview-trigger"), { description = "Overlay: System Map" })
