import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "theme"

PanelWindow {
    id: selector
    property var modelData

    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mocr-side-workspace-selector"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
    }

    readonly property string monitorName: modelData ? modelData.name : ""
    readonly property int panelPaddingX: 12
    readonly property int panelPaddingY: 8
    readonly property int hotZoneHeight: 2
    readonly property int glyphFontSize: 38
    readonly property int nameFontSize: 15
    readonly property int workspaceCount: 3
    property bool expanded: false
    property int previousActiveWorkspaceId: -1
    property bool discoveryCueRequested: false

    readonly property var monitor: {
        var vals = Hyprland.workspaces.values
        for (var i = 0; i < vals.length; i++) {
            var w = vals[i]
            if (w && w.monitor && w.monitor.name === selector.monitorName) return w.monitor
        }
        return null
    }

    readonly property int activeWorkspaceId: {
        if (!selector.monitor) return -1
        var w = selector.monitor.activeWorkspace
        return w ? w.id : -1
    }

    readonly property int activeLocalWorkspace: selector.localNumber(selector.activeWorkspaceId)
    readonly property bool fullscreen: selector.monitor && selector.monitor.activeWorkspace
        ? selector.monitor.activeWorkspace.hasFullscreen : false
    readonly property bool selectorVisible: selector.expanded && !selector.fullscreen

    implicitWidth: panelChrome.implicitWidth
    implicitHeight: selector.selectorVisible ? panelChrome.implicitHeight : selector.hotZoneHeight
    exclusiveZone: 0
    color: "transparent"

    margins.left: modelData ? Math.max(0, Math.round((modelData.width - selector.implicitWidth) / 2)) : 0

    function localNumber(globalId) {
        if (globalId < 1) return -1
        return ((globalId - 1) % selector.workspaceCount) + 1
    }

    function switchWorkspace(id) {
        selector.expanded = false
        Quickshell.execDetached([
            "hyprctl",
            "dispatch",
            "function() return hl.plugin.split_monitor_workspaces.workspace(\"" + String(id) + "\") end"
        ])
    }

    function showDiscoveryCue(durationMs) {
        selector.discoveryCueRequested = true
        discoveryCueTimer.interval = durationMs
        discoveryCueTimer.restart()
    }

    Component.onCompleted: selector.showDiscoveryCue(5000)

    onActiveWorkspaceIdChanged: {
        if (selector.activeWorkspaceId >= 1
                && selector.previousActiveWorkspaceId >= 1
                && selector.activeWorkspaceId !== selector.previousActiveWorkspaceId) {
            selector.showDiscoveryCue(1500)
        }
        selector.previousActiveWorkspaceId = selector.activeWorkspaceId
    }

    onFullscreenChanged: {
        if (selector.fullscreen) {
            closeTimer.stop()
            selector.discoveryCueRequested = false
            selector.expanded = false
        }
    }

    Timer {
        id: discoveryCueTimer
        repeat: false
        onTriggered: selector.discoveryCueRequested = false
    }

    Timer {
        id: closeTimer
        interval: 240
        repeat: false
        onTriggered: selector.expanded = false
    }

    HoverHandler {
        enabled: !selector.fullscreen
        onHoveredChanged: {
            if (hovered) {
                closeTimer.stop()
                selector.expanded = true
            } else {
                closeTimer.restart()
            }
        }
    }

    // Transient discovery cue only: no text, focus, pointer capture, or reserved space.
    Rectangle {
        id: discoveryCue
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: 72
        height: 1
        color: Qt.alpha(Colors.cyan, 0.32)
        opacity: selector.discoveryCueRequested && !selector.expanded && !selector.fullscreen ? 1.0 : 0.0
        visible: opacity > 0.001
        z: 1

        Behavior on opacity {
            NumberAnimation { duration: selector.discoveryCueRequested ? 120 : 180; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        id: panelChrome
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: workspaceRow.implicitWidth + selector.panelPaddingX * 2
        implicitHeight: workspaceRow.implicitHeight + selector.panelPaddingY * 2
        radius: Geometry.radiusContent
        color: Qt.alpha(Colors.bg, 0.92)
        border.width: Geometry.borderWidth
        border.color: Qt.alpha(Colors.cyan, 0.34)
        opacity: selector.selectorVisible ? 1.0 : 0.0
        visible: selector.selectorVisible || opacity > 0.001
        z: 0

        Behavior on opacity {
            NumberAnimation {
                duration: selector.selectorVisible ? 90 : 120
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            color: Qt.alpha(Colors.cyan, 0.68)
        }
    }

    Row {
        id: workspaceRow
        spacing: 8
        anchors.centerIn: panelChrome
        opacity: selector.selectorVisible ? 1.0 : 0.0
        visible: selector.selectorVisible || opacity > 0.001
        z: 2

        Behavior on opacity {
            NumberAnimation {
                duration: selector.selectorVisible ? 90 : 80
                easing.type: Easing.OutCubic
            }
        }

        Repeater {
            model: [1, 2, 3]

            Item {
                id: cell
                required property int modelData

                readonly property bool active: selector.activeLocalWorkspace === cell.modelData
                property bool hovered: false
                property real labelWidth: cell.hovered ? nameLabel.implicitWidth + 12 : 0

                width: 56 + cell.labelWidth
                height: 52
                clip: true

                Behavior on width {
                    NumberAnimation {
                        duration: cell.hovered ? 120 : 80
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Geometry.radiusContent
                    color: cell.active
                        ? Qt.alpha(Colors.amber, cell.hovered ? 0.16 : 0.11)
                        : cell.hovered ? Qt.alpha(Colors.cyan, 0.09) : "transparent"
                    border.width: Geometry.borderWidth
                    border.color: cell.active
                        ? Qt.alpha(Colors.amber, cell.hovered ? 0.76 : 0.58)
                        : cell.hovered ? Qt.alpha(Colors.cyan, 0.44) : "transparent"

                    Behavior on color { ColorAnimation { duration: 80 } }
                }

                Item {
                    id: glyphBox
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: parent.height

                    Text {
                        id: glyphLabel
                        x: Math.round((glyphBox.width - glyphLabel.paintedWidth) / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        text: WorkspaceGlyphs.glyphFor(cell.modelData)
                        color: cell.active
                            ? Colors.amber
                            : cell.hovered ? Colors.cyan : Qt.alpha(Colors.cyan, 0.58)
                        font.family: Geometry.fontFamily
                        font.pixelSize: selector.glyphFontSize
                        font.weight: Geometry.fontWeight
                        verticalAlignment: Text.AlignVCenter

                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                }

                Text {
                    id: nameLabel
                    anchors.left: glyphBox.right
                    anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(cell.modelData) + " · " + WorkspaceGlyphs.nameFor(cell.modelData)
                    opacity: cell.hovered ? 1.0 : 0.0
                    color: cell.active ? Colors.amber : Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: selector.nameFontSize
                    font.weight: Geometry.fontWeight
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter

                    Behavior on opacity { NumberAnimation { duration: 80 } }
                    Behavior on color { ColorAnimation { duration: 80 } }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: cell.hovered = true
                    onExited: cell.hovered = false
                    onClicked: selector.switchWorkspace(cell.modelData)
                }
            }
        }
    }
}
