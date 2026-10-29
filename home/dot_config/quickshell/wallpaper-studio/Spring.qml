import QtQuick

// Liquid Tron damped spring (FEAT-lt28). Set `to`; read `value` and `velocity`.
//
// Retargetable: a new `to` mid-flight keeps the current velocity, so a change of mind curves back instead of
// restarting from rest, which a fixed-duration NumberAnimation cannot do.
// Frame-accurate: integrates on FrameAnimation's real frame time in sub-steps of at most 4 ms, so it advances on
// every frame at 120/144/240 Hz. Qt's SpringAnimation steps in fixed 16 ms increments and skips frames above 60 Hz,
// and render-thread Animators stall GUI-thread animation when several windows are exposed; neither is used here.
//
// `response` is the undamped period in seconds (smaller = quicker). `dampingRatio` 1 settles with no overshoot;
// below 1 it overshoots slightly. This file is identical in every companion (test_motion_authority.py).
FrameAnimation {
    id: spring

    property real to: 0
    property real value: 0
    property real velocity: 0
    property real response: 0.36
    property real dampingRatio: 1.0
    // Settled when both the distance and the speed fall below this (value units: a 0..1 progress or pixels).
    property real epsilon: 0.001
    readonly property bool moving: running

    // Fires once when the spring comes to rest on `to`.
    signal settled()

    // Jump to `to` (or to `v`) with no motion: first layout, or a reset while hidden.
    function snap(v) {
        running = false
        velocity = 0
        value = (v === undefined) ? to : v
    }

    running: false
    onToChanged: running = true
    // onToChanged does not fire for a binding's initial value; land there with no motion, so a surface created
    // already open is visible at once.
    Component.onCompleted: snap()

    onTriggered: {
        // A frame after a stall is capped at 1/30 s, so a hitch costs a step, never a spring flung past its target.
        const dt = Math.min(Math.max(frameTime, 0), 1 / 30)
        const w = 2 * Math.PI / Math.max(0.01, response)
        const k = w * w
        const c = 2 * dampingRatio * w
        const n = Math.max(1, Math.ceil(dt / 0.004))
        const h = dt / n
        let x = value
        let v = velocity
        for (let i = 0; i < n; i++) {
            v += (-k * (x - to) - c * v) * h
            x += v * h
        }
        if (Math.abs(x - to) < epsilon && Math.abs(v) < epsilon * 10) {
            running = false
            velocity = 0
            value = to
            settled()
        } else {
            velocity = v
            value = x
        }
    }
}
