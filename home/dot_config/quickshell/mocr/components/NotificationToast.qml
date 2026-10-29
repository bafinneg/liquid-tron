import QtQuick
import Quickshell.Services.Notifications
import "../theme"
import "../services" as Services

// Individual notification toast. Rendered inside NotificationToastStack's Column.
// Reads plain JS object data (not C++ QObject). Per-urgency styling,
// slide+fade entrance, fade-only exit. Hover pauses auto-close. Click dismisses.

Rectangle {
    id: toast

    // Plain JS object: { summary, body, appName, urgency, notifId, image, appType, receivedAt }
    property var toastData: null
    // Index in the activeToasts array — used for dismiss/pause service calls.
    property int toastIndex: -1

    // Animation state
    property real _slideOffset: 20
    property real _fadeOpacity: 0
    property bool _dismissed: false
    property string _displaySummary: ""
    property string _displayBody: ""
    property int _displayNotifId: -1
    property bool _initialized: false
    property bool _rewritePending: toastData !== null
                                   && Services.NotificationInterpreter.pendingRewriteIds[toastData.notifId] === true

    width: Geometry.toastWidth
    height: contentRow.implicitHeight + Geometry.barPaddingModule * 2
    radius: Geometry.radiusChrome
    color: Qt.alpha(Colors.bg_alt, 0.85)
    border.width: Geometry.borderWidthAccent
    border.color: _borderColor
    opacity: _fadeOpacity
    clip: true

    transform: Translate { x: toast._slideOffset }

    // ── Per-urgency styling ────────────────────────────────────

    readonly property bool _isCritical: toastData && toastData.urgency === NotificationUrgency.Critical
    readonly property bool _isLow: toastData && toastData.urgency === NotificationUrgency.Low

    readonly property color _borderColor: _isCritical ? Colors.red
                                        : _isLow ? Colors.fg_dark
                                        : Colors.cyan

    readonly property color _summaryColor: _isCritical ? Colors.white
                                         : _isLow ? Colors.fg_dim
                                         : Colors.fg

    readonly property color _bodyColor: _isCritical ? Colors.fg
                                      : _isLow ? Colors.fg_dark
                                      : Colors.fg_dim

    onToastDataChanged: {
        if (!toastData) return
        if (!_initialized || toastData.notifId !== _displayNotifId) {
            _displayNotifId = toastData.notifId
            _displaySummary = toastData.summary
            _displayBody = toastData.body || ""
            _initialized = true
            textContent.opacity = 1
            return
        }
        // Same notification, new text: DATA-TNG rewrite arrived.
        if (toastData.summary !== _displaySummary || (toastData.body || "") !== _displayBody) {
            _rewriteAnim.start()
        }
    }

    // ── Entrance animation (slide+fade from right) ────────────

    Component.onCompleted: {
        if (toastData && !_initialized) {
            _displayNotifId = toastData.notifId
            _displaySummary = toastData.summary
            _displayBody = toastData.body || ""
            _initialized = true
        }
        _slideOffset = 0
        _fadeOpacity = 1
    }

    Behavior on _fadeOpacity {
        NumberAnimation {
            duration: Motion.durationPopover
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decay
        }
    }

    Behavior on _slideOffset {
        NumberAnimation {
            duration: Motion.durationPopover
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decay
        }
    }

    // ── Exit (fade only, no slide) ────────────────────────────

    function dismiss() {
        if (_dismissed) return
        _dismissed = true
        _fadeOpacity = 0
        _exitTimer.start()
    }

    Timer {
        id: _exitTimer
        interval: Motion.durationPopover + 20
        onTriggered: {
            if (toast.toastData)
                Services.NotificationService.dismissToastByNotifId(toast.toastData.notifId)
        }
    }

    // ── Content ───────────────────────────────────────────────

    readonly property bool _hasImage: toastData && toastData.image !== ""

    Item {
        id: textContent
        anchors.fill: parent
        opacity: 1

        SequentialAnimation {
            id: _rewriteAnim
            NumberAnimation {
                target: textContent
                property: "opacity"
                to: 0
                duration: 80
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.decay
            }
            ScriptAction {
                script: {
                    toast._displayNotifId = toast.toastData.notifId
                    toast._displaySummary = toast.toastData.summary
                    toast._displayBody = toast.toastData.body || ""
                }
            }
            NumberAnimation {
                target: textContent
                property: "opacity"
                to: 1
                duration: 80
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.decay
            }
        }

        Row {
            id: contentRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Geometry.barPaddingModule
            spacing: 8

            // Notification image (48x48, rounded)
            Rectangle {
                visible: toast._hasImage
                width: visible ? 48 : 0
                height: 48
                radius: Geometry.radiusInteractive
                color: "transparent"
                clip: true
                anchors.top: parent.top

                Image {
                    anchors.fill: parent
                    source: toast._hasImage ? toastData.image : ""
                    sourceSize: Qt.size(48, 48)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Column {
                id: contentCol
                width: contentRow.width - contentRow.spacing * (toast._hasImage ? 1 : 0)
                       - (toast._hasImage ? 48 : 0)
                spacing: 2

                Text {
                    visible: toastData && toastData.appName !== ""
                    text: toastData ? toastData.appName : ""
                    color: toast._borderColor
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize - 2
                    font.weight: Geometry.fontWeight
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    text: toast._displaySummary
                    color: toast._summaryColor
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    visible: toast._displayBody !== ""
                    text: toast._displayBody
                    color: toast._bodyColor
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize
                    font.weight: Geometry.fontWeight
                    wrapMode: Text.WordWrap
                    width: parent.width
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Visible semantic telemetry rail. It reinforces urgency without changing content or interaction.
    Rectangle {
        id: urgencyRail
        visible: toastData !== null
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Geometry.borderWidthAccent
        width: 4
        radius: 2
        color: toast._borderColor
    }

    // Scanning line: visible while DATA-TNG rewrite is in-flight.
    Rectangle {
        id: _scanLine
        visible: toast._rewritePending
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        anchors.left: parent.left
        anchors.leftMargin: Geometry.radiusChrome
        anchors.right: parent.right
        anchors.rightMargin: Geometry.radiusChrome
        height: 1
        color: toast._borderColor

        SequentialAnimation on opacity {
            running: _scanLine.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0.2; to: 0.8; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.8; to: 0.2; duration: 600; easing.type: Easing.InOutSine }
        }
    }

    // ── Interaction ───────────────────────────────────────────

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor

        onClicked: toast.dismiss()

        onEntered: Services.NotificationService.pauseToastAt(toast.toastIndex)
        onExited: Services.NotificationService.resumeToastAt(toast.toastIndex)
    }
}
