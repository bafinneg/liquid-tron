import QtQuick
import "../theme"
import "../components"

// Temperature detail content: sparkline + per-sensor breakdown with trend arrows.

Item {
    id: root
    property var stats: ({ temperature: 0, tempHistory: [], tempSensors: [] })

    Column {
        anchors.fill: parent
        spacing: 4

        Text {
            text: "TEMPERATURE  " + root.stats.temperature + "\u00B0C"
            color: Colors.cyan
            font.family: Geometry.fontFamily
            font.pixelSize: 10
            font.weight: Geometry.fontWeight
        }

        Sparkline {
            width: parent.width
            height: 40
            points: root.stats.tempHistory
            lineColor: Colors.cyan
        }

        Text {
            text: "SENSORS"
            color: Colors.fg_dim
            font.family: Geometry.fontFamily
            font.pixelSize: 10
            font.weight: Geometry.fontWeight
        }

        Column {
            width: parent.width
            spacing: 2

            Repeater {
                model: root.stats.tempSensors

                Row {
                    required property var modelData
                    width: parent.width
                    height: 16

                    Text {
                        width: 70
                        text: modelData.name.toUpperCase()
                        color: Colors.fg_dim
                        font.family: Geometry.fontFamily; font.pixelSize: 10; font.weight: Geometry.fontWeight
                    }
                    Text {
                        width: 50
                        text: modelData.value + "\u00B0C"
                        color: Colors.fg
                        font.family: Geometry.fontFamily; font.pixelSize: 10; font.weight: Geometry.fontWeight
                    }
                    Text {
                        text: modelData.trend
                        color: Colors.fg_dim
                        font.family: Geometry.fontFamily; font.pixelSize: 12; font.weight: Geometry.fontWeight
                    }
                }
            }
        }
    }
}
