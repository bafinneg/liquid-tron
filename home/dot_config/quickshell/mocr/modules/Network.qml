import QtQuick
import "../theme"
import "../components"

// Network module: "NET XXXX↓ XXXX↑". Connected traffic uses restrained cyan;
// disconnected state uses semantic amber.
// Click toggles NetDetail popover in the shelf.

ModuleContainer {
    id: root

    property var parentBar
    sourceActive: parentBar && parentBar.activePopoverId === "net"
    moduleState: sysStats.netConnected ? "normal" : "warning"

    function formatBw(bytesPerSec) {
        if (bytesPerSec < 1000)
            return Math.round(bytesPerSec).toString().padStart(5, ' ')
        if (bytesPerSec < 1000000) {
            var k = (bytesPerSec / 1000).toFixed(0)
            return (k + "K").padStart(5, ' ')
        }
        if (bytesPerSec < 1000000000) {
            var m = (bytesPerSec / 1000000).toFixed(1)
            return (m + "M").padStart(5, ' ')
        }
        var g = (bytesPerSec / 1000000000).toFixed(1)
        return (g + "G").padStart(5, ' ')
    }

    TweenedNumber {
        id: tweenDown
        visible: false
        value: sysStats.netDown
    }

    TweenedNumber {
        id: tweenUp
        visible: false
        value: sysStats.netUp
    }

    TextMetrics {
        id: netMetrics
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
        text: "NET 00.0M\u2193 00.0M\u2191"
    }

    contentItem: [
        Text {
            width: netMetrics.advanceWidth
            text: sysStats.netConnected
                ? "NET " + root.formatBw(tweenDown.displayValue) + "\u2193 " +
                  root.formatBw(tweenUp.displayValue) + "\u2191"
                : "NET \u2500\u2500\u2500\u2500\u2500\u2500"
            color: sysStats.netConnected ? Colors.cyan : Colors.amber
            font.family: Geometry.fontFamily
            font.pixelSize: Geometry.fontSize
            font.weight: Geometry.fontWeight
            verticalAlignment: Text.AlignVCenter
            height: Geometry.barHeightCenter

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.parentBar.togglePopover("net")
            }
        }
    ]
}
