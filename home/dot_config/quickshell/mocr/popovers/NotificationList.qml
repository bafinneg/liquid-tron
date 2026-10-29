import QtQuick
import Quickshell.Services.Notifications
import "../theme"
import "../services" as Services

// Notification history popover content. Scrollable list of past notifications
// with urgency-colored left border accent, relative timestamps, unread tinting,
// and individual/clear dismissal actions.

Item {
    id: notifList

    property real _now: Date.now()

    Timer {
        interval: 60000
        repeat: true
        running: notifList.visible
        onTriggered: notifList._now = Date.now()
    }

    function _relTime(ms) {
        if (!ms) return ""
        var delta = Math.max(0, (notifList._now - ms) / 1000)
        if (delta < 60)    return "just now"
        if (delta < 3600)  return Math.floor(delta / 60) + "m ago"
        if (delta < 86400) return Math.floor(delta / 3600) + "h ago"
        return Math.floor(delta / 86400) + "d ago"
    }

    // ── Empty state ───────────────────────────────────────────

    Text {
        visible: Services.NotificationService.historyList.length === 0
        anchors.centerIn: parent
        text: "NO NOTIFICATIONS"
        color: Colors.fg_dark
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
    }

    // ── List ──────────────────────────────────────────────────

    Flickable {
        id: flickable
        visible: Services.NotificationService.historyList.length > 0
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: clearBtn.top
        anchors.bottomMargin: 6
        clip: true
        contentHeight: listCol.implicitHeight
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: listCol
            width: parent.width
            spacing: Geometry.transientSurfaceGap

            Repeater {
                model: Services.NotificationService.historyList.length

                Rectangle {
                    id: entry
                    required property int index

                    readonly property var _item: index < Services.NotificationService.historyList.length
                        ? Services.NotificationService.historyList[index] : null
                    readonly property string _relativeTime: _item ? notifList._relTime(_item.receivedAt) : ""

                    width: listCol.width
                    height: entryRow.implicitHeight + 12
                    color: (_item && _item.receivedAt > Services.NotificationService.lastViewedAt)
                           ? Qt.alpha(Colors.cyan, 0.10)
                           : Qt.alpha(Colors.bg_inset, 0.88)
                    border.width: Geometry.borderWidth
                    border.color: Colors.fg_dark
                    radius: Geometry.radiusInteractive

                    // Left border accent per urgency
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 4
                        radius: 2
                        color: entry._item
                            ? (entry._item.urgency === NotificationUrgency.Critical ? Colors.red
                               : entry._item.urgency === NotificationUrgency.Low ? Colors.fg_dark
                               : Colors.cyan)
                            : Colors.fg_dark
                    }

                    readonly property bool _hasImage: _item && _item.image !== ""

                    Row {
                        id: entryRow
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.topMargin: 6
                        spacing: 6

                        // History image (32x32, rounded)
                        Rectangle {
                            visible: entry._hasImage
                            width: visible ? 32 : 0
                            height: 32
                            radius: Geometry.radiusInteractive
                            color: "transparent"
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: entry._hasImage ? entry._item.image : ""
                                sourceSize: Qt.size(32, 32)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        Column {
                            id: entryCol
                            width: entryRow.width - entryRow.spacing * (entry._hasImage ? 1 : 0)
                                   - (entry._hasImage ? 32 : 0)
                            spacing: 1

                            // Summary
                            Text {
                                text: entry._item ? entry._item.summary : ""
                                color: Colors.fg
                                font.family: Geometry.fontFamily
                                font.pixelSize: Geometry.fontSize
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            // Body (already stripped in service)
                            Text {
                                visible: entry._item && entry._item.body !== ""
                                text: entry._item ? entry._item.body : ""
                                color: Colors.fg_dim
                                font.family: Geometry.fontFamily
                                font.pixelSize: Geometry.fontSize
                                font.weight: Geometry.fontWeight
                                wrapMode: Text.WordWrap
                                width: parent.width
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            // App name + relative timestamp metadata
                            Row {
                                spacing: 6
                                visible: entry._item && (entry._item.appName !== "" || entry._relativeTime !== "")

                                Text {
                                    visible: entry._item && entry._item.appName !== ""
                                    text: entry._item ? entry._item.appName : ""
                                    color: Colors.fg_dark
                                    font.family: Geometry.fontFamily
                                    font.pixelSize: Geometry.fontSize - 2
                                    font.weight: Geometry.fontWeight
                                }

                                Text {
                                    visible: entry._item && entry._item.appName !== "" && entry._relativeTime !== ""
                                    text: "·"
                                    color: Colors.fg_dark
                                    font.family: Geometry.fontFamily
                                    font.pixelSize: Geometry.fontSize - 2
                                }

                                Text {
                                    visible: entry._relativeTime !== ""
                                    text: entry._relativeTime
                                    color: Colors.fg_dark
                                    font.family: Geometry.fontFamily
                                    font.pixelSize: Geometry.fontSize - 2
                                    font.weight: Geometry.fontWeight
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        onClicked: Services.NotificationService.dismissHistoryAt(entry.index)
                    }
                }
            }
        }
    }

    // ── Clear button ──────────────────────────────────────────

    Rectangle {
        id: clearBtn
        visible: Services.NotificationService.historyList.length > 0
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(clearText.implicitWidth + 24, 112)
        height: clearText.implicitHeight + 12
        radius: Geometry.radiusInteractive
        color: clearMouseArea.containsMouse ? Colors.blue : Colors.bg_inset
        border.width: Geometry.borderWidth
        border.color: Colors.cyan

        Text {
            id: clearText
            anchors.centerIn: parent
            text: "CLEAR"
            color: clearMouseArea.containsMouse ? Colors.white : Colors.cyan
            font.family: Geometry.fontFamily
            font.pixelSize: Geometry.fontSize
            font.weight: Geometry.fontWeight
        }

        MouseArea {
            id: clearMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Services.NotificationService.clearAll()
        }
    }
}
