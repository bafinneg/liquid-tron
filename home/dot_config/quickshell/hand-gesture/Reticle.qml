import QtQuick

// One hand reticle, drawn at (cx, cy) in the window's local space. Liquid Tron on OLED black:
// primary = the gesture cursor at the real pointer: thin cyan ring with four ticks and a centre dot, amber while a
// mouse button is held (or a drag is on), a dwell arc only when the dwell-focus option is on.
// secondary = smaller dim blue ring. Pinch closes the ring to a solid dot. Nothing else (no trails, no glow).
Item {
    id: ret
    property bool primary: true
    property real cx: 0
    property real cy: 0
    property bool pinch: false
    property bool over: false
    property real dwell: 0
    property bool btn: false

    readonly property bool targeting: primary && ((over && dwell > 0 && !pinch) || btn)
    readonly property color tint: !primary ? "#2a6bff" : targeting ? "#ffb000" : "#00e5ff"
    readonly property real ringR: !primary ? 14 : targeting ? 17 : 22

    x: cx - 40
    y: cy - 40
    width: 80
    height: 80

    Canvas {
        id: cv
        anchors.fill: parent
        antialiasing: true
        property color c: ret.tint
        property real r: ret.ringR
        property bool pin: ret.pinch
        property real d: ret.dwell
        property bool prim: ret.primary
        onCChanged: requestPaint()
        onRChanged: requestPaint()
        onPinChanged: requestPaint()
        onDChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var m = 40
            ctx.strokeStyle = c
            ctx.fillStyle = c
            if (pin) {
                ctx.beginPath(); ctx.arc(m, m, prim ? 7 : 5, 0, Math.PI * 2); ctx.fill()
                return
            }
            ctx.lineWidth = prim ? 2 : 1.5
            ctx.globalAlpha = prim ? 1.0 : 0.55
            ctx.beginPath(); ctx.arc(m, m, r, 0, Math.PI * 2); ctx.stroke()
            if (prim) {
                ctx.lineWidth = 2
                var t0 = r + 4, t1 = r + 12
                ctx.beginPath()
                ctx.moveTo(m, m - t0); ctx.lineTo(m, m - t1)
                ctx.moveTo(m, m + t0); ctx.lineTo(m, m + t1)
                ctx.moveTo(m - t0, m); ctx.lineTo(m - t1, m)
                ctx.moveTo(m + t0, m); ctx.lineTo(m + t1, m)
                ctx.stroke()
                ctx.beginPath(); ctx.arc(m, m, 2.5, 0, Math.PI * 2); ctx.fill()
                if (d > 0) {
                    ctx.lineWidth = 4
                    ctx.beginPath()
                    ctx.arc(m, m, r + 0.5, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, d))
                    ctx.stroke()
                }
            }
        }
    }
}
