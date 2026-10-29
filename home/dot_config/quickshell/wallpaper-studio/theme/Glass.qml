// FEAT-lt27 adaptive glass for bar dropdowns drawn by Liquid Tron companions. Same rule and values as Noctalia's
// attached panels (lt3 src/shell/panel/glass_detail.cpp; machines/7800x/tests/test_companion_glass.py keeps them equal):
// clear over bare wallpaper, frosted over a window, by how much of the dropdown windows cover when it opens.
pragma Singleton
import QtQuick

QtObject {
    readonly property real clearPanel: 0.62
    readonly property real frostedPanel: 0.74
    readonly property real clearCard: 0.08
    readonly property real frostedCard: 0.18
    readonly property real coverageClear: 0.02
    readonly property real coverageFrosted: 0.20

    // One read of Hyprland state when a dropdown opens: {"m": monitors, "c": clients}.
    readonly property var sampleCommand: ["sh", "-c",
        "printf '{\"m\":'; hyprctl -j monitors; printf ',\"c\":'; hyprctl -j clients; printf '}'"]

    function ramp(coverage) {
        return Math.max(0, Math.min(1, (coverage - coverageClear) / (coverageFrosted - coverageClear)))
    }
    function panelFor(coverage) { return clearPanel + ramp(coverage) * (frostedPanel - clearPanel) }
    function cardFor(coverage) { return clearCard + ramp(coverage) * (frostedCard - clearCard) }

    // Fraction of the panel rect covered by the union of rects, on a 32x32 grid of cell centres.
    function coverage(rects, px, py, pw, ph) {
        if (pw <= 0 || ph <= 0 || rects.length === 0) return 0
        var grid = 32, covered = 0
        for (var gy = 0; gy < grid; gy++) {
            var y = py + (gy + 0.5) * ph / grid
            for (var gx = 0; gx < grid; gx++) {
                var x = px + (gx + 0.5) * pw / grid
                for (var i = 0; i < rects.length; i++) {
                    var r = rects[i]
                    if (x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h) { covered++; break }
                }
            }
        }
        return covered / (grid * grid)
    }

    // Coverage of a global-coordinate panel rect by windows on the monitor's visible workspaces (active plus an open
    // special workspace). Returns -1 when the sample cannot be read, so callers keep their current opacity.
    function coverageFromSample(text, monitorName, px, py, pw, ph) {
        var d
        try { d = JSON.parse(text) } catch (e) { return -1 }
        if (!d || !d.m || !d.c) return -1
        var mon = null
        for (var i = 0; i < d.m.length; i++) if (d.m[i].name === monitorName) mon = d.m[i]
        if (!mon || !mon.activeWorkspace) return -1
        var visible = {}
        visible[mon.activeWorkspace.id] = true
        if (mon.specialWorkspace && mon.specialWorkspace.id) visible[mon.specialWorkspace.id] = true
        var rects = []
        for (var j = 0; j < d.c.length; j++) {
            var c = d.c[j]
            if (!c.workspace || !visible[c.workspace.id] || c.hidden || c.mapped === false) continue
            if (!c.at || !c.size || c.size[0] <= 0 || c.size[1] <= 0) continue
            rects.push({ x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] })
        }
        return coverage(rects, px, py, pw, ph)
    }
}
