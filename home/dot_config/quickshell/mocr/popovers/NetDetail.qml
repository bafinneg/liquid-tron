import QtQuick
import "../theme"
import "../components"

// Network detail content: dual sparklines + interface info.

Item {
    id: root
    property var stats: ({
        netDown: 0, netUp: 0, netConnected: false,
        netDownHistory: [], netUpHistory: [],
        netInterface: "", netIpAddress: "", netLinkSpeed: ""
    })

    function formatBw(bytesPerSec) {
        if (bytesPerSec < 1000) return Math.round(bytesPerSec) + " B/s"
        if (bytesPerSec < 1000000) return (bytesPerSec / 1000).toFixed(1) + " KB/s"
        if (bytesPerSec < 1000000000) return (bytesPerSec / 1000000).toFixed(1) + " MB/s"
        return (bytesPerSec / 1000000000).toFixed(1) + " GB/s"
    }

    Column {
        anchors.fill: parent
        spacing: 4

        Text {
            text: root.stats.netConnected
                ? "\u2193 " + root.formatBw(root.stats.netDown) + "   \u2191 " + root.formatBw(root.stats.netUp)
                : "DISCONNECTED"
            color: Colors.green
            font.family: Geometry.fontFamily
            font.pixelSize: 10
            font.weight: Geometry.fontWeight
        }

        Item {
            width: parent.width
            height: 40

            Sparkline {
                anchors.fill: parent
                points: root.stats.netDownHistory
                lineColor: Colors.green
            }

            Sparkline {
                anchors.fill: parent
                points: root.stats.netUpHistory
                lineColor: Colors.amber
                fillColor: Qt.alpha(Colors.amber, 0.05)
            }
        }

        Column {
            width: parent.width
            spacing: 2

            Repeater {
                model: [
                    { label: "INTERFACE",  value: root.stats.netInterface || "\u2014" },
                    { label: "IP ADDRESS", value: root.stats.netIpAddress && root.stats.netIpAddress !== "?" ? root.stats.netIpAddress : "\u2014" },
                    { label: "LINK SPEED", value: root.stats.netLinkSpeed && root.stats.netLinkSpeed !== "?" && root.stats.netLinkSpeed !== "-1" ? root.stats.netLinkSpeed + " Mbps" : "\u2014" }
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
