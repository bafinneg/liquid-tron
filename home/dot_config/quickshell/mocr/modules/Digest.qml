import QtQuick
import "../theme"
import "../components"
import "../services" as Services

// Daily anomaly digest freshness pill. Click toggles the shelf reader.
ModuleContainer {
    id: root

    property var parentBar
    sourceActive: parentBar && parentBar.activePopoverId === "digest"
    moduleState: Services.DigestService.staleDays >= 2 ? "warning" : "normal"

    TextMetrics {
        id: digestMetrics
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
        text: "DIG 99d"
    }

    contentItem: [
        Item {
            implicitWidth: digestMetrics.advanceWidth
            implicitHeight: Geometry.barHeightCenter

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: !Services.DigestService.available
                      ? "DIG ──"
                      : "DIG " + Services.DigestService.staleDays + "d"
                color: Colors.cyan
                font.family: Geometry.fontFamily
                font.pixelSize: Geometry.fontSize
                font.weight: Geometry.fontWeight
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton
                onClicked: root.parentBar.togglePopover("digest")
            }
        }
    ]
}
