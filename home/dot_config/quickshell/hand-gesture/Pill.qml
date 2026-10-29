import QtQuick

// The pill itself. `st` is the parsed state.json (or null).
Item {
    id: pill
    property var st: null

    readonly property string mode: st ? st.state : "idle"
    readonly property color accent: mode === "armed" || mode === "cooldown" ? "#00e5ff"
        : mode === "arming" ? "#ffb000" : "#5a5a5a"
    property string flashDir: ""
    // phase 2: "drag" / "resize" / "fullscreen" while a window gesture is active (state.json "mode")
    readonly property string gmode: (st && st.mode) ? st.mode : ""
    readonly property string gmodeLabel: gmode === "drag" ? "DRAG" : gmode === "resize" ? "RESIZE"
        : gmode === "fullscreen" ? "FULLSCREEN" : ""
    readonly property color modeColor: gmode === "resize" ? "#ff4fd8" : gmode === "fullscreen" ? "#7dff5c" : "#00e5ff"

    Connections {
        target: pill
        function onStChanged() {
            if (pill.st && pill.st.last_ms > 0 && pill.st.last_ms !== pill.lastSeen && pill.st.last) {
                pill.lastSeen = pill.st.last_ms
                if (pill.initialised) { pill.flashDir = pill.st.last; flashTimer.restart() }
            }
            if (pill.st) pill.initialised = true
        }
    }
    property real lastSeen: 0
    property bool initialised: false
    Timer { id: flashTimer; interval: 400; onTriggered: pill.flashDir = "" }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "#000000"
        border.width: 2
        border.color: pill.accent
    }

    // progress arc (arming amber / fist disarm)
    Canvas {
        id: arc
        width: 64; height: 64
        anchors.left: parent.left
        anchors.leftMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        property real p: pill.st ? pill.st.progress : 0
        property color c: pill.gmodeLabel !== "" ? pill.modeColor : pill.accent
        onPChanged: requestPaint()
        onCChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.lineWidth = 5
            ctx.strokeStyle = "#222222"
            ctx.beginPath(); ctx.arc(32, 32, 26, 0, Math.PI * 2); ctx.stroke()
            if (p > 0) {
                ctx.strokeStyle = c
                ctx.beginPath()
                ctx.arc(32, 32, 26, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p); ctx.stroke()
            }
        }
        // hand dot inside the ring, showing x/y
        Rectangle {
            visible: pill.st !== null && pill.st.hand
            width: 10; height: 10; radius: 5
            color: pill.accent
            x: 32 - 5 + ((pill.st ? pill.st.x : 0.5) - 0.5) * 36
            y: 32 - 5 + ((pill.st ? pill.st.y : 0.5) - 0.5) * 36
        }
        // second hand dot (two hands seen)
        Rectangle {
            visible: pill.st !== null && pill.st.hand && pill.st.hands >= 2 && pill.st.x2 !== null && pill.st.x2 !== undefined
            width: 8; height: 8; radius: 4
            color: "#ff4fd8"
            x: 32 - 4 + ((pill.st && pill.st.x2 !== null && pill.st.x2 !== undefined ? pill.st.x2 : 0.5) - 0.5) * 36
            y: 32 - 4 + ((pill.st && pill.st.y2 !== null && pill.st.y2 !== undefined ? pill.st.y2 : 0.5) - 0.5) * 36
        }
    }

    Text {
        anchors.centerIn: parent
        text: pill.gmodeLabel !== "" ? pill.gmodeLabel : pill.mode === "armed" ? "ARMED" : pill.mode === "arming" ? "HOLD PALM"
            : pill.mode === "cooldown" ? "" : pill.mode === "paused" ? "PAUSED (LOCK)"
            : pill.mode === "nocam" ? "NO CAMERA" : "IDLE"
        color: pill.gmodeLabel !== "" ? pill.modeColor : pill.accent
        font.pixelSize: pill.gmodeLabel.length > 7 ? 18 : 22
        font.family: "monospace"
        font.letterSpacing: 3
    }

    // swipe chevrons, flash 400 ms
    Canvas {
        id: chev
        width: 48; height: 48
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        opacity: pill.flashDir !== "" ? 1.0 : (pill.mode === "armed" && pill.gmodeLabel === "" ? 0.25 : 0.0)
        Behavior on opacity { NumberAnimation { duration: 120 } }
        property string dir: pill.flashDir
        onDirChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.lineWidth = 5; ctx.lineCap = "round"; ctx.lineJoin = "round"
            function draw(up, active) {
                ctx.strokeStyle = active ? "#00e5ff" : "#5a5a5a"
                ctx.beginPath()
                var y0 = up ? 18 : 30, tip = up ? 6 : 42
                ctx.moveTo(10, up ? 20 : 28); ctx.lineTo(24, up ? 6 : 42); ctx.lineTo(38, up ? 20 : 28)
                ctx.stroke()
            }
            if (dir === "left" || dir === "right") {
                var left = dir === "left"
                ctx.strokeStyle = "#00e5ff"
                ctx.beginPath()
                ctx.moveTo(left ? 28 : 20, 10); ctx.lineTo(left ? 8 : 40, 24); ctx.lineTo(left ? 28 : 20, 38)
                ctx.moveTo(left ? 8 : 40, 24); ctx.lineTo(left ? 42 : 6, 24)
                ctx.stroke()
                return
            }
            draw(true, dir === "up")
            draw(false, dir === "down")
        }
    }
}
