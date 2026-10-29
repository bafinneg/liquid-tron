// Matrix Bezels — vertical NetIO-hex rain on the outer 30% of the two
// palette-selected side monitors. Roles follow Ambient.monitorScope order:
// scope[0] renders at the left edge, scope[1] at the right edge; every
// other monitor (including the center) renders nothing.
//
// Reactivity: SystemStats.netDown + netUp drives column density and fall
// speed. Idle network = sparse + slow; transferring = dense + fast.
//
// Frame rate: activeFps when network intensity changed within the last
// 5s, idleFps otherwise. Active/idle threshold lives in this file
// (Chunk 2 only has NetIO; future chunks add CPU/GPU and the gate moves
// to a shared controller).
//
// OLED watchdog: each column tracks its head pixel position; if the
// position has not changed by ≥1px in 3s, the column is fully reset
// (random seed, fresh NetIO glyphs). Pause-on-fullscreen is handled by the
// AmbientLayer Loader (Loader.active: false → MatrixBezels destroyed
// entirely → fresh state on resume), so this file does not implement a
// `paused` property.
//
// Bleed: per-column opacity ramps from 0 to 1 over 80px starting from
// the inner edge of the rain region so the rain never visually crowds
// the workspace.
import QtQuick
import "../../theme"

Item {
    id: root

    // Screen this variant is bound to. AmbientLayer passes this from
    // ambient.modelData.name. Roles resolve from Ambient.monitorScope
    // order, so connector-name changes do not alter edge ownership.
    required property string screenName
    // SystemStats instance from AmbientLayer (per-monitor). Provides
    // netDown / netUp in bytes/sec.
    required property var sysStats

    readonly property int roleIndex: Ambient.monitorScope.indexOf(screenName)
    readonly property bool inScope: roleIndex === 0 || roleIndex === 1
    readonly property bool leftEdge: roleIndex === 0
    visible: inScope

    // ── Region geometry ─────────────────────────────────────
    readonly property real rainFraction: 0.30
    readonly property int columnWidth: 14
    readonly property int glyphHeight: 18
    readonly property int trailLength: 20
    readonly property int bleedPx: 80

    readonly property int rainWidth: Math.floor(width * rainFraction)
    readonly property int rainX: leftEdge ? 0 : width - rainWidth
    // Inner edge = the edge of the rain region facing the workspace.
    readonly property int innerEdgeX: leftEdge ? rainWidth : width - rainWidth
    readonly property int columnCount: rainWidth > 0 ? Math.floor(rainWidth / columnWidth) : 0

    // ── NetIO reactivity and glyph source ───────────────────
    readonly property real netDown: sysStats ? Math.max(0, sysStats.netDown || 0) : 0
    readonly property real netUp: sysStats ? Math.max(0, sysStats.netUp || 0) : 0
    readonly property bool hasNetData: netDown > 0 || netUp > 0
    // Hex encodes the current byte/sec rates. D/U delimiters preserve
    // direction in the one-cell glyph stream without adding a new surface.
    readonly property string netHex: {
        if (!hasNetData) return ""
        var down = Math.floor(netDown).toString(16).toUpperCase().slice(-6)
        var up = Math.floor(netUp).toString(16).toUpperCase().slice(-6)
        return down + "D" + up + "U"
    }

    function glyphFor(columnIndex: int, glyphIndex: int): string {
        if (!netHex.length) return randomGlyph()
        // JavaScript remainder preserves a negative sign; shimmer can pass
        // a negative head-derived glyphIndex before a column enters view.
        var phase = (columnIndex + glyphIndex) % netHex.length
        return netHex.charAt((phase + netHex.length) % netHex.length)
    }

    // 10 MB/s combined throughput = full intensity. Cap at 1.0.
    readonly property real netIntensity: {
        var total = netDown + netUp
        var max = 10 * 1024 * 1024
        var v = total / max
        return v > 1.0 ? 1.0 : v
    }
    // Density: 30% of columns active when idle, scaling to all 30 when busy.
    readonly property real density: 0.30 + 0.70 * netIntensity
    // Speed multiplier: 1.0 idle, 2.5 max.
    readonly property real speedMul: 1.0 + 1.5 * netIntensity

    // ── FPS gate (active vs idle) ───────────────────────────
    // Active when intensity has changed by >0.05 within the last 5s.
    // isActive is a regular property updated by the Timer below — a
    // binding on `Date.now() - _lastChangeMs < 5000` would NOT re-eval
    // on its own (Date.now() is a function call, not a tracked
    // dependency), so isActive would latch true after the first burst.
    property real _lastIntensity: 0
    property real _lastChangeMs: 0
    property bool isActive: false

    Timer {
        interval: 500
        running: root.inScope
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = Date.now()
            if (Math.abs(root.netIntensity - root._lastIntensity) > 0.05) {
                root._lastIntensity = root.netIntensity
                root._lastChangeMs = now
            }
            root.isActive = (now - root._lastChangeMs) < 5000
        }
    }

    readonly property int targetFps: isActive ? Ambient.activeFps : Ambient.idleFps
    readonly property int tickInterval: Math.max(16, Math.round(1000 / targetFps))

    // ── No-data fallback alphabet ────────────────────────────
    // Halfwidth katakana (U+FF66..FF9D) + digits preserve motion if the
    // telemetry source has not produced a non-zero sample yet.
    readonly property string fallbackGlyphs:
        "ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789"

    function randomGlyph(): string {
        return fallbackGlyphs.charAt(Math.floor(Math.random() * fallbackGlyphs.length))
    }

    // ── Master tick: advance heads, swap shimmer glyphs, watchdog ──
    Timer {
        interval: root.tickInterval
        running: root.inScope
        repeat: true
        onTriggered: {
            var now = Date.now()
            for (var i = 0; i < columnRepeater.count; i++) {
                var col = columnRepeater.itemAt(i)
                if (col) col.advance(now)
            }
        }
    }

    // ── Rain columns ────────────────────────────────────────
    Repeater {
        id: columnRepeater
        model: root.columnCount

        Item {
            id: col
            required property int index

            x: root.rainX + index * root.columnWidth
            y: 0
            width: root.columnWidth
            height: root.height

            // Per-column random seeds (regenerated on full reset).
            property real seedSpeed: 0.5 + Math.random() * 1.5
            property real seedThreshold: Math.random()
            property real headPx: -Math.random() * root.height * 0.5
            property real lastTrackedPx: headPx
            property real lastMoveMs: Date.now()
            property var glyphBuffer: []

            // Visibility scales with density: a column shows iff its
            // seed sits below the current density curve.
            readonly property bool densityVisible: seedThreshold < root.density
            visible: densityVisible

            // Bleed multiplier: 0 at the inner edge, 1 once `bleedPx`
            // away from the inner edge. Outer columns get full opacity.
            readonly property real bleedMul: {
                var centerX = x + root.columnWidth / 2
                var distFromInner = root.leftEdge
                    ? (root.innerEdgeX - centerX)
                    : (centerX - root.innerEdgeX)
                if (distFromInner <= 0) return 0
                if (distFromInner >= root.bleedPx) return 1
                return distFromInner / root.bleedPx
            }

            opacity: bleedMul * Ambient.maxOpacity

            function regenerateGlyphs() {
                var g = []
                for (var i = 0; i < root.trailLength; i++) {
                    g.push(root.glyphFor(index, i))
                }
                glyphBuffer = g
            }

            function fullReset() {
                seedSpeed = 0.5 + Math.random() * 1.5
                seedThreshold = Math.random()
                headPx = -Math.random() * root.height * 0.5
                lastTrackedPx = headPx
                lastMoveMs = Date.now()
                regenerateGlyphs()
            }

            function advance(now: real): void {
                var dt = root.tickInterval / 1000.0
                // Base fall speed: 120 px/sec (≈6.5 cells/sec at 18px),
                // multiplied by per-column seed and global netIntensity.
                var step = dt * 120 * seedSpeed * root.speedMul
                headPx += step

                if (Math.abs(headPx - lastTrackedPx) >= 1) {
                    lastTrackedPx = headPx
                    lastMoveMs = now
                } else if (now - lastMoveMs > 3000) {
                    // OLED watchdog: stalled column → reset everything.
                    fullReset()
                    return
                }

                if (headPx > root.height + root.glyphHeight) {
                    fullReset()
                    return
                }

                // Shimmer: each tick swap one random glyph in ~10% of columns.
                if (Math.random() < 0.10) {
                    var idx = Math.floor(Math.random() * glyphBuffer.length)
                    var newBuf = glyphBuffer.slice()
                    newBuf[idx] = root.glyphFor(index, idx + Math.floor(headPx / root.glyphHeight))
                    glyphBuffer = newBuf
                }
            }

            Component.onCompleted: regenerateGlyphs()

            // Wrapper Item slides as a single transform per tick;
            // children are positioned at constant relative y so only the
            // wrapper's y binding re-evaluates on advance().
            Item {
                id: trail
                x: 0
                y: col.headPx
                width: parent.width

                Repeater {
                    model: root.trailLength

                    Text {
                        required property int index
                        text: col.glyphBuffer[index] || ""
                        // index 0 = head (bright), increasing index = trail (dimmer).
                        y: -index * root.glyphHeight
                        x: 0
                        width: root.columnWidth
                        horizontalAlignment: Text.AlignHCenter
                        color: index === 0 ? Colors.white : Colors.cyan
                        opacity: {
                            if (index === 0) return 1.0
                            // Linear fade from 0.95 at index 1 to 0 at trailLength.
                            var t = index / root.trailLength
                            return Math.max(0, 0.95 - 0.95 * t)
                        }
                        font.family: Geometry.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
