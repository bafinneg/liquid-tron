import Quickshell
import QtQuick
import "../theme"
import "../components"

// Power menu content: Lock / Suspend / Reboot / Shutdown buttons.

Item {
    Column {
        anchors.fill: parent
        spacing: 4

        Repeater {
            model: [
                { label: "LOCK",     cmd: "loginctl lock-session" },
                { label: "SUSPEND",  cmd: "systemctl suspend" },
                { label: "REBOOT",   cmd: "systemctl reboot" },
                { label: "SHUTDOWN", cmd: "systemctl poweroff" }
            ]

            delegate: Rectangle {
                required property var modelData
                width: parent.width
                height: 30
                radius: Geometry.radiusInteractive
                color: buttonMouse.containsMouse ? Qt.alpha(Colors.cyan, 0.15) : "transparent"
                border.width: 1
                border.color: buttonMouse.containsMouse ? Qt.alpha(Colors.cyan, 0.4) : Colors.fg_dark

                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: modelData.label === "SHUTDOWN" ? Colors.red
                         : modelData.label === "REBOOT"   ? Colors.amber
                         : Colors.fg
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize
                    font.weight: Geometry.fontWeight
                }

                MouseArea {
                    id: buttonMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["sh", "-c", modelData.cmd])
                    }
                }
            }
        }
    }
}
