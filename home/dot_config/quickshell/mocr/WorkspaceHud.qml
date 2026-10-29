import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "theme"

// Transient OLED-safe workspace switch feedback for side monitors.
PanelWindow {
    id: hud
    property var modelData

    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mocr-workspace-hud"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { left: true }
    exclusiveZone: 0
    color: "transparent"
    visible: chrome.visible
    implicitWidth: 84
    implicitHeight: stack.implicitHeight + 20
    margins.left: 24
    margins.top: modelData ? Math.max(0, Math.round((modelData.height - implicitHeight) / 2)) : 0

    readonly property string monitorName: modelData ? modelData.name : ""
    readonly property int workspaceCount: 3
    property int previousActiveWorkspaceId: -1
    property real hudOpacity: 0.0

    readonly property var monitor: {
        var vals = Hyprland.workspaces.values
        for (var i = 0; i < vals.length; i++) {
            var w = vals[i]
            if (w && w.monitor && w.monitor.name === hud.monitorName) return w.monitor
        }
        return null
    }

    readonly property int activeWorkspaceId: {
        if (!hud.monitor) return -1
        var w = hud.monitor.activeWorkspace
        return w ? w.id : -1
    }

    readonly property int activeLocalWorkspace: hud.localNumber(hud.activeWorkspaceId)

    function localNumber(globalId) {
        if (globalId < 1) return -1
        return ((globalId - 1) % hud.workspaceCount) + 1
    }

    onActiveWorkspaceIdChanged: {
        if (hud.previousActiveWorkspaceId >= 1
                && hud.activeWorkspaceId >= 1
                && hud.activeWorkspaceId !== hud.previousActiveWorkspaceId) {
            pulseAnim.restart()
        }
        hud.previousActiveWorkspaceId = hud.activeWorkspaceId
    }

    SequentialAnimation {
        id: pulseAnim
        NumberAnimation {
            target: hud
            property: "hudOpacity"
            to: 1.0
            duration: 90
            easing.type: Easing.OutCubic
        }
        PauseAnimation { duration: 900 }
        NumberAnimation {
            target: hud
            property: "hudOpacity"
            to: 0.0
            duration: 300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decay
        }
    }

    Rectangle {
        id: chrome
        width: hud.implicitWidth
        height: hud.implicitHeight
        radius: Geometry.radiusChrome
        color: Qt.alpha(Colors.bg, 0.88)
        border.width: Geometry.borderWidth
        border.color: Qt.alpha(Colors.cyan, 0.34)
        opacity: hud.hudOpacity
        visible: hud.hudOpacity > 0.001

        Column {
            id: stack
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: [1, 2, 3]

                Item {
                    id: cell
                    required property int modelData
                    readonly property bool active: hud.activeLocalWorkspace === cell.modelData
                    width: 56
                    height: 48

                    Rectangle {
                        anchors.fill: parent
                        radius: Geometry.radiusContent
                        color: cell.active ? Qt.alpha(Colors.amber, 0.12) : "transparent"
                        border.width: Geometry.borderWidth
                        border.color: cell.active ? Qt.alpha(Colors.amber, 0.58) : Qt.alpha(Colors.cyan, 0.18)
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: WorkspaceGlyphs.glyphFor(cell.modelData)
                            color: cell.active ? Colors.amber : Qt.alpha(Colors.cyan, 0.5)
                            font.family: Geometry.fontFamily
                            font.pixelSize: 22
                            font.weight: Geometry.fontWeight
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: String(cell.modelData)
                            color: cell.active ? Colors.amber : Qt.alpha(Colors.cyan, 0.5)
                            font.family: Geometry.fontFamily
                            font.pixelSize: 10
                            font.weight: Geometry.fontWeight
                        }
                    }
                }
            }
        }
    }
}
