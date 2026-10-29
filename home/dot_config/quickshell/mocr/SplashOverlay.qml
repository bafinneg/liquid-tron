import Quickshell
import Quickshell.Wayland
import QtQuick
import "theme"

// Boot splash — fullscreen overlay per monitor.
// Covers the desktop with a Tron-themed animation while mpvpaper and other
// services load, then fades out and hides.

PanelWindow {
    id: splash
    property var modelData
    readonly property bool animated: modelData && modelData.name === "DP-3"

    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mocr-splash"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: -1
    color: "transparent"

    // ── Timing ───────────────────────────────────────────────────────────
    // Total visible time: ~4s (hold) + 0.8s (fade) = ~4.8s
    property bool dismissed: false

    Timer {
        id: holdTimer
        interval: 4000
        running: true
        onTriggered: splash.dismissed = true
    }

    // ── Root container — handles the fade-out ────────────────────────────
    Rectangle {
        id: root
        anchors.fill: parent
        color: "#000000"

        opacity: splash.dismissed ? 0.0 : 1.0
        Behavior on opacity {
            NumberAnimation {
                duration: 800
                easing.type: Easing.InQuad
            }
        }

        onOpacityChanged: {
            if (opacity === 0.0)
                splash.visible = false
        }

        // ── Scan line overlay ────────────────────────────────────────────
        Canvas {
            id: scanLines
            visible: splash.animated
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

            Component.onCompleted: {
                if (splash.animated)
                    requestPaint()
            }
        }

        // ── Center content ───────────────────────────────────────────────
        Item {
            id: centerContent
            visible: splash.animated
            anchors.centerIn: parent
            width: contentCol.width
            height: contentCol.height

            Column {
                id: contentCol
                spacing: 16

                // ── Top horizontal rule ──────────────────────────────────
                Rectangle {
                    id: topRule
                    width: titleMeasure.width
                    height: 1
                    color: Colors.cyan
                    anchors.horizontalCenter: parent.horizontalCenter

                    property real spread: 0
                    transform: Scale {
                        origin.x: topRule.width / 2
                        xScale: topRule.spread
                    }

                    NumberAnimation on spread {
                        running: splash.animated
                        from: 0; to: 1
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }

                // ── Main title — typewriter reveal ───────────────────────
                Item {
                    id: titleContainer
                    width: titleMeasure.width
                    height: titleMeasure.height
                    anchors.horizontalCenter: parent.horizontalCenter

                    property int revealedChars: 0
                    property bool fullyRevealed: revealedChars >= 13

                    // Hidden text to measure full width
                    Text {
                        id: titleMeasure
                        text: "SYSTEM ONLINE"
                        font.family: Geometry.fontFamily
                        font.pixelSize: 48
                        font.weight: Font.Medium
                        font.letterSpacing: 16
                        visible: false
                    }

                    // Visible text — only shows revealed characters
                    Text {
                        id: titleText
                        text: "SYSTEM ONLINE".substring(0, titleContainer.revealedChars)
                        font.family: Geometry.fontFamily
                        font.pixelSize: 48
                        font.weight: Font.Medium
                        font.letterSpacing: 16
                        color: Colors.cyan
                    }

                    // Blinking cursor
                    Rectangle {
                        id: cursor
                        x: titleText.contentWidth + 2
                        width: 2
                        height: titleText.font.pixelSize
                        anchors.verticalCenter: parent.verticalCenter
                        color: Colors.cyan
                        visible: !titleContainer.fullyRevealed

                        SequentialAnimation on opacity {
                            running: splash.animated && cursor.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 400 }
                            NumberAnimation { to: 1; duration: 400 }
                        }
                    }

                    Timer {
                        interval: 80
                        running: splash.animated
                        repeat: true
                        onTriggered: {
                            if (titleContainer.revealedChars < 13)
                                titleContainer.revealedChars++
                            else
                                stop()
                        }
                    }
                }

                // ── Subtitle — fades in then pulses ─────────────────────
                Text {
                    id: subtitleText
                    text: "INITIALIZING SUBSYSTEMS"
                    font.family: Geometry.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.Normal
                    font.letterSpacing: 8
                    color: Colors.amber
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: 0.0

                    // Fade in, then hand off to pulse loop
                    SequentialAnimation on opacity {
                        running: splash.animated && titleContainer.fullyRevealed
                        NumberAnimation { to: 1.0; duration: 400 }
                        SequentialAnimation {
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                        }
                    }
                }

                // ── Bottom horizontal rule ───────────────────────────────
                Rectangle {
                    id: bottomRule
                    width: titleMeasure.width
                    height: 1
                    color: Colors.cyan
                    anchors.horizontalCenter: parent.horizontalCenter

                    property real spread: 0
                    transform: Scale {
                        origin.x: bottomRule.width / 2
                        xScale: bottomRule.spread
                    }

                    NumberAnimation on spread {
                        running: splash.animated
                        from: 0; to: 1
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // ── Center glow — soft halo behind text ──────────────────────
            Rectangle {
                anchors.centerIn: parent
                width: titleMeasure.width + 80
                height: contentCol.height + 40
                z: -1
                radius: 200
                color: Colors.cyan
                opacity: titleContainer.fullyRevealed ? 0.06 : 0.0

                Behavior on opacity {
                    NumberAnimation { duration: 800 }
                }
            }
        }

        // ── Corner accents — animate outward from center content box ─────
        // Each bracket starts at its nearest corner of the center content
        // and travels to its final position on screen, like the system is
        // "opening up" from the title.
        property real cornerProgress: 0.0
        readonly property real cornerInset: 6.0
        NumberAnimation on cornerProgress {
            from: 0; to: 1
            duration: 1200
            easing.type: Easing.OutCubic
            running: splash.animated && titleContainer.fullyRevealed
        }

        Repeater {
            model: splash.animated ? [
                // signX/signY: which corner (-1 = left/top, +1 = right/bottom)
                { signX: -1, signY: -1 },
                { signX:  1, signY: -1 },
                { signX: -1, signY:  1 },
                { signX:  1, signY:  1 }
            ] : []

            Item {
                required property var modelData
                property real bracketSize: 40

                // Start position: corners of centerContent box
                property real startX: centerContent.x + (modelData.signX > 0 ? centerContent.width : 0)
                                      - (modelData.signX > 0 ? bracketSize : 0)
                property real startY: centerContent.y + (modelData.signY > 0 ? centerContent.height : 0)
                                      - (modelData.signY > 0 ? bracketSize : 0)

                // End position: slightly inset from physical edges to avoid clipping.
                property real endX: modelData.signX > 0 ? root.width - bracketSize - root.cornerInset : root.cornerInset
                property real endY: modelData.signY > 0 ? root.height - bracketSize - root.cornerInset : root.cornerInset

                x: startX + (endX - startX) * root.cornerProgress
                y: startY + (endY - startY) * root.cornerProgress
                width: bracketSize; height: bracketSize
                opacity: root.cornerProgress * 0.5

                // Horizontal stroke
                Rectangle {
                    width: parent.bracketSize; height: 1
                    y: modelData.signY > 0 ? parent.bracketSize - 1 : 0
                    color: Colors.cyan
                }
                // Vertical stroke
                Rectangle {
                    width: 1; height: parent.bracketSize
                    x: modelData.signX > 0 ? parent.bracketSize - 1 : 0
                    color: Colors.cyan
                }
            }
        }
    }
}
