-- Tron Compute — Hyprland colors
-- Managed by apply-theme.sh — do not edit directly

hl.config({ general = { col = { active_border = { colors = { "rgba(0abdc6ff)", "rgba(0072ffff)", "rgba(1a1a2aff)" }, angle = 45 } } } })
hl.config({ general = { col = { inactive_border = "rgba(1a1a2aff)" } } })
-- FEAT-lt26r-5 (13): frame-state grammar from the Tron Compute palette. Groups read cyan/blue, never the upstream
-- yellow/olive; locked and deny-group states use the same tokens (no orange, INVARIANTS 1).
hl.config({ general = { col = { nogroup_border = "rgba(1a1a2aff)" } } })
hl.config({ general = { col = { nogroup_border_active = { colors = { "rgba(0abdc6ff)", "rgba(0072ffff)", "rgba(1a1a2aff)" }, angle = 45 } } } })
hl.config({ group = { col = { border_active = { colors = { "rgba(0abdc6ff)", "rgba(0072ffff)" }, angle = 45 } } } })
hl.config({ group = { col = { border_inactive = "rgba(0072ff66)" } } })
hl.config({ group = { col = { border_locked_active = { colors = { "rgba(0abdc6ff)", "rgba(0072ffff)" }, angle = 45 } } } })
hl.config({ group = { col = { border_locked_inactive = "rgba(0072ff66)" } } })
hl.config({ group = { groupbar = { col = { active = "rgba(0072ffcc)" } } } })
hl.config({ group = { groupbar = { col = { inactive = "rgba(1a1a2acc)" } } } })
hl.config({ group = { groupbar = { col = { locked_active = "rgba(0072ffcc)" } } } })
hl.config({ group = { groupbar = { col = { locked_inactive = "rgba(1a1a2acc)" } } } })
hl.config({ group = { groupbar = { text_color = "rgba(e0e0f0ff)" } } })
hl.config({ group = { groupbar = { text_color_inactive = "rgba(c0c0d0ff)" } } })
-- FEAT-lt26r-5 OD-C depth A "tight contact": neutral bg_dark shadow instead of the 52 px cyan halo.
hl.config({ decoration = { shadow = { color = "rgba(06060cb3)" } } })
hl.env("XCURSOR_THEME", "Bibata-Original-Tron")
hl.env("XCURSOR_SIZE", "24")
-- Vector hyprcursor build of the same theme (sources/bibata-tron/build-hyprcursor.py): sharp at any size.
hl.env("HYPRCURSOR_THEME", "Bibata-Original-Tron")
hl.env("HYPRCURSOR_SIZE", "24")
