import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "ambient/variants"
import "services" as Services

// WlrLayer.Background surface hosting PrismaticVeil on DP-3 only.
// Governed suppressions destroy the Loader item rather than hiding it, so
// fullscreen, game, lock/idle absence, and power-saving states leave no
// rendered center ambient surface behind.
PanelWindow {
    id: centerAmbient
    property var modelData

    screen: modelData
    visible: !!modelData

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "mocr-center-ambient"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    mask: Region {}
    color: "transparent"

    readonly property bool suppressed: centerAmbient.anyScopeFullscreen
        || Services.SystemMode.gamingMode
        || Services.PresenceState.absent
        || Services.PowerProfile.powerSaving

    property bool anyScopeFullscreen: {
        var ws = Hyprland.workspaces
        for (var i = 0; i < ws.values.length; i++) {
            var w = ws.values[i]
            if (w && w.hasFullscreen && w.monitor && w.monitor.name === "DP-3")
                return true
        }
        return false
    }

    // Owner-directed performance correction: keep the DP-3 layer contract and
    // suppression authorities, but leave the full-screen 4 FPS Canvas unloaded.
    // Controlled runtime isolation reduced aggregate GPU utilization from the
    // 20–30% range to 11–14% and Hyprland attribution from 14–34% to 5–12%.
    // Set active back to `centerAmbient.visible && !centerAmbient.suppressed` to
    // restore PrismaticVeil after a replacement renderer is performance-proven.
    Loader {
        id: depthLoader
        anchors.fill: parent
        active: false
        sourceComponent: Component { PrismaticVeil {} }
    }
}
