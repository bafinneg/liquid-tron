import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

PanelWindow {
    id: win
    required property var ctl

    readonly property color cyan: "#0abdc6"
    readonly property color cyanHi: "#9ff4f8"
    readonly property color amber: "#ff8c00"

    readonly property var mon: Hyprland.monitorFor(screen)
    readonly property var activeWs: mon ? mon.activeWorkspace : null
    readonly property int activeId: activeWs ? activeWs.id : -1
    readonly property bool fullscreenHere: activeWs ? activeWs.hasFullscreen : false
    readonly property bool suppressed: !ctl.enabled || ctl.gaming || fullscreenHere
    readonly property bool normalWs: activeId > 0 && !(activeWs && String(activeWs.name).indexOf("special") === 0)

    // ---- stack of workspaces on this monitor, in id order ----
    property var stackIds: []
    property var stackWs: []
    function rebuildStack() {
        var vals = Hyprland.workspaces.values
        var arr = []
        for (var i = 0; i < vals.length; i++) {
            var w = vals[i]
            if (w && w.id > 0 && w.monitor && mon && w.monitor.name === mon.name) arr.push(w)
        }
        arr.sort(function (a, b) { return a.id - b.id })
        stackWs = arr
        stackIds = arr.map(function (w) { return w.id })
    }
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { win.rebuildStack(); win.recheckEmpty() }
    }
    onMonChanged: { rebuildStack(); recheckEmpty() }

    // ---- empty detection (window count of the active workspace) ----
    property bool wsEmpty: false
    function recheckEmpty() {
        var w = activeWs
        wsEmpty = !!w && w.toplevels.values.length === 0
    }
    Connections {
        target: win.activeWs ? win.activeWs.toplevels : null
        function onValuesChanged() { win.recheckEmpty() }
    }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            var n = ev.name
            if (n === "openwindow" || n === "closewindow" || n === "movewindowv2" || n === "movewindow") settle.restart()
        }
    }
    Timer { id: settle; interval: 120; onTriggered: { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); win.recheckEmpty() } }
    onActiveWsChanged: recheckEmpty()

    // ---- display helpers ----
    function slotOf(id) { return ((id - 1) % ctl.slots) + 1 }
    function numeralText(id) {
        var n = ctl.globalNumbers ? id : slotOf(id)
        return (n < 10 ? "0" : "") + n
    }
    function nameOf(id) {
        for (var i = 0; i < stackWs.length; i++)
            if (stackWs[i].id === id) {
                var nm = String(stackWs[i].name)
                return (nm !== "" && nm !== String(id)) ? nm : ""
            }
        return ""
    }

    // ---- seam feather (owner send-back HQ-0185: the join between screens was visible) ----
    // The three wallpapers are rendered separately and do not match where they meet (left edge of the centre
    // frame is about 2/255 luma, the right edge of the left frame about 14/255). A static black falloff on each
    // edge that touches another monitor makes both sides converge on the bezel, so no seam is seen. Wallpaper
    // independent, no re-encode, tunable in config.json (feather, feather_width, feather_alpha).
    readonly property bool featherOn: ctl.partFeather && !suppressed
    function touches(dx) {
        var scrs = Quickshell.screens
        if (!screen) return false
        for (var i = 0; i < scrs.length; i++) {
            var o = scrs[i]
            if (o.name === screen.name) continue
            var edgeA = dx < 0 ? screen.x : screen.x + screen.width
            var edgeB = dx < 0 ? o.x + o.width : o.x
            var overlap = Math.min(screen.y + screen.height, o.y + o.height) - Math.max(screen.y, o.y)
            if (Math.abs(edgeA - edgeB) <= 2 && overlap > 0) return true
        }
        return false
    }
    readonly property bool featherLeft: touches(-1)
    readonly property bool featherRight: touches(1)

    // ---- beat state ----
    property int prevId: -1
    property real sgn: 1            // +1: new content arrives from below (next), -1: from above
    property string curText: ""
    property string curName: ""
    property string outText: ""
    property string outName: ""
    property real inY: 0            // numeral offset in px
    property real inA: 0
    property real outY: 0
    property real outA: 0
    property real bandF: 1.05       // band centre as a fraction of height
    property real bandA: 0
    property real ladderA: 0
    property real tickTarget: 0
    property real tickF: 0          // highlight position, in tick slots
    property int tickCount: 0
    property real driftX: 0
    property real driftY: 0

    readonly property bool holdWanted: ctl.partNumeral && ctl.emptyHold && wsEmpty && normalWs && !suppressed
    readonly property real restA: holdWanted ? ctl.emptyAlpha : 0.0
    onRestAChanged: {
        if (!beat.running && curText !== "") restTo.restart()
    }

    visible: !suppressed && (featherOn || beat.running || bandA > 0.002 || inA > 0.002 || outA > 0.002 || ladderA > 0.002 || holdWanted)

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "ws-sweep"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    mask: Region {}

    onSuppressedChanged: if (suppressed) cancelBeat()
    function cancelBeat() {
        beat.stop(); restTo.stop()
        bandA = 0; inA = 0; outA = 0; ladderA = 0
    }

    onActiveIdChanged: {
        if (activeId <= 0 || (mon && mon.activeWorkspace && String(mon.activeWorkspace.name).indexOf("special") === 0)) return
        rebuildStack()
        var firstTime = prevId < 0
        var old = prevId
        prevId = activeId
        curName = nameOf(activeId)
        if (firstTime) {
            curText = numeralText(activeId)
            inY = 0; inA = restA
            tickCount = stackIds.length
            tickF = Math.max(0, stackIds.indexOf(activeId))
            return
        }
        if (suppressed) { curText = numeralText(activeId); return }
        var d = activeId - old
        var s = d > 0 ? 1 : -1
        if (Math.abs(d) >= ctl.slots - 1 && Math.abs(d) < 2 * ctl.slots) s = -s   // wrap: same direction the slide uses
        play(s, old)
    }

    function play(s, old) {
        var H = height > 0 ? height : 2160
        var D = H * 0.22
        // retarget: the visible numeral becomes the leaving one
        outText = curText; outName = curName
        outY = inY; outA = inA
        sgn = s
        curText = numeralText(activeId)
        curName = nameOf(activeId)
        inY = s * D
        tickCount = stackIds.length
        tickTarget = Math.max(0, stackIds.indexOf(activeId))
        if (!ctl.partNumeral) { inA = 0; outA = 0 }
        // band: continue from where it is when a beat is still running
        var startF = s > 0 ? 1.05 : -0.05
        if (bandA < 0.02) bandF = startF
        beat.restart()
    }

    SequentialAnimation {
        id: beat
        ParallelAnimation {
            // band travel + incoming/outgoing numerals on the slide bezier
            NumberAnimation { target: win; property: "bandF"; to: win.sgn > 0 ? 0.15 : 0.85; duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0] }
            NumberAnimation { target: win; property: "inY"; to: 0; duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0] }
            NumberAnimation { target: win; property: "outY"; to: -win.sgn * win.height * 0.22; duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0] }
            NumberAnimation { target: win; property: "tickF"; to: win.tickTarget; duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0] }
            NumberAnimation { target: win; property: "outA"; to: 0; duration: 300; easing.type: Easing.OutCubic }
            SequentialAnimation {
                NumberAnimation { target: win; property: "bandA"; to: ctl.partBand ? 1 : 0; duration: 70 }
                PauseAnimation { duration: 230 }
                NumberAnimation { target: win; property: "bandA"; to: 0; duration: Math.max(200, ctl.beatMs - 300 - 100); easing.type: Easing.InOutQuad }
            }
            SequentialAnimation {
                NumberAnimation { target: win; property: "inA"; to: ctl.numeralAlpha; duration: 200; easing.type: Easing.OutCubic }
                PauseAnimation { duration: Math.max(0, ctl.beatMs - 200 - 380) }
                NumberAnimation { target: win; property: "inA"; to: win.restA; duration: 380; easing.type: Easing.InOutQuad }
            }
            SequentialAnimation {
                NumberAnimation { target: win; property: "ladderA"; to: ctl.partLadder ? ctl.ladderAlpha : 0; duration: 140 }
                PauseAnimation { duration: Math.max(0, ctl.beatMs - 140 - 300) }
                NumberAnimation { target: win; property: "ladderA"; to: 0; duration: 300; easing.type: Easing.InOutQuad }
            }
        }
    }
    NumberAnimation { id: restTo; target: win; property: "inA"; to: win.restA; duration: 600; easing.type: Easing.InOutQuad }

    // OLED drift while the empty numeral is held: at most 2 px per 30 s
    Timer {
        interval: 30000
        repeat: true
        running: win.holdWanted
        onTriggered: {
            var step = [[0, 0], [2, 0], [2, 2], [0, 2]]
            win._driftIdx = (win._driftIdx + 1) % 4
            win.driftX = step[win._driftIdx][0]
            win.driftY = step[win._driftIdx][1]
        }
    }
    property int _driftIdx: 0

    // ================= visuals =================
    Item {
        id: stage
        anchors.fill: parent

        // seam feather: eased black falloff on each edge shared with another monitor
        Rectangle {
            visible: win.featherOn && win.featherLeft
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: Math.round(parent.width * ctl.featherWidth)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: Qt.rgba(0, 0, 0, ctl.featherAlpha) }
                GradientStop { position: 0.12; color: Qt.rgba(0, 0, 0, ctl.featherAlpha * 0.80) }
                GradientStop { position: 0.28; color: Qt.rgba(0, 0, 0, ctl.featherAlpha * 0.52) }
                GradientStop { position: 0.48; color: Qt.rgba(0, 0, 0, ctl.featherAlpha * 0.27) }
                GradientStop { position: 0.70; color: Qt.rgba(0, 0, 0, ctl.featherAlpha * 0.09) }
                GradientStop { position: 1.00; color: Qt.rgba(0, 0, 0, 0.0) }
            }
        }
        Rectangle {
            visible: win.featherOn && win.featherRight
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: Math.round(parent.width * ctl.featherWidth)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 0.30; color: Qt.rgba(0, 0, 0, ctl.featherAlpha * 0.09) }
                GradientStop { position: 0.52; color: Qt.rgba(0, 0, 0, ctl.featherAlpha * 0.27) }
                GradientStop { position: 0.72; color: Qt.rgba(0, 0, 0, ctl.featherAlpha * 0.52) }
                GradientStop { position: 0.88; color: Qt.rgba(0, 0, 0, ctl.featherAlpha * 0.80) }
                GradientStop { position: 1.00; color: Qt.rgba(0, 0, 0, ctl.featherAlpha) }
            }
        }

        // sweep band
        Item {
            id: band
            visible: ctl.partBand && win.bandA > 0.002
            width: parent.width
            height: parent.height * 0.18
            y: parent.height * win.bandF - height / 2
            opacity: win.bandA
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(win.cyan.r, win.cyan.g, win.cyan.b, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(win.cyan.r, win.cyan.g, win.cyan.b, ctl.bandAlpha) }
                    GradientStop { position: 1.0; color: Qt.rgba(win.cyan.r, win.cyan.g, win.cyan.b, 0.0) }
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: Qt.rgba(win.cyanHi.r, win.cyanHi.g, win.cyanHi.b, Math.min(1, ctl.bandAlpha * 3.2))
            }
        }

        // numerals (etched: outline only, no panel)
        Item {
            id: numerals
            anchors.fill: parent
            visible: ctl.partNumeral
            Column {
                id: outCol
                visible: win.outA > 0.002
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: win.driftX
                y: (parent.height - height) / 2 + win.outY + win.driftY
                opacity: win.outA
                spacing: 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.outText
                    font.family: "GeistMono Nerd Font"; font.weight: Font.Thin
                    font.pixelSize: Math.round(win.height * 0.34)
                    color: Qt.rgba(win.cyan.r, win.cyan.g, win.cyan.b, 0.06)
                    style: Text.Outline
                    styleColor: win.cyan
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.outName; visible: text !== ""
                    font.family: "GeistMono Nerd Font"; font.weight: Font.Light
                    font.pixelSize: Math.round(win.height * 0.016); font.letterSpacing: 6
                    color: win.cyan
                }
            }
            Column {
                id: inCol
                visible: win.inA > 0.002
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: win.driftX
                y: (parent.height - height) / 2 + win.inY + win.driftY
                opacity: win.inA
                spacing: 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.curText
                    font.family: "GeistMono Nerd Font"; font.weight: Font.Thin
                    font.pixelSize: Math.round(win.height * 0.34)
                    color: Qt.rgba(win.cyan.r, win.cyan.g, win.cyan.b, 0.06)
                    style: Text.Outline
                    styleColor: win.cyan
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.curName; visible: text !== ""
                    font.family: "GeistMono Nerd Font"; font.weight: Font.Light
                    font.pixelSize: Math.round(win.height * 0.016); font.letterSpacing: 6
                    color: win.cyan
                }
            }
        }

        // tick ladder, right edge
        Item {
            id: ladder
            visible: ctl.partLadder && win.ladderA > 0.002
            opacity: win.ladderA
            readonly property real pitch: 36
            width: 48
            height: Math.max(1, win.tickCount) * pitch
            anchors.right: parent.right
            // Clear of the screen joins: when the right edge touches another monitor, sit past the feather band
            // (owner send-back 2: ticks beside the join read as a seam line). Outer edge keeps the 36 px inset.
            anchors.rightMargin: 36 + (win.featherRight ? Math.round(parent.width * (ctl.featherWidth + 0.04)) : 0)
            y: (parent.height - height) / 2
            Repeater {
                model: win.tickCount
                Rectangle {
                    required property int index
                    readonly property bool act: Math.abs(index - win.tickF) < 0.5
                    anchors.right: parent.right
                    y: index * ladder.pitch + ladder.pitch / 2 - 1
                    width: 22
                    height: 2
                    color: win.cyan
                    opacity: 0.8
                }
            }
            Rectangle {   // sliding amber highlight
                anchors.right: parent.right
                y: win.tickF * ladder.pitch + ladder.pitch / 2 - 1.5
                width: 44
                height: 3
                color: win.amber
            }
        }
    }
}
