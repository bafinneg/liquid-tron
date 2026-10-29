import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "../theme"
import "../components"
import "../services" as Services

// FEAT-workspace-split-monitor: compact 6-cell monitor-local workspace bar.
// Each physical monitor renders its own local workspace stack. Hyprland still
// exposes plugin-managed global workspace IDs; localNumber() maps those IDs to
// the user-facing 1..6 namespace.
Item {
    id: root

    property var screen: null

    implicitHeight: Geometry.barHeightCenter
    implicitWidth: workspaceRow.implicitWidth

    readonly property int glyphFontSize: 18
    readonly property int nameFontSize: 12
    readonly property int workspaceCount: 6

    property int previousLocalActive: -1
    property real edgeLineOpacity: 0.0

    readonly property var monitor: {
        if (!root.screen) return null
        var vals = Hyprland.workspaces.values
        for (var i = 0; i < vals.length; i++) {
            var w = vals[i]
            if (w && w.monitor && w.monitor.name === root.screen.name) return w.monitor
        }
        return null
    }

    readonly property int activeWorkspaceId: {
        if (!root.monitor) return -1
        var w = root.monitor.activeWorkspace
        return w ? w.id : -1
    }

    readonly property int localActiveWorkspace: root.localNumber(root.activeWorkspaceId)

    readonly property int monitorWorkspaceCount: {
        if (!root.screen) return 0
        var vals = Hyprland.workspaces.values
        var n = 0
        for (var i = 0; i < vals.length; i++) {
            var w = vals[i]
            if (w && w.id >= 1 && w.monitor && w.monitor.name === root.screen.name) n++
        }
        return n
    }

    function localNumber(globalId) {
        if (globalId < 1) return -1
        return ((globalId - 1) % root.workspaceCount) + 1
    }

    onLocalActiveWorkspaceChanged: {
        if (root.previousLocalActive >= 1
                && root.localActiveWorkspace >= 1
                && root.localActiveWorkspace !== root.previousLocalActive) {
            edgeLineAnim.restart()
        }
        root.previousLocalActive = root.localActiveWorkspace
    }

    SequentialAnimation {
        id: edgeLineAnim
        NumberAnimation { target: root; property: "edgeLineOpacity"; to: 1.0; duration: 100 }
        NumberAnimation { target: root; property: "edgeLineOpacity"; to: 0.0; duration: 200 }
    }

    Row {
        id: workspaceRow
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Repeater {
            model: [1, 2, 3, 4, 5, 6]

            Item {
                id: wsCell
                required property int modelData
                required property int index

                readonly property bool active: root.localActiveWorkspace === wsCell.modelData
                property bool hovered: false
                property real extraWidth: wsCell.hovered ? nameLabel.implicitWidth + 3 : 0

                width: cellContent.implicitWidth + Geometry.barPaddingModule * 2 +
                       (wsCell.index > 0 ? Geometry.borderWidth : 0) + wsCell.extraWidth
                height: root.implicitHeight
                clip: true

                Behavior on extraWidth {
                    NumberAnimation { duration: wsCell.hovered ? 120 : 80; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    color: wsCell.active
                        ? Qt.alpha(Colors.amber, wsCell.hovered ? 0.14 : 0.09)
                        : wsCell.hovered ? Qt.alpha(Colors.cyan, 0.08) : "transparent"
                    z: 0
                    Behavior on color { ColorAnimation { duration: 90 } }
                }

                Rectangle {
                    visible: wsCell.index > 0
                    width: Geometry.borderWidth
                    height: parent.height
                    color: Colors.fg_dark
                    anchors.left: parent.left
                    z: 1
                }

                Row {
                    id: cellContent
                    spacing: 3
                    anchors.left: parent.left
                    anchors.leftMargin: (wsCell.index > 0 ? Geometry.borderWidth : 0) + Geometry.barPaddingModule
                    anchors.verticalCenter: parent.verticalCenter
                    z: 2

                    Text {
                        text: WorkspaceGlyphs.glyphFor(wsCell.modelData)
                        color: wsCell.active ? Colors.amber : Colors.cyan
                        font.family: Geometry.fontFamily
                        font.pixelSize: root.glyphFontSize
                        font.weight: Geometry.fontWeight
                        verticalAlignment: Text.AlignVCenter
                        Behavior on color { ColorAnimation { duration: 90 } }
                    }
                }

                Text {
                    id: nameLabel
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: cellContent.right
                    anchors.leftMargin: 3
                    text: String(wsCell.modelData) + " · " + WorkspaceGlyphs.nameFor(wsCell.modelData)
                    opacity: wsCell.hovered ? 1.0 : 0.0
                    color: wsCell.active ? Colors.amber : Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: root.nameFontSize
                    font.weight: Geometry.fontWeight
                    z: 2
                    Behavior on opacity { NumberAnimation { duration: 80 } }
                    Behavior on color { ColorAnimation { duration: 90 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    z: 3
                    onEntered: wsCell.hovered = true
                    onExited: wsCell.hovered = false
                    onClicked: {
                        splitWorkspaceProc.command = ["hyprctl", "dispatch", "function() return hl.plugin.split_monitor_workspaces.workspace(\"" + String(wsCell.modelData) + "\") end"]
                        splitWorkspaceProc.running = true
                    }
                }

                Process { id: splitWorkspaceProc }
            }
        }
    }

    // One continuous command-deck rail keeps the local three-cell selector
    // visually anchored without changing the cell interaction model.
    Rectangle {
        visible: root.screen && root.screen.name === "DP-3"
        anchors.left: parent.left
        anchors.right: workspaceRow.right
        anchors.bottom: parent.bottom
        height: Geometry.borderWidth
        color: Colors.cyan
        z: 4
    }

    Rectangle {
        id: edgeLine
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Colors.amber
        opacity: root.edgeLineOpacity
        visible: root.edgeLineOpacity > 0.001
        z: 6
    }

    Item {
        id: stateBadge
        visible: root.monitorWorkspaceCount !== root.workspaceCount
        anchors.left: workspaceRow.right
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: stateLabel.implicitWidth
        implicitHeight: stateLabel.implicitHeight

        Text {
            id: stateLabel
            text: root.monitorWorkspaceCount + "/" + root.workspaceCount
            color: Qt.alpha(Colors.cyan, 0.45)
            font.family: Geometry.fontFamily
            font.pixelSize: 11
            font.weight: Geometry.fontWeight
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Services.WorkspacesService.dumpState()
        }
    }
}
