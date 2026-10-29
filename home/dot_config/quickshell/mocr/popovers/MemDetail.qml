import QtQuick
import "../theme"
import "../components"

// Memory detail content: sparkline + total/used/cached/available/free breakdown.

Item {
    id: root
    property var stats: ({
        memUsage: 0, memHistory: [],
        memTotalKB: 0, memFreeKB: 0, memAvailableKB: 0, memBuffersKB: 0, memCachedKB: 0
    })

    function formatKB(kb) {
        if (kb >= 1048576) return (kb / 1048576).toFixed(1) + " GB"
        if (kb >= 1024) return (kb / 1024).toFixed(0) + " MB"
        return kb + " KB"
    }

    Column {
        anchors.fill: parent
        spacing: 4

        Text {
            text: "MEMORY  " + root.stats.memUsage + "%"
            color: Colors.cyan
            font.family: Geometry.fontFamily
            font.pixelSize: 10
            font.weight: Geometry.fontWeight
        }

        Sparkline {
            width: parent.width
            height: 40
            points: root.stats.memHistory
            lineColor: Colors.cyan
        }

        Column {
            width: parent.width
            spacing: 2

            Repeater {
                model: [
                    { label: "TOTAL",     value: root.formatKB(root.stats.memTotalKB) },
                    { label: "USED",      value: root.formatKB(root.stats.memTotalKB - root.stats.memAvailableKB) },
                    { label: "CACHED",    value: root.formatKB(root.stats.memBuffersKB + root.stats.memCachedKB) },
                    { label: "AVAILABLE", value: root.formatKB(root.stats.memAvailableKB) },
                    { label: "FREE",      value: root.formatKB(root.stats.memFreeKB) }
                ]

                Row {
                    required property var modelData
                    width: parent.width; height: 16
                    Text {
                        width: 90; text: modelData.label; color: Colors.fg_dim
                        font.family: Geometry.fontFamily; font.pixelSize: 10; font.weight: Geometry.fontWeight
                    }
                    Text {
                        text: modelData.value; color: Colors.fg
                        font.family: Geometry.fontFamily; font.pixelSize: 10; font.weight: Geometry.fontWeight
                    }
                }
            }
        }
    }
}
