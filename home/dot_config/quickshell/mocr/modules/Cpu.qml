import QtQuick
import "../theme"
import "../components"

// CPU usage module: "CPU NN%", cyan, tweened value updates.
// Warning at 85%, critical at 95%.
// Click toggles CpuDetail popover in the shelf.

ModuleContainer {
    id: root

    property var parentBar
    sourceActive: parentBar && parentBar.activePopoverId === "cpu"
    property int warningThreshold: 85
    property int criticalThreshold: 95

    moduleState: sysStats.cpuUsage >= criticalThreshold ? "critical"
               : sysStats.cpuUsage >= warningThreshold  ? "warning"
               : "normal"

    TextMetrics {
        id: cpuMetrics
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
        text: "CPU 100%"
    }

    contentItem: [
        TweenedNumber {
            width: cpuMetrics.advanceWidth
            value: sysStats.cpuUsage
            prefix: "CPU "
            suffix: "%"
            padWidth: 3
            textColor: Colors.cyan

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.parentBar.togglePopover("cpu")
            }
        }
    ]
}
