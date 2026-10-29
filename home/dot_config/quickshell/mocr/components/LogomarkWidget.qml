import QtQuick
import "../theme"

// Liquid Tron logomark — 240×240 ShaderEffect wrapper with reactivity state machine.
//
// Inputs:
//   cpuUsage: int   0–100 (aggregate, from caller's SystemStats instance)
//   gpuUsage: int   0–100 or -1 (-1 = GPU unavailable; stays idle)
//
// Layer A (phase sweep) and Layer C (noise jitter) run entirely inside the shader.
// Layer B (positional drift) is a slow Transform.Translate on this Item.
// Reactivity state machine drives u_outerState / u_innerState uniforms.

Item {
    id: widget
    width: 240
    height: 240

    property int cpuUsage: 0
    property int gpuUsage: -1   // -1 = GPU unavailable, inner ring stays idle

    // ── Clock (u_time) ────────────────────────────────────────────────────────
    property real _elapsed: 0.0

    FrameAnimation {
        running: true
        onTriggered: widget._elapsed += frameTime
    }

    // ── Layer B: positional drift ±4px, 30-min cycle, 60s ease ───────────────
    transform: Translate {
        id: driftTranslate
        x: 0.0
        y: 0.0
        Behavior on x { NumberAnimation { duration: 60000; easing.type: Easing.InOutCubic } }
        Behavior on y { NumberAnimation { duration: 60000; easing.type: Easing.InOutCubic } }
    }

    Timer {
        interval: 1800000   // 30 minutes
        repeat: true
        running: true
        onTriggered: {
            driftTranslate.x = Math.random() * 8.0 - 4.0   // ±4px
            driftTranslate.y = Math.random() * 8.0 - 4.0
        }
    }

    // ── Outer ring state machine (CPU, enter≥70%, exit<60%) ──────────────────
    // States: idle → entering → active → exiting → idle
    // Sustain: 5s (10 × 500ms) to enter, 3s (6 × 500ms) to exit.

    property real   _outerState: 0.0      // lerped 0.0→1.0 by animations
    property string _outerStage: "idle"   // idle | entering | active | exiting
    property int    _outerTicks: 0

    NumberAnimation {
        id: outerEnterAnim
        target: widget; property: "_outerState"
        to: 1.0; duration: 400           // Motion.durationTweenMax
        easing.type: Easing.Bezier; easing.bezierCurve: Motion.snap
        onStopped: if (widget._outerStage === "entering") widget._outerStage = "active"
    }

    // 1200ms exit decay — no Motion constant; raw literal per spec (AC-4 minor notes)
    NumberAnimation {
        id: outerExitAnim
        target: widget; property: "_outerState"
        to: 0.0; duration: 1200
        easing.type: Easing.Bezier; easing.bezierCurve: Motion.decay
        onStopped: if (widget._outerStage === "exiting") widget._outerStage = "idle"
    }

    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            var stage = widget._outerStage
            if (stage === "idle") {
                if (widget.cpuUsage >= 70) {
                    if (++widget._outerTicks >= 10) {    // 10 × 500ms = 5s
                        widget._outerTicks = 0
                        widget._outerStage = "entering"
                        outerEnterAnim.start()
                    }
                } else {
                    widget._outerTicks = 0
                }
            } else if (stage === "active") {
                if (widget.cpuUsage < 60) {
                    if (++widget._outerTicks >= 6) {     // 6 × 500ms = 3s
                        widget._outerTicks = 0
                        widget._outerStage = "exiting"
                        outerExitAnim.start()
                    }
                } else {
                    widget._outerTicks = 0
                }
            }
        }
    }

    // ── Inner ring state machine (GPU, enter≥60%, exit<50%) ──────────────────
    // gpuUsage == -1 → unavailable → -1 < 60, never triggers enter; stays idle.

    property real   _innerState: 0.0
    property string _innerStage: "idle"
    property int    _innerTicks: 0

    NumberAnimation {
        id: innerEnterAnim
        target: widget; property: "_innerState"
        to: 1.0; duration: 400
        easing.type: Easing.Bezier; easing.bezierCurve: Motion.snap
        onStopped: if (widget._innerStage === "entering") widget._innerStage = "active"
    }

    NumberAnimation {
        id: innerExitAnim
        target: widget; property: "_innerState"
        to: 0.0; duration: 1200
        easing.type: Easing.Bezier; easing.bezierCurve: Motion.decay
        onStopped: if (widget._innerStage === "exiting") widget._innerStage = "idle"
    }

    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            var stage = widget._innerStage
            if (stage === "idle") {
                if (widget.gpuUsage >= 60) {
                    if (++widget._innerTicks >= 10) {
                        widget._innerTicks = 0
                        widget._innerStage = "entering"
                        innerEnterAnim.start()
                    }
                } else {
                    widget._innerTicks = 0
                }
            } else if (stage === "active") {
                if (widget.gpuUsage < 50) {
                    if (++widget._innerTicks >= 6) {
                        widget._innerTicks = 0
                        widget._innerStage = "exiting"
                        innerExitAnim.start()
                    }
                } else {
                    widget._innerTicks = 0
                }
            }
        }
    }

    // ── ShaderEffect ──────────────────────────────────────────────────────────
    // fragmentShader resolves relative to this file (components/), so "../shaders/".
    // Qt6 pairs this with its built-in vertex shader that provides qt_TexCoord0.
    // Uniform names match the struct fields in the std140 buf block (minus ubuf. prefix).

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: "../shaders/logomark.frag.qsb"

        property real  u_time:            widget._elapsed
        property real  u_outerState:      widget._outerState
        property real  u_innerState:      widget._innerState
        property real  u_outerPulsePhase: 0.0
        property real  u_innerPulsePhase: 3.14159265   // π — counter-phase for dual-active
        property size  u_resolution:      Qt.size(widget.width, widget.height)
        property color u_cyan:            Colors.cyan
        property color u_amber:           Colors.amber
    }
}
