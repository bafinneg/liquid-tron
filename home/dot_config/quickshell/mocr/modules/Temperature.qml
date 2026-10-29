import QtQuick
import "../theme"
import "../components"

// Temperature module: "TMP NN°", cyan normally, red at critical (≥80°C).
// Warning at 75°C, critical at 80°C.
// Click toggles TempDetail popover in the shelf.

ModuleContainer {
    id: root

    property var parentBar
    sourceActive: parentBar && parentBar.activePopoverId === "temp"
    property int warningThreshold: 75
    property int criticalThreshold: 80

    moduleState: sysStats.temperature < 0                   ? "normal"
               : sysStats.temperature >= criticalThreshold ? "critical"
               : sysStats.temperature >= warningThreshold  ? "warning"
               : "normal"

    TextMetrics {
        id: tmpMetrics
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
        text: "TMP 100\u00B0"
    }

    contentItem: [
        TweenedNumber {
            width: tmpMetrics.advanceWidth
            value: sysStats.temperature < 0 ? 0 : sysStats.temperature
            prefix: "TMP "
            suffix: sysStats.temperature < 0 ? "" : "\u00B0"
            padWidth: 3
            textColor: sysStats.temperature < 0 ? Colors.fg_dim
                     : sysStats.temperature >= root.criticalThreshold ? Colors.red
                     : Colors.cyan

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.parentBar.togglePopover("temp")
            }
        }
    ]
}
