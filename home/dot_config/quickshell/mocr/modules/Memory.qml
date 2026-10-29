import QtQuick
import "../theme"
import "../components"

// Memory usage module: "MEM NN%", cyan, tweened value updates.
// Click toggles MemDetail popover in the shelf.

ModuleContainer {
    id: root

    property var parentBar
    sourceActive: parentBar && parentBar.activePopoverId === "mem"

    TextMetrics {
        id: memMetrics
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
        text: "MEM 100%"
    }

    contentItem: [
        TweenedNumber {
            width: memMetrics.advanceWidth
            value: sysStats.memUsage
            prefix: "MEM "
            suffix: "%"
            padWidth: 3
            textColor: Colors.cyan

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.parentBar.togglePopover("mem")
            }
        }
    ]
}
