import QtQuick
import "../theme"
import "../components"

// CPU detail content: sparkline of aggregate usage + 16 per-core bars.

Item {
    id: root
    property var stats: ({ cpuUsage: 0, cpuHistory: [], coreUsages: [] })

    Column {
        anchors.fill: parent
        spacing: 6

        Text {
            text: "CPU USAGE  " + root.stats.cpuUsage + "%"
            color: Colors.cyan
            font.family: Geometry.fontFamily
            font.pixelSize: 10
            font.weight: Geometry.fontWeight
        }

        Sparkline {
            width: parent.width
            height: 40
            points: root.stats.cpuHistory
            lineColor: Colors.cyan
        }

        Text {
            text: "PER CORE"
            color: Colors.fg_dim
            font.family: Geometry.fontFamily
            font.pixelSize: 10
            font.weight: Geometry.fontWeight
        }

        Row {
            spacing: 2
            height: 50

            Repeater {
                model: 16

                Item {
                    property int usage: index < root.stats.coreUsages.length
                        ? root.stats.coreUsages[index] : 0
                    width: Math.floor((root.width - 15 * 2) / 16)
                    height: 50

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(1, parent.height * parent.usage / 100)
                        color: parent.usage >= 95 ? Colors.red
                             : parent.usage >= 85 ? Colors.amber
                             : Colors.cyan

                        Behavior on height {
                            NumberAnimation {
                                duration: Motion.durationTween
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Motion.decay
                            }
                        }
                    }
                }
            }
        }
    }
}
