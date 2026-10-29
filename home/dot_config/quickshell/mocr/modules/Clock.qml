import QtQuick
import "../theme"
import "../components"

// Clock module: HH:MM:SS, amber, weight 600, 1-second updates.
// Click toggles Calendar popover in the shelf.

ModuleContainer {
    id: root

    property var parentBar
    property string _timeText: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = new Date()
            var h = now.getHours().toString().padStart(2, '0')
            var m = now.getMinutes().toString().padStart(2, '0')
            var s = now.getSeconds().toString().padStart(2, '0')
            root._timeText = h + ":" + m + ":" + s
        }
    }

    contentItem: [
        Text {
            text: root._timeText
            color: Colors.amber
            font.family: Geometry.fontFamily
            font.pixelSize: Geometry.fontSize
            font.weight: Font.DemiBold
            verticalAlignment: Text.AlignVCenter
            height: parent.height

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.parentBar.togglePopover("calendar")
            }
        }
    ]
}
