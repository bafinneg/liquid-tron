import QtQuick

// Low-luminance DP-3 command-well depth field.
// The field is local to CenterAmbientLayer and reads only its own size and
// timer phase: no app metadata, cursor state, pixels, or wallpaper state.
// 250ms update rate (4fps) keeps the motion visible but calm.
Item {
    id: root
    anchors.fill: parent

    readonly property int frameMs: 250
    readonly property int commandBarHeight: 52
    readonly property int motionLimitPx: 24
    readonly property real maxAlpha: 0.16

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject

        property real t: 0

        function clamp(value, lower, upper) {
            return Math.max(lower, Math.min(upper, value))
        }

        function rgba(rgb, alpha) {
            return "rgba(" + rgb + "," + alpha + ")"
        }

        function fillEllipse(ctx, cx, cy, rx, ry, fillStyle) {
            ctx.save()
            ctx.translate(cx, cy)
            ctx.scale(rx, ry)
            ctx.fillStyle = fillStyle
            ctx.beginPath()
            ctx.arc(0, 0, 1, 0, Math.PI * 2)
            ctx.fill()
            ctx.restore()
        }

        function drawPanel(ctx, points, fillStyle) {
            ctx.fillStyle = fillStyle
            ctx.beginPath()
            ctx.moveTo(points[0].x, points[0].y)
            for (var i = 1; i < points.length; i++)
                ctx.lineTo(points[i].x, points[i].y)
            ctx.closePath()
            ctx.fill()
        }

        function strokePath(ctx, points, color, width) {
            ctx.strokeStyle = color
            ctx.lineWidth = width
            ctx.beginPath()
            ctx.moveTo(points[0].x, points[0].y)
            for (var i = 1; i < points.length; i++)
                ctx.lineTo(points[i].x, points[i].y)
            ctx.stroke()
        }

        Timer {
            interval: root.frameMs
            repeat: true
            running: root.visible && canvas.width > 0 && canvas.height > 0
            onTriggered: {
                canvas.t += root.frameMs
                canvas.requestPaint()
            }
        }

        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0)
                return

            var cyan = "10,189,198"
            var blue = "0,114,255"
            var voidRgb = "0,0,0"
            var minDim = Math.min(width, height)
            var motion = canvas.clamp(minDim * 0.006, 8, root.motionLimitPx)
            var centerX = width * 0.5 + Math.sin(canvas.t / 17000) * motion * 0.35
            var topY = Math.max(root.commandBarHeight, height * 0.055)
            var spineWidth = canvas.clamp(width * 0.22, 520, 760)
            var wellTopHalf = spineWidth * 0.20
            var wellBottomHalf = canvas.clamp(width * 0.16, spineWidth * 0.55, spineWidth * 0.82)
            var lowerY = height * 0.80 + Math.cos(canvas.t / 23000) * motion
            var phase = Math.sin(canvas.t / 29000)

            var leftShift = -phase * motion
            var rightShift = Math.cos(canvas.t / 31000) * motion
            var leftFill = ctx.createLinearGradient(centerX - spineWidth * 0.45, topY, 0, height)
            leftFill.addColorStop(0.00, canvas.rgba(cyan, 0.10))
            leftFill.addColorStop(0.42, canvas.rgba(blue, 0.050))
            leftFill.addColorStop(1.00, canvas.rgba(cyan, 0.00))
            var rightFill = ctx.createLinearGradient(centerX + spineWidth * 0.45, topY, width, height)
            rightFill.addColorStop(0.00, canvas.rgba(cyan, 0.10))
            rightFill.addColorStop(0.42, canvas.rgba(blue, 0.050))
            rightFill.addColorStop(1.00, canvas.rgba(cyan, 0.00))

            var leftPlane = [
                { x: centerX - spineWidth * 0.34 + leftShift * 0.2, y: topY + 22 },
                { x: centerX - spineWidth * 0.62 + leftShift, y: topY + 76 },
                { x: centerX - width * 0.47 + leftShift * 0.6, y: height * 0.92 },
                { x: centerX - wellBottomHalf + leftShift * 0.25, y: lowerY }
            ]
            var rightPlane = [
                { x: centerX + spineWidth * 0.34 + rightShift * 0.2, y: topY + 22 },
                { x: centerX + spineWidth * 0.62 + rightShift, y: topY + 76 },
                { x: centerX + width * 0.47 + rightShift * 0.6, y: height * 0.92 },
                { x: centerX + wellBottomHalf + rightShift * 0.25, y: lowerY }
            ]
            canvas.drawPanel(ctx, leftPlane, leftFill)
            canvas.drawPanel(ctx, rightPlane, rightFill)

            var troughFill = ctx.createLinearGradient(centerX, topY, centerX, height)
            troughFill.addColorStop(0.00, canvas.rgba(voidRgb, 0.00))
            troughFill.addColorStop(0.22, canvas.rgba(voidRgb, 0.11))
            troughFill.addColorStop(0.72, canvas.rgba(voidRgb, 0.16))
            troughFill.addColorStop(1.00, canvas.rgba(voidRgb, 0.03))
            var trough = [
                { x: centerX - wellTopHalf, y: topY + 8 },
                { x: centerX + wellTopHalf, y: topY + 8 },
                { x: centerX + wellBottomHalf, y: lowerY },
                { x: centerX + wellBottomHalf * 0.46, y: height },
                { x: centerX - wellBottomHalf * 0.46, y: height },
                { x: centerX - wellBottomHalf, y: lowerY }
            ]
            canvas.drawPanel(ctx, trough, troughFill)

            var spineGlow = ctx.createRadialGradient(centerX, topY + 18, 0, centerX, topY + 18, spineWidth * 0.56)
            spineGlow.addColorStop(0.00, canvas.rgba(cyan, root.maxAlpha))
            spineGlow.addColorStop(0.36, canvas.rgba(blue, 0.085))
            spineGlow.addColorStop(1.00, canvas.rgba(cyan, 0.00))
            canvas.fillEllipse(ctx, centerX, topY + 20, spineWidth * 0.58, 68, spineGlow)

            var keelAlpha = 0.10 + 0.025 * Math.sin(canvas.t / 19000)
            canvas.strokePath(ctx, [
                { x: centerX - wellTopHalf, y: topY + 10 },
                { x: centerX - wellBottomHalf, y: lowerY }
            ], canvas.rgba(cyan, keelAlpha), 1.4)
            canvas.strokePath(ctx, [
                { x: centerX + wellTopHalf, y: topY + 10 },
                { x: centerX + wellBottomHalf, y: lowerY }
            ], canvas.rgba(cyan, keelAlpha), 1.4)

            var centerLine = ctx.createLinearGradient(centerX, topY, centerX, height)
            centerLine.addColorStop(0.00, canvas.rgba(blue, 0.105))
            centerLine.addColorStop(0.55, canvas.rgba(cyan, 0.050))
            centerLine.addColorStop(1.00, canvas.rgba(cyan, 0.00))
            ctx.fillStyle = centerLine
            ctx.fillRect(centerX - 0.5, topY + 12, 1, height - topY - 12)
        }
    }
}
