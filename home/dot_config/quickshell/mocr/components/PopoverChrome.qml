import QtQuick
import "../theme"

// Shared popover chrome: semi-transparent rounded rectangle.
// Close: border snaps off instantly (no cyan blur), opacity fades,
// dimensions hold at full size, then snap to 0 after fade.
// Auto-closes after 10s; hover pauses the timer.

Rectangle {
    id: chrome

    property bool popoverOpen: false
    property int popoverWidth: 260
    property int popoverHeight: 200
    property var onAutoClose: function() {}

    property bool _closing: false

    width: (popoverOpen || _closing) ? popoverWidth : 0
    height: (popoverOpen || _closing) ? popoverHeight : 0
    visible: popoverOpen || _closing
    opacity: popoverOpen ? 1 : 0
    clip: true

    color: Qt.alpha(Colors.bg_alt, 0.85)
    radius: Geometry.radiusChrome
    // Border snaps off immediately on close — eliminates cyan blur artifact
    border.width: popoverOpen ? Geometry.borderWidthAccent : 0
    border.color: Colors.cyan

    Behavior on opacity {
        NumberAnimation {
            duration: Motion.durationPopover
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decay
        }
    }

    onPopoverOpenChanged: {
        if (!popoverOpen) {
            _closing = true
            _snapTimer.start()
            _autoCloseTimer.stop()
        } else {
            _closing = false
            _snapTimer.stop()
            _autoCloseTimer.restart()
        }
    }

    Timer {
        id: _snapTimer
        interval: Motion.durationPopover + 20
        onTriggered: chrome._closing = false
    }

    Timer {
        id: _autoCloseTimer
        interval: 10000
        onTriggered: chrome.onAutoClose()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: chrome.onAutoClose()
        onEntered: _autoCloseTimer.stop()
        onExited: if (chrome.popoverOpen) _autoCloseTimer.restart()
    }
}
