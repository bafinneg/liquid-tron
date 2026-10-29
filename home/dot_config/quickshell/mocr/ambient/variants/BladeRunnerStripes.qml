// Blade Runner Stripes — 80px vertical emission stripe on the outer
// edge of each side monitor, fading to transparent over the next 400px.
//
// Role is bound to palette monitor_scope order, not hardcoded monitor
// names (MatrixBezels predates this convention; once the name rot of
// DP-1→DP-2 surfaced, role-by-order became the repo convention for new
// variants):
//   scope[0] → CPU reactive, stripe on LEFT edge
//   scope[1] → GPU reactive, stripe on RIGHT edge
//
// Reactivity:
//   - Emission band height = current usage% × stripe height (bottom-anchored).
//   - Pulse: opacity fades 1.0 → 0.55 over 1.8s on each history push
//     (every 2s from SystemStats / GpuStats). The pulse IS the motion-
//     per-pixel budget — a steady-state 5% CPU still ticks pixels.
//   - Threshold colors: cyan base → amber > 70% → red > 90%.
//
// OLED safety:
//   - Hard: AmbientLayer Loader.active destroys the variant on fullscreen
//     pause; resume gets fresh state (same pattern as MatrixBezels).
//   - Soft: pulse opacity modulation guarantees steady-state motion-per-
//     pixel every 2s even when usage% is perfectly flat.
import QtQuick
import "../../services" as Services
import "../../theme"

Item {
    id: root

    // AmbientLayer passes modelData.name (e.g. "DP-2"). Variants resolve
    // their role from palette monitor_scope (declared in Ambient.qml).
    required property string screenName
    // SystemStats instance (per-AmbientLayer) for CPU role. GPU role
    // reads the Services.GpuStats singleton directly.
    required property var sysStats

    // ── Role resolution ─────────────────────────────────────
    readonly property int roleIndex: Ambient.monitorScope.indexOf(screenName)
    readonly property bool inScope: roleIndex === 0 || roleIndex === 1
    readonly property bool leftEdge: roleIndex === 0
    readonly property string role: roleIndex === 0 ? "cpu" : roleIndex === 1 ? "gpu" : "none"

    visible: inScope

    // ── Stripe geometry ─────────────────────────────────────
    readonly property int stripeWidth: 80
    readonly property int fadeWidth: 400

    // ── Telemetry source (by role) ──────────────────────────
    readonly property int currentValue: role === "cpu"
        ? (sysStats ? sysStats.cpuUsage : 0)
        : role === "gpu"
        ? Services.GpuStats.gpuUsage
        : 0

    // Watching the history array reference is the pulse heartbeat.
    // Both SystemStats and GpuStats replace the array on each push, so
    // this binding fires every 2s even when currentValue is unchanged.
    readonly property var historyRef: role === "cpu"
        ? (sysStats ? sysStats.cpuHistory : null)
        : role === "gpu"
        ? Services.GpuStats.gpuHistory
        : null

    onHistoryRefChanged: {
        if (inScope) pulseAnim.restart()
    }

    // ── Threshold → color ───────────────────────────────────
    readonly property color valueColor: {
        if (currentValue > 90) return Colors.red
        if (currentValue > 70) return Colors.amber
        return Colors.cyan
    }

    // ── Pulse animation ─────────────────────────────────────
    property real pulseOpacity: 0.65
    NumberAnimation {
        id: pulseAnim
        target: root
        property: "pulseOpacity"
        from: 1.0
        to: 0.55
        duration: 1800
        easing.type: Easing.OutCubic
    }

    // ── Emission band height tracks usage% ──────────────────
    // Not `readonly`: Behavior animates by writing the property between
    // binding evaluations, which Qt forbids on readonly. The binding
    // still drives the value; Behavior just smooths the transitions.
    property real bandHeight: height * (currentValue / 100.0)
    Behavior on bandHeight {
        NumberAnimation { duration: 800; easing.type: Easing.InOutCubic }
    }

    // ═══ Rendering ══════════════════════════════════════════

    // Base stripe — dim cyan, always on when in scope.
    Rectangle {
        id: baseStripe
        width: root.stripeWidth
        height: parent.height
        x: root.leftEdge ? 0 : parent.width - width
        color: Colors.cyan
        opacity: 0.25 * Ambient.maxOpacity
    }

    // Emission band — bright, height tracks current value, pulse opacity.
    Rectangle {
        id: emissionBand
        width: root.stripeWidth
        height: root.bandHeight
        x: root.leftEdge ? 0 : parent.width - width
        anchors.bottom: baseStripe.bottom
        color: root.valueColor
        opacity: root.pulseOpacity * Ambient.maxOpacity
    }

    // Fade gradient — cyan at the stripe edge, transparent 400px inward.
    // This is the "glow bleed" that softens the hard stripe boundary into
    // the workspace.
    Rectangle {
        id: fade
        width: root.fadeWidth
        height: parent.height
        x: root.leftEdge ? root.stripeWidth : parent.width - root.stripeWidth - root.fadeWidth
        opacity: 0.25 * Ambient.maxOpacity
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: root.leftEdge ? Colors.cyan : "transparent"
            }
            GradientStop {
                position: 1.0
                color: root.leftEdge ? "transparent" : Colors.cyan
            }
        }
    }
}
