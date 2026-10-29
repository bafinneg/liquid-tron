import QtQuick
import "../theme"
import "../components"
import "../services" as Services

// Notification bar module: "NTF --" (no unread) or "NTF 3" (unread count).
// Click toggles notification history popover in the shelf.
// Warning state when a critical notification is active.

ModuleContainer {
    id: root

    property var parentBar
    sourceActive: parentBar && parentBar.activePopoverId === "notif"

    moduleState: Services.NotificationService.hasActiveCritical ? "critical" : "normal"

    TextMetrics {
        id: ntfMetrics
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
        text: "NTF 99"
    }

    contentItem: [
        Item {
            implicitWidth: ntfMetrics.advanceWidth
            implicitHeight: Geometry.barHeightCenter

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Services.NotificationService.unreadCount > 0
                      ? "NTF " + Services.NotificationService.unreadCount
                      : "NTF \u2500\u2500"
                color: Colors.cyan
                font.family: Geometry.fontFamily
                font.pixelSize: Geometry.fontSize
                font.weight: Geometry.fontWeight
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton
                onClicked: {
                    root.parentBar.togglePopover("notif")
                    Services.NotificationService.markRead()
                }
            }
        }
    ]
}
