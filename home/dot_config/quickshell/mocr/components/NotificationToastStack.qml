import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../services" as Services

// Single PanelWindow for all notification toasts. Created once in shell.qml
// outside the Variants block, pinned to DP-3 (center monitor).
// Reads popover bridge from NotificationService to shift below open popovers.

PanelWindow {
    id: stack

    anchors {
        top: true
        right: true
    }

    margins.top: Geometry.barHeightCenter + 3
                 + (Services.NotificationService.popoverShelfOpen
                    ? Services.NotificationService.popoverShelfHeight + 6
                    : 0)
    margins.right: Geometry.barPaddingOuter

    Behavior on margins.top {
        NumberAnimation {
            duration: Motion.durationPopover
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decay
        }
    }

    exclusiveZone: 0
    color: "transparent"

    visible: Services.NotificationService.activeToasts.length > 0

    implicitWidth: Geometry.toastWidth
    implicitHeight: Math.max(1, toastColumn.implicitHeight)

    Column {
        id: toastColumn
        anchors.right: parent.right
        width: Geometry.toastWidth
        spacing: Geometry.transientSurfaceGap

        Repeater {
            model: Services.NotificationService.activeToasts.length

            NotificationToast {
                required property int index
                toastData: index < Services.NotificationService.activeToasts.length
                    ? Services.NotificationService.activeToasts[index] : null
                toastIndex: index
            }
        }
    }
}
