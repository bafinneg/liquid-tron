import QtQuick
import "../theme"
import "../components"

// Static hostname display. Cyan, weight 600.
// Click toggles PowerMenu popover in the shelf.

ModuleContainer {
    id: root

    property var parentBar

    contentItem: [
        Text {
            text: "ATLAS-7800X"
            color: Colors.cyan
            font.family: Geometry.fontFamily
            font.pixelSize: Geometry.fontSize
            font.weight: Font.DemiBold
            verticalAlignment: Text.AlignVCenter
            height: parent.height

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.parentBar.togglePopover("power")
            }
        }
    ]
}
