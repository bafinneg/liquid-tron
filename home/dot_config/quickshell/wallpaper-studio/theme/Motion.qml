pragma Singleton
import QtQuick

QtObject {
    // From design doc §5 motion vocabulary.
    // QML easing.bezierCurve = [cx1, cy1, cx2, cy2, 1, 1] for single-segment.

    readonly property var linear:  [0.00, 0.00, 1.00, 1.00, 1, 1]
    readonly property var sweep:   [0.22, 1.00, 0.36, 1.00, 1, 1]
    readonly property var snap:    [0.05, 0.90, 0.10, 1.00, 1, 1]
    readonly property var decay:   [0.40, 0.00, 0.20, 1.00, 1, 1]
    readonly property var inflate: [0.25, 0.46, 0.45, 1.00, 1, 1]

    // Standard durations from the discovery doc constraints:
    readonly property int durationTween:     200  // value tweens (number changes)
    readonly property int durationTweenMax:  400  // ceiling for any tween
    readonly property int durationPopoverReveal: 300  // vertical transient reveal
    readonly property int durationWorkspace: 350  // workspace switch slide
    readonly property int durationPopover:   200  // popover fade-in
    readonly property int durationActionFeedbackHold: 900
    readonly property int durationSystemMapEntry: 220
    readonly property int durationSystemMapExit: 140
    readonly property int durationSystemMapTraverse: 160

    // FEAT-lt28 springs (Spring.qml): `response` is the undamped period in seconds; damping 1.0 = no overshoot.
    // One spring per surface; every channel (scrim, opacity, scale, height) is derived from its 0..1 progress.
    readonly property real springDamping: 1.0
    readonly property real springSceneOpen: 0.40     // System Map open
    readonly property real springSceneClose: 0.28    // System Map close: leaving never makes you wait
    readonly property real springGlide: 0.26         // System Map selection cursor
    readonly property real springPopoverReveal: 0.46 // compact wallpaper popover bleeding down from the bar
    readonly property real springCard: 0.36          // Wallpaper Studio card
    // Entrance cascade (compact popover tiles): each tile rises and fades in, one step after the previous one.
    readonly property int cascadeStep: 18
    readonly property int cascadeRise: 180
    readonly property int cascadeMaxSteps: 15
    readonly property int cascadeDistance: 14
    readonly property int cascadeLateJoin: 600  // a tile created this soon after an open still joins the cascade
}
