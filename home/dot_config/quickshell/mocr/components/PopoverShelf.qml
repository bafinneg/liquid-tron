import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../services" as Services

// Popover shelf: single full-width PanelWindow holding ALL popover content.
// Anchored below the bar. Right-side popovers stack from the right edge.
// Center popovers (power + calendar) are centered. Both groups share the
// same vertical alignment and coordinate space — no overlap possible.

PanelWindow {
    id: shelf

    property var stats: null
    property var _openList: []
    property int effectiveBarHeight: Geometry.barHeightCenter

    readonly property int _popW: 260
    readonly property int _popH: 200

    anchors {
        top: true
        left: true
        right: true
    }

    margins.top: 0
    exclusiveZone: 0
    color: "transparent"

    property bool _anyOpen: _openList.length > 0
    // Right-side only — excludes center popovers (power, calendar, mode) which
    // are too far left to overlap with the toast stack on DP-3.
    readonly property var _centerPopovers: ["power", "calendar", "mode"]
    readonly property bool _anyCenterOpen: {
        for (var i = 0; i < _openList.length; i++) {
            if (_centerPopovers.indexOf(_openList[i]) >= 0) return true
        }
        return false
    }
    readonly property bool _anyRightOpen: {
        for (var i = 0; i < _openList.length; i++) {
            if (_centerPopovers.indexOf(_openList[i]) < 0) return true
        }
        return false
    }
    // Read-only source-selection state for the owning Bar. The shelf retains
    // all open-list, interaction, and timing ownership.
    readonly property string activePopoverId: _openList.length > 0 ? _openList[_openList.length - 1] : ""
    property real revealProgress: 0

    onActivePopoverIdChanged: {
        revealAnimation.stop()
        revealProgress = 0

        if (activePopoverId !== "")
            revealAnimation.start()
    }

    NumberAnimation {
        id: revealAnimation
        target: shelf
        property: "revealProgress"
        from: 0
        to: 1
        duration: Motion.durationPopoverReveal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.sweep
    }

    visible: _anyOpen

    // Height = tallest possible popover + margin (346 = 340 notif + 6 gap)
    implicitHeight: _anyOpen ? 346 : 1

    // Clear the active popover before opening another so replacement is
    // deterministic across every popover route.
    function _dismissOtherGroup(popoverId) {
        _openList = []
    }

    // Cross-bar coordination: when another screen's shelf opens, close ours.
    readonly property string _screenName: shelf.screen ? shelf.screen.name : ""
    Connections {
        target: Services.NotificationService
        function onActivePopoverScreenChanged() {
            var active = Services.NotificationService.activePopoverScreen
            if (active !== "" && active !== shelf._screenName) {
                shelf._openList = []
            }
        }
    }

    function _claimScreen() {
        if (shelf._screenName !== "")
            Services.NotificationService.activePopoverScreen = shelf._screenName
    }

    function toggle(popoverId) {
        var idx = _openList.indexOf(popoverId)
        if (idx >= 0) {
            _openList = _openList.filter(function(x) { return x !== popoverId })
        } else {
            _claimScreen()
            _dismissOtherGroup(popoverId)
            _openList = _openList.concat([popoverId])
        }
    }

    function show(popoverId) {
        if (_openList.indexOf(popoverId) < 0) {
            _claimScreen()
            _dismissOtherGroup(popoverId)
            _openList = _openList.concat([popoverId])
        }
    }

    function dismissIfActive(popoverId) {
        if (activePopoverId === popoverId)
            _openList = []
    }

    function isOpen(popoverId) {
        return _openList.indexOf(popoverId) >= 0
    }

    readonly property var activePopoverChrome: {
        switch (activePopoverId) {
        case "notif": return notifChrome
        case "digest": return digestChrome
        case "vol": return volChrome
        case "net": return netChrome
        case "temp": return tempChrome
        case "mem": return memChrome
        case "gpu": return gpuChrome
        case "cpu": return cpuChrome
        case "power": return powerChrome
        case "calendar": return calendarChrome
        case "mode": return modeChrome
        default: return null
        }
    }

    Rectangle {
        id: activePopoverPlane
        visible: activePopoverChrome !== null && activePopoverChrome.popoverOpen
        x: activePopoverChrome ? activePopoverChrome.parent.x + activePopoverChrome.x : 0
        y: activePopoverChrome ? activePopoverChrome.parent.y + activePopoverChrome.y : 0
        width: activePopoverChrome ? activePopoverChrome.width : 0
        height: activePopoverChrome ? activePopoverChrome.height : 0
        opacity: shelf.revealProgress
        radius: 0
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: Geometry.radiusInteractive
        bottomRightRadius: Geometry.radiusInteractive
        color: Colors.bg_dark
        border.width: 0
        z: 0
    }

    // ── Right-side popovers (telemetry modules) ──────────────────────
    Row {
        id: rightRow
        y: 0
        anchors.right: parent.right
        anchors.rightMargin: Geometry.barPaddingOuter
        layoutDirection: Qt.RightToLeft
        spacing: 8
        z: 1

        PopoverChrome {
            id: notifChrome
            popoverOpen: shelf.isOpen("notif")
            popoverWidth: 300
            popoverHeight: 340
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("notif") }

            Loader {
                anchors.fill: parent
                anchors.margins: 8
                active: parent.popoverOpen
                source: "../popovers/NotificationList.qml"
            }
        }

        PopoverChrome {
            id: digestChrome
            popoverOpen: shelf.isOpen("digest")
            popoverWidth: 420
            popoverHeight: 340
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("digest") }

            Loader {
                anchors.fill: parent
                anchors.margins: 8
                active: parent.popoverOpen
                source: "../popovers/DigestView.qml"
            }
        }

        PopoverChrome {
            id: volChrome
            popoverOpen: shelf.isOpen("vol")
            popoverWidth: shelf._popW
            popoverHeight: 280
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("vol") }

            Loader {
                anchors.fill: parent
                anchors.margins: 8
                active: parent.popoverOpen
                source: "../popovers/VolumePicker.qml"
            }
        }

        PopoverChrome {
            id: netChrome
            popoverOpen: shelf.isOpen("net")
            popoverWidth: shelf._popW
            popoverHeight: shelf._popH
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("net") }

            Loader {
                anchors.fill: parent
                anchors.margins: 8
                active: parent.popoverOpen
                source: "../popovers/NetDetail.qml"
                onLoaded: if (item) item.stats = shelf.stats
            }
        }

        PopoverChrome {
            id: tempChrome
            popoverOpen: shelf.isOpen("temp")
            popoverWidth: shelf._popW
            popoverHeight: shelf._popH
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("temp") }

            Loader {
                anchors.fill: parent
                anchors.margins: 8
                active: parent.popoverOpen
                source: "../popovers/TempDetail.qml"
                onLoaded: if (item) item.stats = shelf.stats
            }
        }

        PopoverChrome {
            id: memChrome
            popoverOpen: shelf.isOpen("mem")
            popoverWidth: shelf._popW
            popoverHeight: shelf._popH
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("mem") }

            Loader {
                anchors.fill: parent
                anchors.margins: 8
                active: parent.popoverOpen
                source: "../popovers/MemDetail.qml"
                onLoaded: if (item) item.stats = shelf.stats
            }
        }

        PopoverChrome {
            id: gpuChrome
            popoverOpen: shelf.isOpen("gpu")
            popoverWidth: shelf._popW
            popoverHeight: shelf._popH
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("gpu") }

            Loader {
                anchors.fill: parent
                anchors.margins: 8
                active: parent.popoverOpen
                source: "../popovers/GpuDetail.qml"
            }
        }

        PopoverChrome {
            id: cpuChrome
            popoverOpen: shelf.isOpen("cpu")
            popoverWidth: shelf._popW
            popoverHeight: shelf._popH
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("cpu") }

            Loader {
                anchors.fill: parent
                anchors.margins: 8
                active: parent.popoverOpen
                source: "../popovers/CpuDetail.qml"
                onLoaded: if (item) item.stats = shelf.stats
            }
        }
    }

    // ── Center popovers (power + calendar + mode) ────────────────────
    Row {
        id: centerRow
        y: 0
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        z: 1

        PopoverChrome {
            id: powerChrome
            popoverOpen: shelf.isOpen("power")
            popoverWidth: shelf._popW
            popoverHeight: shelf._popH
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("power") }

            Loader {
                anchors.fill: parent
                anchors.margins: 8
                active: parent.popoverOpen
                source: "../popovers/PowerMenu.qml"
            }
        }

        PopoverChrome {
            id: calendarChrome
            popoverOpen: shelf.isOpen("calendar")
            popoverWidth: shelf._popW
            popoverHeight: shelf._popH
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("calendar") }

            Loader {
                anchors.fill: parent
                anchors.margins: 8
                active: parent.popoverOpen
                source: "../popovers/Calendar.qml"
            }
        }

        PopoverChrome {
            id: modeChrome
            popoverOpen: shelf.isOpen("mode")
            popoverWidth: 220
            popoverHeight: 72
            visible: popoverOpen
            width: popoverOpen ? popoverWidth : 0
            height: popoverOpen ? Math.round(popoverHeight * shelf.revealProgress) : 0
            color: "transparent"
            radius: 0
            border.width: 0
            border.color: "transparent"
            onAutoClose: function() { shelf.dismissIfActive("mode") }

            Row {
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    id: intelligentModeButton

                    readonly property bool selected: Services.SystemMode.mode === "intelligent"

                    width: 86
                    height: 36
                    radius: Geometry.radiusInteractive
                    color: selected ? Qt.alpha(Colors.cyan, 0.18)
                         : intelligentModeMouse.containsMouse ? Qt.alpha(Colors.cyan, 0.10)
                         : "transparent"
                    border.width: Geometry.borderWidth
                    border.color: selected ? Colors.cyan
                                 : intelligentModeMouse.containsMouse ? Qt.alpha(Colors.cyan, 0.45)
                                 : Colors.fg_dark

                    Text {
                        anchors.centerIn: parent
                        text: "INT"
                        color: intelligentModeButton.selected ? Colors.cyan : Colors.fg
                        font.family: Geometry.fontFamily
                        font.pixelSize: Geometry.fontSize
                        font.weight: Geometry.fontWeight
                    }

                    MouseArea {
                        id: intelligentModeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["system-mode-toggle", "intelligent"])
                            shelf.toggle("mode")
                        }
                    }
                }

                Rectangle {
                    id: gamingModeButton

                    readonly property bool selected: Services.SystemMode.gamingMode

                    width: 86
                    height: 36
                    radius: Geometry.radiusInteractive
                    color: selected ? Qt.alpha(Colors.amber, 0.20)
                         : gamingModeMouse.containsMouse ? Qt.alpha(Colors.amber, 0.12)
                         : "transparent"
                    border.width: Geometry.borderWidth
                    border.color: selected ? Colors.amber
                                 : gamingModeMouse.containsMouse ? Qt.alpha(Colors.amber, 0.45)
                                 : Colors.fg_dark

                    Text {
                        anchors.centerIn: parent
                        text: "GAME"
                        color: gamingModeButton.selected ? Colors.amber : Colors.fg
                        font.family: Geometry.fontFamily
                        font.pixelSize: Geometry.fontSize
                        font.weight: Geometry.fontWeight
                    }

                    MouseArea {
                        id: gamingModeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["system-mode-toggle", "gaming"])
                            shelf.toggle("mode")
                        }
                    }
                }
            }
        }
    }
}
