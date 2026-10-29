import QtQuick
import "../theme"
import "../components"
import "../services" as Services

// GPU detail content: utilization sparkline, thermals, VRAM meter, and power.
Item {
    id: root

    Column {
        anchors.fill: parent
        spacing: 6

        Text {
            text: "GPU USAGE  " + Services.GpuStats.gpuUsage + "%"
            color: Colors.cyan
            font.family: Geometry.fontFamily
            font.pixelSize: 10
            font.weight: Geometry.fontWeight
        }

        Sparkline {
            width: parent.width
            height: 40
            points: Services.GpuStats.gpuHistory
            lineColor: Colors.cyan
        }

        Row {
            width: parent.width
            spacing: 8
            Text {
                width: 70
                text: "TEMP"
                color: Colors.fg_dim
                font.family: Geometry.fontFamily
                font.pixelSize: 10
                font.weight: Geometry.fontWeight
            }
            Text {
                text: Services.GpuStats.gpuTemp + "°C"
                color: Services.GpuStats.gpuTemp >= 84 ? Colors.red : Services.GpuStats.gpuTemp >= 75 ? Colors.amber : Colors.cyan
                font.family: Geometry.fontFamily
                font.pixelSize: 10
                font.weight: Geometry.fontWeight
            }
        }

        Row {
            width: parent.width
            spacing: 8
            Text {
                width: 70
                text: "POWER"
                color: Colors.fg_dim
                font.family: Geometry.fontFamily
                font.pixelSize: 10
                font.weight: Geometry.fontWeight
            }
            Text {
                text: Services.GpuStats.powerDraw.toFixed(1) + " W"
                color: Colors.cyan
                font.family: Geometry.fontFamily
                font.pixelSize: 10
                font.weight: Geometry.fontWeight
            }
        }

        Text {
            text: "VRAM  " + Services.GpuStats.vramUsed + " / " + Services.GpuStats.vramTotal + " MiB"
            color: Colors.fg_dim
            font.family: Geometry.fontFamily
            font.pixelSize: 10
            font.weight: Geometry.fontWeight
        }

        Rectangle {
            width: parent.width
            height: 8
            radius: 3
            color: Qt.alpha(Colors.bg_dark, 0.8)
            border.width: 1
            border.color: Qt.alpha(Colors.cyan, 0.25)

            readonly property real frac: Services.GpuStats.vramTotal > 0 ? Math.max(0, Math.min(1, Services.GpuStats.vramUsed / Services.GpuStats.vramTotal)) : 0

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * parent.frac
                radius: 3
                color: parent.frac >= 0.9 ? Colors.red : parent.frac >= 0.75 ? Colors.amber : Colors.cyan
                Behavior on width {
                    NumberAnimation {
                        duration: Motion.durationTween
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.decay
                    }
                }
            }
        }

        Sparkline {
            width: parent.width
            height: 32
            points: Services.GpuStats.vramHistory
            lineColor: Colors.amber
        }
    }
}
