import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "theme"

// Unlock splash — snappy variant of the boot splash.
// Triggered by hypr-lock-drift.sh writing to the trigger file after unlock.
// ~2s total: instant text + brackets expand + fast fade-out.

PanelWindow {
    id: unlock
    property var modelData

    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mocr-unlock"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    color: "transparent"
    visible: false

    // ── Trigger ──────────────────────────────────────────────────────────
    // Shared across all screen instances via the singleton-like first instance.
    // Each instance watches the same file; all fire together.
    property bool active: false

    FileView {
        id: triggerFile
        path: "/tmp/mocr-unlock-trigger"
        preload: true
        printErrors: false
    }

    property bool initialized: false
    property string lastTrigger: ""
    property string currentTrigger: triggerFile.text()

    onCurrentTriggerChanged: {
        if (!initialized) {
            // Snapshot whatever value exists at startup — don't animate on it
            lastTrigger = currentTrigger
            initialized = true
            return
        }
        if (currentTrigger !== "" && currentTrigger !== lastTrigger) {
            lastTrigger = currentTrigger
            unlock._startAnimation()
        }
    }

    function _startAnimation() {
        // Reset state
        dismissed = false
        cornerProgress = 0
        titleOpacity = 0
        subtitleOpacity = 0
        ruleSpread = 0
        visible = true
        active = true

        // Kick off the sequence
        appearAnim.start()
        ruleAnim.start()
        cornerAnim.start()
        dismissTimer.start()
    }

    // ── Timing — fast: 1.5s hold + 0.5s fade = 2s ───────────────────────
    property bool dismissed: false

    Timer {
        id: dismissTimer
        interval: 1500
        onTriggered: unlock.dismissed = true
    }

    // ── Animated properties ──────────────────────────────────────────────
    property real titleOpacity: 0
    property real subtitleOpacity: 0
    property real ruleSpread: 0
    property real cornerProgress: 0

    NumberAnimation {
        id: appearAnim
        target: unlock; property: "titleOpacity"
        from: 0; to: 1; duration: 300
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: ruleAnim
        target: unlock; property: "ruleSpread"
        from: 0; to: 1; duration: 400
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: cornerAnim
        target: unlock; property: "cornerProgress"
        from: 0; to: 1; duration: 800
        easing.type: Easing.OutCubic
    }

    // ── Root container ───────────────────────────────────────────────────
    Rectangle {
        id: root
        anchors.fill: parent
        color: "#000000"

        opacity: unlock.dismissed ? 0.0 : 1.0
        Behavior on opacity {
            NumberAnimation {
                duration: 500
                easing.type: Easing.InQuad
            }
        }

        onOpacityChanged: {
            if (opacity === 0.0) {
                unlock.visible = false
                unlock.active = false
            }
        }

        // ── Scan lines (reused from boot splash) ────────────────────────
        Canvas {
            anchors.fill: parent
            z: 10
            opacity: 0.06

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = Colors.cyan.toString()
                ctx.lineWidth = 1
                for (var y = 0; y < height; y += 4) {
                    ctx.beginPath()
                    ctx.moveTo(0, y)
                    ctx.lineTo(width, y)
                    ctx.stroke()
                }
            }

            Component.onCompleted: requestPaint()
        }

        // ── Center content ───────────────────────────────────────────────
        Item {
            id: centerContent
            anchors.centerIn: parent
            width: contentCol.width
            height: contentCol.height

            Column {
                id: contentCol
                spacing: 16

                // ── Top rule ─────────────────────────────────────────────
                Rectangle {
                    id: topRule
                    width: 520
                    height: 1
                    color: Colors.cyan
                    anchors.horizontalCenter: parent.horizontalCenter

                    transform: Scale {
                        origin.x: topRule.width / 2
                        xScale: unlock.ruleSpread
                    }
                }

                // ── Title — instant reveal (no typewriter) ───────────────
                Text {
                    id: titleText
                    text: "SYSTEM UNLOCKED"
                    font.family: Geometry.fontFamily
                    font.pixelSize: 48
                    font.weight: Font.Medium
                    font.letterSpacing: 16
                    color: Colors.cyan
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: unlock.titleOpacity
                }

                // ── Subtitle ─────────────────────────────────────────────
                Text {
                    text: "RESUMING SESSION"
                    font.family: Geometry.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.Normal
                    font.letterSpacing: 8
                    color: Colors.amber
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: unlock.titleOpacity * 0.8
                }

                // ── Bottom rule ──────────────────────────────────────────
                Rectangle {
                    id: bottomRule
                    width: 520
                    height: 1
                    color: Colors.cyan
                    anchors.horizontalCenter: parent.horizontalCenter

                    transform: Scale {
                        origin.x: bottomRule.width / 2
                        xScale: unlock.ruleSpread
                    }
                }
            }

            // ── Center glow ──────────────────────────────────────────────
            Rectangle {
                anchors.centerIn: parent
                width: 400
                height: 160
                z: -1
                radius: 200
                color: Colors.cyan
                opacity: unlock.titleOpacity * 0.06
            }
        }

        // ── Corner brackets — expand from center ─────────────────────────
        Repeater {
            model: [
                { signX: -1, signY: -1 },
                { signX:  1, signY: -1 },
                { signX: -1, signY:  1 },
                { signX:  1, signY:  1 }
            ]

            Item {
                required property var modelData
                property real bracketSize: 40

                property real startX: centerContent.x + (modelData.signX > 0 ? centerContent.width : 0)
                                      - (modelData.signX > 0 ? bracketSize : 0)
                property real startY: centerContent.y + (modelData.signY > 0 ? centerContent.height : 0)
                                      - (modelData.signY > 0 ? bracketSize : 0)

                property real endX: root.width / 2 + modelData.signX * (root.width * 0.35)
                                    - (modelData.signX > 0 ? bracketSize : 0)
                property real endY: root.height / 2 + modelData.signY * (root.height * 0.30)
                                    - (modelData.signY > 0 ? bracketSize : 0)

                x: startX + (endX - startX) * unlock.cornerProgress
                y: startY + (endY - startY) * unlock.cornerProgress
                width: bracketSize; height: bracketSize
                opacity: unlock.cornerProgress * 0.5

                Rectangle {
                    width: parent.bracketSize; height: 1
                    y: modelData.signY > 0 ? parent.bracketSize - 1 : 0
                    color: Colors.cyan
                }
                Rectangle {
                    width: 1; height: parent.bracketSize
                    x: modelData.signX > 0 ? parent.bracketSize - 1 : 0
                    color: Colors.cyan
                }
            }
        }
    }
}
