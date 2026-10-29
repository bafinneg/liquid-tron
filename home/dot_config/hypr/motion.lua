-- Liquid Tron motion authority (FEAT-lt28 C2).
--
-- THE ONLY FILE THAT CALLS hl.curve OR hl.animation. Every other Hyprland Lua file goes through LT_MOTION
-- (LT_MOTION.leaf / LT_MOTION.with_style). The bezier curves below are, value for value, the companions'
-- theme/Motion.qml curves; machines/7800x/tests/test_motion_authority.py fails if they drift, if any other
-- hypr Lua file calls hl.curve/hl.animation, or if docs/aesthetic-design-system.md §5 stops matching LEAVES.
-- Change a curve here and in both Motion.qml copies in the same commit, or in neither.
-- Noctalia owns its own surfaces' motion (shell.animation; the no_anim layer rule in hyprland.lua).
local M = {}

-- Cubic-bezier control points x1, y1, x2, y2.
M.CURVES = {
    linear  = { 0.00, 0.00, 1.00, 1.00 }, -- constant speed
    sweep   = { 0.22, 1.00, 0.36, 1.00 }, -- workspace slides, border sweep (deliberate)
    snap    = { 0.05, 0.90, 0.10, 1.00 }, -- fade-in, border colour (responsive)
    decay   = { 0.40, 0.00, 0.20, 1.00 }, -- fade out, window close (settling)
    inflate = { 0.25, 0.46, 0.45, 1.00 }, -- elastic resize (kept for the vocabulary; no leaf today)
}

-- FEAT-lt26r-3 C4 (15 OD3): critically damped spring S2 (k=380, c=39, mass 1, about 0.30 s) for window open/move.
-- Pre-declared fallback S1 if S2 reads abrupt at the screen: stiffness = 170, dampening = 26.
M.SPRINGS = {
    settle = { mass = 1, stiffness = 380, dampening = 39 },
}

-- leaf -> { speed, curve, style }. A curve named in SPRINGS is applied as a spring, any other as a bezier.
M.LEAVES = {
    windows          = { 2.5, "settle" },
    windowsOut       = { 2,   "decay", "popin 85%" },
    windowsMove      = { 3,   "settle" },
    fade             = { 2,   "decay" },
    fadeIn           = { 1.5, "snap" },
    workspaces       = { 3.5, "sweep", "slidevert" },
    specialWorkspace = { 3,   "sweep", "slidefadevert -50%" },
    border           = { 1,   "snap" },
    -- FEAT-lt26r-3 C4 (15 OD2): one border sweep per focus change instead of a continuous loop (render budget).
    borderangle      = { 12,  "sweep", "once" },
}

local function put(name, style)
    local l = M.LEAVES[name]
    local t = { leaf = name, enabled = true, speed = l[1] }
    if M.SPRINGS[l[2]] then t.spring = l[2] else t.bezier = l[2] end
    local s = style or l[3]
    if s then t.style = s end
    hl.animation(t)
end

-- Re-apply one leaf from the table (its own style).
function M.leaf(name) put(name) end

-- Apply one leaf with a different style for a single move (the workspace wrap flips slidevert), then call
-- M.leaf(name) to put the table's style back.
function M.with_style(name, style) put(name, style) end

-- Apply order is fixed (parents before children: windows before windowsOut, fade before fadeIn), as the
-- hand-written block it replaced did; pairs() order is unspecified.
M.CURVE_ORDER = { "linear", "sweep", "snap", "decay", "inflate" }
M.LEAF_ORDER = { "windows", "windowsOut", "windowsMove", "fade", "fadeIn", "workspaces", "specialWorkspace",
                 "border", "borderangle" }

function M.apply()
    hl.config({ animations = { enabled = true } })
    for _, name in ipairs(M.CURVE_ORDER) do
        local p = M.CURVES[name]
        hl.curve(name, { type = "bezier", points = { { p[1], p[2] }, { p[3], p[4] } } })
    end
    for name, s in pairs(M.SPRINGS) do
        hl.curve(name, { type = "spring", mass = s.mass, stiffness = s.stiffness, dampening = s.dampening })
    end
    for _, name in ipairs(M.LEAF_ORDER) do put(name) end
end

-- Hyprland's require takes a path and may not hand back a return value, so the module is also a global.
LT_MOTION = M
return M
