import QtQuick
import "../theme"
import "../components"
import "../services" as Services

ModuleContainer {
    id: root
    property var parentBar

    moduleState: Services.SystemMode.gamingMode ? "warning" : "normal"

    contentItem: [
        Text {
            text: Services.SystemMode.gamingMode ? "GAME" : "INT"
            font.family: Geometry.fontFamily
            font.pixelSize: Geometry.fontSize
            font.weight: Geometry.fontWeight
            color: Services.SystemMode.gamingMode ? Colors.amber : Colors.cyan
            height: parent.height
            verticalAlignment: Text.AlignVCenter

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.parentBar.togglePopover("mode")
            }
        }
    ]
}
