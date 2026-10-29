import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// Hand-gesture HUD: bottom-centre pill on the PG42UQ. Hidden when state.json is absent.
ShellRoot {
    id: root

    property var st: null
    readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/hand-gesture/state.json"

    function parse(text) {
        if (!text || text.length < 2) { st = null; return }
        try {
            var o = JSON.parse(text)
            st = (o && o.v === 1) ? o : null
        } catch (e) { st = null }
    }

    FileView {
        id: file
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.st = null
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: file.reload()
    }

    // -- reticles: the daemon streams newline-delimited JSON over a Unix socket (30 Hz); state.json is too slow for it
    property var reticles: []
    property real lastRecv: 0
    property int recvCount: 0
    // HAND_GESTURE_DIR overrides the directory (tests drive a stub server); HAND_GESTURE_DEBUG logs receive stats
    readonly property string sockDir: Quickshell.env("HAND_GESTURE_DIR") || ((Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/hand-gesture")
    readonly property string sockPath: sockDir + "/reticle.sock"
    readonly property bool debug: Quickshell.env("HAND_GESTURE_DEBUG") === "1"
    property real lat: 0

    Socket {
        id: sock
        path: root.sockPath
        connected: true
        parser: SplitParser {
            onRead: data => {
                try {
                    var o = JSON.parse(data)
                    if (o && o.v === 1) {
                        root.reticles = o.r
                        root.recvCount++
                        if (root.debug && o.cap_ms) root.lat = Date.now() - o.cap_ms
                        root.lastRecv = Date.now()
                    }
                } catch (e) {}
            }
        }
        onConnectedChanged: if (!connected) root.reticles = []
    }
    Timer {
        interval: 1000
        running: root.debug
        repeat: true
        property int prev: 0
        onTriggered: { console.log("hg-recv-hz=" + (root.recvCount - prev) + " lat-ms=" + root.lat.toFixed(1)); prev = root.recvCount }
    }
    Timer {                                  // reconnect after the daemon restarts; clear stale reticles
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (!sock.connected) { sock.connected = false; sock.connected = true }
            if (root.reticles.length > 0 && Date.now() - root.lastRecv > 700) root.reticles = []
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: overlay
            required property var modelData
            screen: modelData
            visible: root.reticles.length > 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "hand-gesture-reticle"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            mask: Region {}

            Repeater {
                model: root.reticles
                Reticle {
                    required property var modelData
                    primary: modelData.id === "p"
                    cx: modelData.x - overlay.screen.x
                    cy: modelData.y - overlay.screen.y
                    pinch: modelData.pinch
                    over: modelData.over
                    dwell: modelData.dwell
                    btn: modelData.btn === true
                    visible: cx > -40 && cx < overlay.width + 40 && cy > -40 && cy < overlay.height + 40
                }
            }
        }
    }

    function pickScreen() {
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++)
            if ((s[i].model || "").indexOf("PG42UQ") >= 0) return s[i]
        return s.length > 0 ? s[0] : null
    }

    PanelWindow {
        id: win
        screen: root.pickScreen()
        visible: root.st !== null || slide.running || pill.y < win.height
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "hand-gesture"
        exclusionMode: ExclusionMode.Ignore
        anchors.bottom: true
        margins.bottom: 48
        implicitWidth: 340
        implicitHeight: 96
        color: "transparent"
        mask: Region {}

        Pill {
            id: pill
            width: parent.width
            height: parent.height
            st: root.st
            y: root.st !== null ? 0 : win.height
            Behavior on y {
                NumberAnimation { id: slide; duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }
}
