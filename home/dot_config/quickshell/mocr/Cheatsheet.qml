import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "theme"

// Keybind cheatsheet overlay — FEAT-liquid-tron-desktop-polish-2 C3.
PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mocr-cheatsheet"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: false

    property var binds: []
    property var categories: []
    property string _bindsJsonBuffer: ""

    function screenForName(name) {
        for (var i = 0; i < Quickshell.screens.length; i++) {
            var s = Quickshell.screens[i]
            if (s.name === name) return s
        }
        return null
    }

    function modLabel(modmask) {
        var bits = []
        if (modmask & 64) bits.push("SUPER")
        if (modmask & 4) bits.push("CTRL")
        if (modmask & 8) bits.push("ALT")
        if (modmask & 1) bits.push("SHIFT")
        return bits.join("+")
    }

    function keyLabel(entry) {
        var mods = root.modLabel(entry.modmask || 0)
        var key = entry.key || entry.keycode || "?"
        return mods.length > 0 ? mods + "+" + key : key
    }

    function categoryFor(description) {
        if (!description || description.length === 0) return "OTHER"
        var idx = description.indexOf(": ")
        return idx > 0 ? description.slice(0, idx) : "OTHER"
    }

    function labelFor(description, dispatcher, arg) {
        if (description && description.length > 0) {
            var idx = description.indexOf(": ")
            return idx > 0 ? description.slice(idx + 2) : description
        }
        var fallback = dispatcher || "bind"
        if (arg && arg.length > 0) fallback += " " + arg
        return fallback
    }

    function rebuild(parsed) {
        var grouped = ({})
        for (var i = 0; i < parsed.length; i++) {
            var e = parsed[i]
            var desc = e.description || ""
            var cat = root.categoryFor(desc)
            if (!grouped[cat]) grouped[cat] = []
            grouped[cat].push({
                key: root.keyLabel(e),
                description: root.labelFor(desc, e.dispatcher || "", e.arg || ""),
                described: desc.length > 0
            })
        }
        var order = ["Launch", "Session", "Window", "Focus", "Move", "Workspace", "Monitor", "Group", "Capture", "Media", "Clipboard", "Overlay", "OTHER"]
        var out = []
        for (var j = 0; j < order.length; j++) {
            if (grouped[order[j]]) out.push({ name: order[j], rows: grouped[order[j]] })
        }
        for (var k in grouped) {
            if (order.indexOf(k) < 0) out.push({ name: k, rows: grouped[k] })
        }
        root.categories = out
    }

    function refreshBinds() {
        bindsProc.running = false
        root._bindsJsonBuffer = ""
        bindsProc.running = true
    }

    function open() {
        var mon = Hyprland.focusedMonitor
        if (mon) root.screen = root.screenForName(mon.name)
        root.refreshBinds()
        backdrop.opacity = 0.0
        card.opacity = 0.0
        card.scale = 0.97
        root.visible = true
        focusCatcher.forceActiveFocus()
        openBackdropAnim.start()
        openCardAnim.start()
    }

    function close() {
        root.visible = false
        backdrop.opacity = 0.0
        card.opacity = 0.0
        card.scale = 0.97
    }

    function closeAnimated() {
        closeAnim.start()
    }

    function toggleVisible() {
        if (root.visible) root.closeAnimated()
        else root.open()
    }

    IpcHandler {
        target: "cheatsheet"
        function toggle() { root.toggleVisible() }
    }

    Process {
        id: bindsProc
        running: false
        command: ["hyprctl", "binds", "-j"]
        stdout: SplitParser {
            onRead: function(data) {
                root._bindsJsonBuffer += data + "\n"
            }
        }
        onExited: {
            try {
                var parsed = JSON.parse(root._bindsJsonBuffer)
                if (parsed) root.rebuild(parsed)
            } catch (e) {
                console.warn("Cheatsheet failed to parse hyprctl binds JSON: " + e)
            }
        }
    }

    NumberAnimation {
        id: openBackdropAnim
        target: backdrop
        property: "opacity"
        from: 0.0; to: 1.0
        duration: 150
        easing.type: Easing.OutCubic
    }

    ParallelAnimation {
        id: openCardAnim
        NumberAnimation {
            target: card
            property: "opacity"
            from: 0.0; to: 1.0
            duration: Motion.durationTween
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.sweep
        }
        NumberAnimation {
            target: card
            property: "scale"
            from: 0.97; to: 1.0
            duration: Motion.durationTween
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
            duration: 120
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: card
            property: "opacity"
            from: card.opacity; to: 0.0
            duration: 120
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decay
        }
        NumberAnimation {
            target: card
            property: "scale"
            from: card.scale; to: 0.97
            duration: 120
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decay
        }
        onFinished: root.close()
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.alpha(Colors.bg, 0.88)
        opacity: 0.0

        Item {
            id: focusCatcher
            anchors.fill: parent
            focus: root.visible
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    root.closeAnimated()
                    event.accepted = true
                }
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.82, 3000)
            height: Math.min(parent.height * 0.78, 1700)
            radius: Geometry.radiusChrome
            color: Qt.alpha(Colors.bg_inset, 0.94)
            border.color: Qt.alpha(Colors.cyan, 0.42)
            border.width: 1
            opacity: 0.0
            scale: 0.97
            transformOrigin: Item.Center

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 18

                Text {
                    text: "KEYBIND CHEATSHEET"
                    color: Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: 24
                    font.letterSpacing: 3
                    font.weight: Font.DemiBold
                }

                Flow {
                    width: parent.width
                    height: parent.height - 56
                    spacing: 18

                    Repeater {
                        model: root.categories
                        delegate: Rectangle {
                            required property var modelData
                            width: Math.floor((card.width - 56 - 54) / 4)
                            height: Math.min(520, header.implicitHeight + rows.implicitHeight + 24)
                            radius: 10
                            color: Qt.alpha(Colors.bg_dark, 0.64)
                            border.color: Qt.alpha(Colors.fg_dark, 0.45)
                            border.width: 1

                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                Text {
                                    id: header
                                    text: modelData.name
                                    color: modelData.name === "OTHER" ? Colors.fg_dim : Colors.cyan
                                    font.family: Geometry.fontFamily
                                    font.pixelSize: 13
                                    font.letterSpacing: 2
                                    font.weight: Font.DemiBold
                                }

                                Column {
                                    id: rows
                                    width: parent.width
                                    spacing: 6

                                    Repeater {
                                        model: modelData.rows
                                        delegate: Row {
                                            required property var modelData
                                            width: rows.width
                                            spacing: 8

                                            Rectangle {
                                                width: 118
                                                height: 24
                                                radius: 6
                                                color: Qt.alpha(Colors.amber, 0.12)
                                                border.color: Qt.alpha(Colors.amber, 0.24)
                                                border.width: 1
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.key
                                                    color: Colors.amber
                                                    font.family: Geometry.fontFamily
                                                    font.pixelSize: 10
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                    width: parent.width - 8
                                                    horizontalAlignment: Text.AlignHCenter
                                                }
                                            }

                                            Text {
                                                width: rows.width - 126
                                                text: modelData.description
                                                color: modelData.described ? Colors.fg : Colors.fg_dim
                                                font.family: Geometry.fontFamily
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
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
}
