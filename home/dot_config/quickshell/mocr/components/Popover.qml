import Quickshell
import QtQuick
import "../theme"

// Base popover component for MOCR-Q bar modules.
//
// Extends PopupWindow, anchored below the target module (bar is top-anchored).
// Toggle-only: click the module to open/close. Popovers persist until
// explicitly toggled — no click-outside dismissal.
// Multiple popovers can be open simultaneously.
// Semi-transparent chrome with floating gap and slide-from-right entrance.
//
// Usage:
//   Popover {
//       id: myPopover
//       anchor.window: bar       // the PanelWindow
//       anchor.item: myModule    // the module Item to anchor to
//       popoverWidth: 200
//       popoverHeight: 150
//       popoverContent: [
//           Column { ... }
//       ]
//   }
//   // Toggle: myPopover.toggle()

PopupWindow {
    id: popover

    color: "transparent"
    visible: false

    property alias popoverContent: contentArea.data
    property int popoverWidth: 200
    property int popoverHeight: 120
    property int contentMargin: 8
    property int _floatGap: 6

    implicitWidth: popoverWidth
    implicitHeight: popoverHeight + _floatGap

    // Anchor below the bar module (bar is at screen top).
    // edges: Bottom = popup attaches at the bottom edge of the anchor item.
    // gravity: Bottom = popup grows downward from that attachment point.
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    function toggle() {
        if (visible) close(); else open()
    }

    function open() {
        visible = true
        chrome.opacity = 1
        chrome.slideOffset = 0
    }

    function close() {
        chrome.opacity = 0
        chrome.slideOffset = 20
        _closeTimer.start()
    }

    // Chrome: semi-transparent bg_alt fill, 2px cyan border, 8px radius.
    // Floats below bar with a gap. Slides in from right on open.
    Rectangle {
        id: chrome
        x: 0
        y: popover._floatGap
        width: popover.popoverWidth
        height: popover.popoverHeight
        color: Qt.alpha(Colors.bg_alt, 0.85)
        radius: Geometry.radiusChrome
        border.width: Geometry.borderWidthAccent
        border.color: Colors.cyan
        opacity: 0

        property real slideOffset: 20
        transform: Translate { x: chrome.slideOffset }

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.durationPopover
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.decay
            }
        }

        Behavior on slideOffset {
            NumberAnimation {
                duration: Motion.durationPopover
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.decay
            }
        }

        Item {
            id: contentArea
            anchors.fill: parent
            anchors.margins: popover.contentMargin
        }
    }

    Timer {
        id: _closeTimer
        interval: Motion.durationPopover + 20
        onTriggered: popover.visible = false
    }
}
