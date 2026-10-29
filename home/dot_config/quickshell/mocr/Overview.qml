import Quickshell
import Quickshell.Wayland
import Quickshell.Wayland._Screencopy
import Quickshell.Hyprland
import QtQuick
import "theme"
import "services" as Services

// Global workspace overview — spatial 3×6 monitor wall.
// Columns follow physical monitor x-position; rows are each monitor's local
// workspace stack 1..6. Every navigation target resolves from a live
// (monitor identity, local positive slot) pair; no global-ordinal fallback.
PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mocr-overview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    visible: false

    readonly property int _outerMargin: 20
    readonly property int _framePaddingX: 24
    readonly property int _framePaddingY: 24
    readonly property int _headerHeight: 34
    readonly property int _headerGap: 18
    readonly property int _planeSpacing: 18
    readonly property int _planePadding: 12
    readonly property int _planeHeaderHeight: 18
    readonly property int _planeHeaderGap: 9
    readonly property int _tileSpacing: 9
    readonly property int _workspaceRows: 6
    readonly property int _wallColumns: Math.max(1, monitorColumns.length)
    readonly property int _monitorMinY: {
        var mons = root.monitorColumns
        if (mons.length === 0) return 0
        var minY = mons[0].y
        for (var i = 1; i < mons.length; i++) minY = Math.min(minY, mons[i].y)
        return minY
    }
    readonly property int _monitorMaxY: {
        var mons = root.monitorColumns
        if (mons.length === 0) return 0
        var maxY = mons[0].y
        for (var i = 1; i < mons.length; i++) maxY = Math.max(maxY, mons[i].y)
        return maxY
    }
    readonly property int _monitorYRange: Math.max(0, _monitorMaxY - _monitorMinY)
    readonly property int _planeYOffsetSpread: Math.min(32, Math.round(_monitorYRange / 12))
    readonly property int _availableWidth: root.screen ? root.screen.width : root.width
    readonly property int _availableHeight: root.screen ? root.screen.height : root.height
    readonly property int _frameBudgetW: Math.max(1, _availableWidth - 2 * _outerMargin)
    readonly property int _frameBudgetH: Math.max(1, _availableHeight - 2 * _outerMargin)
    readonly property int _tileWidthBudget: Math.floor((_frameBudgetW
        - 2 * _framePaddingX
        - Math.max(0, _wallColumns - 1) * _planeSpacing
        - _wallColumns * 2 * _planePadding) / _wallColumns)
    readonly property int _tileHeightBudget: Math.floor((_frameBudgetH
        - 2 * _framePaddingY
        - _headerHeight
        - _headerGap
        - _planeYOffsetSpread
        - 2 * _planePadding
        - _planeHeaderHeight
        - _planeHeaderGap
        - Math.max(0, _workspaceRows - 1) * _tileSpacing) / _workspaceRows)
    readonly property int _tileWidth: Math.max(1, Math.floor(Math.min(500, _tileWidthBudget, _tileHeightBudget / 0.54)))
    readonly property int _tileHeight: Math.max(1, Math.floor(Math.min(_tileWidth * 0.54, _tileHeightBudget)))
    readonly property int _planeWidth: _tileWidth + 2 * _planePadding
    readonly property int _planeHeight: 2 * _planePadding + _planeHeaderHeight + _planeHeaderGap
        + _workspaceRows * _tileHeight + Math.max(0, _workspaceRows - 1) * _tileSpacing
    readonly property int _wallWidth: _wallColumns * _planeWidth + Math.max(0, _wallColumns - 1) * _planeSpacing
    readonly property int _wallHeight: _planeHeight + _planeYOffsetSpread
    readonly property int _frameWidth: 2 * _framePaddingX + _wallWidth
    readonly property int _frameHeight: 2 * _framePaddingY + _headerHeight + _headerGap + _wallHeight
    readonly property bool _layoutFits: monitorColumns.length > 0
        && _tileWidthBudget >= 120
        && _tileHeightBudget >= 64
        && _frameWidth <= _frameBudgetW
        && _frameHeight <= _frameBudgetH
    readonly property string focusedMonitorMarker: {
        var mon = Hyprland.focusedMonitor
        return mon ? root.monitorRole(mon) : "—"
    }
    readonly property bool anyFullscreen: {
        var vals = Hyprland.workspaces.values
        for (var i = 0; i < vals.length; i++) {
            if (vals[i] && vals[i].hasFullscreen) return true
        }
        return false
    }
    // PresenceState and PowerProfile are existing authoritative producers.
    readonly property bool sceneSuppressed: root.anyFullscreen
        || Services.SystemMode.gamingMode
        || Services.PresenceState.absent
        || Services.PowerProfile.powerSaving

    property int selectedCol: 0
    property int selectedRow: 0

    readonly property var monitorColumns: {
        var vals = Hyprland.monitors.values
        var arr = []
        for (var i = 0; i < vals.length; i++) {
            var m = vals[i]
            if (m && m.name) arr.push(m)
        }
        arr.sort(function(a, b) { return a.x - b.x })
        return arr
    }

    function monitorRole(mon) {
        var mons = root.monitorColumns
        var index = mons.indexOf(mon)
        return ["L", "C", "R"][index] || "M"
    }

    function monitorYOffset(mon) {
        if (!mon || root._monitorYRange <= 0) return 0
        return Math.round(((mon.y - root._monitorMinY) / root._monitorYRange) * root._planeYOffsetSpread)
    }

    function tileXFor(col) {
        return col * (root._planeWidth + root._planeSpacing) + root._planePadding
    }

    function tileYFor(col, row) {
        var mons = root.monitorColumns
        var mon = col >= 0 && col < mons.length ? mons[col] : null
        return root.monitorYOffset(mon)
            + root._planePadding
            + root._planeHeaderHeight
            + root._planeHeaderGap
            + row * (root._tileHeight + root._tileSpacing)
    }

    function localNumber(workspace) {
        if (!workspace || workspace.id < 1 || !workspace.monitor) return -1
        var vals = Hyprland.workspaces.values
        var locals = []
        for (var i = 0; i < vals.length; i++) {
            var candidate = vals[i]
            if (candidate && candidate.id >= 1 && candidate.monitor
                    && candidate.monitor.name === workspace.monitor.name) {
                locals.push(candidate)
            }
        }
        locals.sort(function(a, b) { return a.id - b.id })
        return locals.indexOf(workspace) + 1
    }

    function screenForName(name) {
        for (var i = 0; i < Quickshell.screens.length; i++) {
            var s = Quickshell.screens[i]
            if (s.name === name) return s
        }
        return null
    }

    function wsForMonitorLocal(monName, local) {
        var vals = Hyprland.workspaces.values
        for (var i = 0; i < vals.length; i++) {
            var w = vals[i]
            if (w && w.id >= 1 && w.monitor && w.monitor.name === monName
                    && root.localNumber(w) === local) {
                return w
            }
        }
        return null
    }

    function workspaceIdForCell(col, row) {
        var mons = root.monitorColumns
        if (col >= 0 && col < mons.length) {
            var ws = root.wsForMonitorLocal(mons[col].name, row + 1)
            if (ws) return ws.id
        }
        return -1
    }

    function activeRowForMonitor(mon) {
        if (!mon || !mon.activeWorkspace) return 0
        var local = root.localNumber(mon.activeWorkspace)
        return local >= 1 ? local - 1 : 0
    }

    function syncSelectionToFocus() {
        var mons = root.monitorColumns
        var focused = Hyprland.focusedMonitor
        var col = 0
        for (var i = 0; i < mons.length; i++) {
            if (focused && mons[i].name === focused.name) {
                col = i
                break
            }
        }
        root.selectedCol = Math.max(0, Math.min(col, Math.max(0, mons.length - 1)))
        root.selectedRow = root.activeRowForMonitor(mons[root.selectedCol])
    }

    function dispatchCell(col, row) {
        var id = root.workspaceIdForCell(col, row)
        if (id < 1 || root.sceneSuppressed) return
        Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + String(id) + "\" })")
        root.closeAnimated()
    }

    function open() {
        if (root.sceneSuppressed) {
            root.close()
            return
        }
        var mon = Hyprland.focusedMonitor
        if (mon) root.screen = root.screenForName(mon.name)
        if (!root._layoutFits) {
            root.close()
            return
        }
        root.syncSelectionToFocus()
        backdrop.opacity = 0.0
        gridFrame.opacity = 0.0
        gridFrame.scale = 0.96
        root.visible = true
        focusCatcher.forceActiveFocus()
        openBackdropAnim.start()
        openGridAnim.start()
    }

    function close() {
        root.visible = false
        backdrop.opacity = 0.0
        gridFrame.opacity = 0.0
        gridFrame.scale = 0.96
    }

    function closeAnimated() {
        closeAnim.start()
    }

    onSceneSuppressedChanged: {
        if (sceneSuppressed && root.visible) root.close()
    }

    NumberAnimation {
        id: openBackdropAnim
        target: backdrop
        property: "opacity"
        from: 0.0; to: 1.0
        duration: Motion.durationSystemMapEntry
        easing.type: Easing.OutCubic
    }

    ParallelAnimation {
        id: openGridAnim
        NumberAnimation {
            target: gridFrame
            property: "opacity"
            from: 0.0; to: 1.0
            duration: Motion.durationSystemMapEntry
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.sweep
        }
        NumberAnimation {
            target: gridFrame
            property: "scale"
            from: 0.96; to: 1.0
            duration: Motion.durationSystemMapEntry
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.sweep
        }
    }

    ParallelAnimation {
        id: closeAnim
        NumberAnimation {
            target: backdrop
            property: "opacity"
            from: backdrop.opacity; to: 0.0
            duration: Motion.durationSystemMapExit
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: gridFrame
            property: "opacity"
            from: gridFrame.opacity; to: 0.0
            duration: Motion.durationSystemMapExit
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decay
        }
        NumberAnimation {
            target: gridFrame
            property: "scale"
            from: gridFrame.scale; to: 0.96
            duration: Motion.durationSystemMapExit
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decay
        }
        onFinished: root.close()
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        // The surrounding void is intentionally near-black; the system map is
        // the only raised object in the overlay.
        color: Colors.bg_dark
        opacity: 0.0

        Item {
            id: focusCatcher
            anchors.fill: parent
            focus: root.visible
            Keys.onPressed: function(event) {
                if (!root.visible) return
                var mons = root.monitorColumns
                var maxCol = Math.max(0, mons.length - 1)
                if (event.key === Qt.Key_Left) {
                    root.selectedCol = Math.max(0, root.selectedCol - 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    root.selectedCol = Math.min(maxCol, root.selectedCol + 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    root.selectedRow = Math.max(0, root.selectedRow - 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    root.selectedRow = Math.min(root._workspaceRows - 1, root.selectedRow + 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    root.dispatchCell(root.selectedCol, root.selectedRow)
                    event.accepted = true
                } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
                    root.selectedRow = event.key - Qt.Key_1
                    root.dispatchCell(root.selectedCol, root.selectedRow)
                    event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                    root.closeAnimated()
                    event.accepted = true
                }
            }
        }

        // The scene owns its explicit outside-click exit. It sits beneath the
        // composed wall, whose tile handlers retain navigation ownership.
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeAnimated()
        }

        // This is the single composed object animated by the open/close paths.
        Item {
            id: gridFrame
            z: 1
            anchors.centerIn: parent
            width: root._frameWidth
            height: root._frameHeight
            opacity: 0.0
            scale: 0.96
            transformOrigin: Item.Center

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Qt.alpha(Colors.bg_dark, 0.96)
                border.color: Qt.alpha(Colors.cyan, 0.62)
                border.width: Geometry.borderWidth
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 6
                color: Qt.alpha(Colors.bg_alt, 0.64)
                border.color: Qt.alpha(Colors.blue, 0.22)
                border.width: Geometry.borderWidth
            }

            Rectangle {
                id: systemHeader
                x: root._framePaddingX
                y: root._framePaddingY
                width: root._wallWidth
                height: root._headerHeight
                radius: 4
                color: Qt.alpha(Colors.bg_dark, 0.90)
                border.color: Qt.alpha(Colors.cyan, 0.38)
                border.width: Geometry.borderWidth

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SYSTEM MAP"
                    color: Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: 14
                    font.weight: Geometry.fontWeight
                    font.letterSpacing: 1.6
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "PLANE [" + root.focusedMonitorMarker + "]"
                    color: Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: 11
                    font.weight: Geometry.fontWeight
                    font.letterSpacing: 1.0
                }
            }

            Item {
                id: monitorWall
                x: root._framePaddingX
                y: root._framePaddingY + root._headerHeight + root._headerGap
                width: root._wallWidth
                height: root._wallHeight

                Repeater {
                    model: root.monitorColumns

                    Rectangle {
                        id: monPlane
                        required property var modelData
                        required property int index
                        readonly property bool focusedColumn: Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === modelData.name

                        x: monPlane.index * (root._planeWidth + root._planeSpacing)
                        y: root.monitorYOffset(monPlane.modelData)
                        width: root._planeWidth
                        height: root._planeHeight
                        radius: 6
                        color: Qt.alpha(Colors.bg_alt, focusedColumn ? 0.84 : 0.66)
                        border.color: focusedColumn ? Qt.alpha(Colors.cyan, 0.78) : Qt.alpha(Colors.cyan, 0.34)
                        border.width: focusedColumn ? Geometry.borderWidthAccent : Geometry.borderWidth

                        Behavior on y {
                            NumberAnimation {
                                duration: Motion.durationSystemMapTraverse
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Motion.decay
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 4
                            color: Qt.alpha(Colors.bg_dark, 0.34)
                            border.color: Qt.alpha(Colors.blue, 0.18)
                            border.width: Geometry.borderWidth
                        }

                        Column {
                            id: columnStack
                            anchors.fill: parent
                            anchors.margins: root._planePadding
                            spacing: root._tileSpacing

                            Text {
                                height: root._planeHeaderHeight
                                width: root._tileWidth
                                text: "PLANE " + root.monitorRole(monPlane.modelData)
                                color: monPlane.focusedColumn ? Colors.cyan : Qt.alpha(Colors.cyan, 0.72)
                                font.family: Geometry.fontFamily
                                font.pixelSize: 11
                                font.weight: Geometry.fontWeight
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            Item {
                                width: 1
                                height: root._planeHeaderGap - root._tileSpacing
                            }

                            Repeater {
                                model: [1, 2, 3, 4, 5, 6]

                                Item {
                                    id: tile
                                    required property int modelData
                                    required property int index

                                    readonly property int rowIndex: tile.index
                                    readonly property int colIndex: monPlane.index
                                    property var wsObj: root.wsForMonitorLocal(monPlane.modelData.name, tile.modelData)
                                    property int workspaceId: wsObj ? wsObj.id : -1
                                    property var hostMon: wsObj ? wsObj.monitor : monPlane.modelData
                                    property bool isActive: hostMon !== null && hostMon.activeWorkspace !== null
                                                            && hostMon.activeWorkspace.id === tile.workspaceId
                                    property bool isSelected: root.selectedCol === tile.colIndex && root.selectedRow === tile.rowIndex
                                    property bool focusedActive: tile.isActive && monPlane.focusedColumn
                                    property bool _hovered: false
                                    readonly property int toplevelCount: tile.wsObj && tile.wsObj.toplevels
                                        ? tile.wsObj.toplevels.values.length : 0

                                    width: root._tileWidth
                                    height: root._tileHeight
                                    z: isSelected ? 4 : 1

                                    Rectangle {
                                        id: tileField
                                        anchors.fill: parent
                                        radius: 4
                                        // Blue is reserved for traversal selection. Amber only
                                        // appears as the single active-location marker below.
                                        color: tile.isSelected
                                            ? Qt.alpha(Colors.blue, 0.32)
                                            : tile._hovered ? Qt.alpha(Colors.cyan, 0.08) : Qt.alpha(Colors.bg_dark, 0.58)
                                        border.color: tile.isSelected
                                            ? Qt.alpha(Colors.cyan, 0.86)
                                            : (tile._hovered ? Qt.alpha(Colors.cyan, 0.72) : Qt.alpha(Colors.cyan, 0.32))
                                        border.width: tile.isSelected ? Geometry.borderWidthAccent : Geometry.borderWidth

                                        Behavior on color { ColorAnimation { duration: Motion.durationSystemMapTraverse } }
                                        Behavior on border.color { ColorAnimation { duration: Motion.durationSystemMapTraverse } }
                                    }

                                    // Live workspace content. Each window keeps its compositor
                                    // geometry inside the monitor-scaled tile; no workspace is
                                    // activated merely to collect pixels. Capture handles exist
                                    // only while System Map itself is visible.
                                    Item {
                                        id: windowMap
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        anchors.topMargin: 18
                                        anchors.bottomMargin: 20
                                        clip: true
                                        opacity: tile.isSelected || tile.focusedActive ? 1.0 : 0.82

                                        Repeater {
                                            model: tile.wsObj ? tile.wsObj.toplevels : null

                                            Rectangle {
                                                id: windowPreviewFrame
                                                required property int index
                                                required property var modelData

                                                readonly property var ipc: modelData ? modelData.lastIpcObject : null
                                                readonly property bool geometryValid: Boolean(tile.hostMon
                                                    && tile.hostMon.width > 0 && tile.hostMon.height > 0
                                                    && ipc && ipc.at && ipc.size
                                                    && ipc.at.length >= 2 && ipc.size.length >= 2
                                                    && ipc.size[0] > 0 && ipc.size[1] > 0)
                                                readonly property string applicationClass: ipc && ipc.class
                                                    ? String(ipc.class).toUpperCase() : "APPLICATION"
                                                readonly property real scaledX: geometryValid
                                                    ? (ipc.at[0] - tile.hostMon.x) / tile.hostMon.width * windowMap.width : 0
                                                readonly property real scaledY: geometryValid
                                                    ? (ipc.at[1] - tile.hostMon.y) / tile.hostMon.height * windowMap.height : 0
                                                readonly property real scaledW: geometryValid
                                                    ? ipc.size[0] / tile.hostMon.width * windowMap.width : windowMap.width * 0.42
                                                readonly property real scaledH: geometryValid
                                                    ? ipc.size[1] / tile.hostMon.height * windowMap.height : windowMap.height * 0.42

                                                x: geometryValid
                                                    ? Math.max(0, Math.min(windowMap.width - 24, Math.round(scaledX)))
                                                    : 6 + (index % 2) * Math.round(windowMap.width * 0.44)
                                                y: geometryValid
                                                    ? Math.max(0, Math.min(windowMap.height - 18, Math.round(scaledY)))
                                                    : 6 + Math.floor(index / 2) * Math.round(windowMap.height * 0.44)
                                                width: Math.max(24, Math.min(windowMap.width - x, Math.round(scaledW)))
                                                height: Math.max(18, Math.min(windowMap.height - y, Math.round(scaledH)))
                                                radius: 2
                                                color: Qt.alpha(Colors.bg_inset, 0.82)
                                                border.color: Qt.alpha(Colors.cyan, tile.isSelected ? 0.70 : 0.42)
                                                border.width: Geometry.borderWidth
                                                clip: true

                                                // Truthful class fallback sits beneath live pixels.
                                                // It remains available during geometry/capture warm-up
                                                // and is naturally covered once Screencopy has content.
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    height: Math.min(16, parent.height)
                                                    color: Qt.alpha(Colors.bg_dark, 0.72)
                                                    visible: parent.height >= 12

                                                    Text {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 4
                                                        anchors.rightMargin: 4
                                                        text: windowPreviewFrame.applicationClass
                                                        color: Qt.alpha(Colors.white, 0.88)
                                                        font.family: Geometry.fontFamily
                                                        font.pixelSize: 8
                                                        font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                }

                                                ScreencopyView {
                                                    id: livePreview
                                                    anchors.fill: parent
                                                    anchors.margins: Geometry.borderWidth
                                                    captureSource: root.visible && windowPreviewFrame.modelData
                                                        && windowPreviewFrame.modelData.wayland
                                                        ? windowPreviewFrame.modelData.wayland : null
                                                    live: captureSource !== null
                                                    paintCursor: false
                                                    constraintSize: Qt.size(Math.max(1, width), Math.max(1, height))
                                                    opacity: hasContent ? 1.0 : 0.0
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: tile.toplevelCount === 0
                                        text: tile.workspaceId >= 1 ? "EMPTY" : "UNMAPPED"
                                        color: Qt.alpha(Colors.cyan, tile.workspaceId >= 1 ? 0.54 : 0.30)
                                        font.family: Geometry.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        font.letterSpacing: 1.1
                                    }

                                    Rectangle {
                                        visible: tile.focusedActive
                                        width: 10
                                        height: 10
                                        radius: 2
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 7
                                        rotation: 45
                                        color: Colors.amber
                                        opacity: 0.92
                                        z: 9
                                    }

                                    // Navigation state remains legible above arbitrary live
                                    // application pixels.
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 4
                                        color: "transparent"
                                        border.color: tile.isSelected
                                            ? Qt.alpha(Colors.cyan, 0.90)
                                            : (tile._hovered ? Qt.alpha(Colors.cyan, 0.74) : "transparent")
                                        border.width: tile.isSelected ? Geometry.borderWidthAccent : Geometry.borderWidth
                                        z: 8
                                    }

                                    Text {
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.margins: 6
                                        text: "SLOT " + String(tile.modelData)
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        color: tile.isSelected ? Colors.cyan : Qt.alpha(Colors.cyan, 0.76)
                                    }

                                    Text {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.margins: 4
                                        text: String(tile.modelData)
                                        font.pixelSize: 9
                                        color: Qt.alpha(Colors.cyan, 0.78)
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onEntered: tile._hovered = true
                                        onExited: tile._hovered = false
                                        onClicked: root.dispatchCell(tile.colIndex, tile.rowIndex)
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: traversalCursor
                    visible: root.workspaceIdForCell(root.selectedCol, root.selectedRow) >= 1
                    x: root.tileXFor(root.selectedCol)
                    y: root.tileYFor(root.selectedCol, root.selectedRow)
                    width: root._tileWidth
                    height: root._tileHeight
                    radius: 5
                    color: "transparent"
                    border.width: Geometry.borderWidthAccent
                    border.color: Qt.alpha(Colors.cyan, 0.94)
                    z: 20

                    Behavior on x {
                        NumberAnimation {
                            duration: Motion.durationSystemMapTraverse
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.decay
                        }
                    }
                    Behavior on y {
                        NumberAnimation {
                            duration: Motion.durationSystemMapTraverse
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.decay
                        }
                    }
                    Behavior on width {
                        NumberAnimation {
                            duration: Motion.durationSystemMapTraverse
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.decay
                        }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: Motion.durationSystemMapTraverse
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.decay
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.visible
        onCleared: root.close()
    }

    Shortcut {
        sequences: ["Escape"]
        enabled: root.visible
        onActivated: root.closeAnimated()
    }

    Connections {
        target: Services.WorkspacesService
        function onOverviewToggleRequested() {
            if (root.visible)
                root.closeAnimated()
            else
                root.open()
        }
    }
}
