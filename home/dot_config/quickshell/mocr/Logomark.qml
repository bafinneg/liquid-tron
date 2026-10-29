import Quickshell
import Quickshell.Wayland
import QtQuick
import "components"
import "services" as Services
import "theme"

// Liquid Tron logomark — identity mark surface, DP-3 only.
// Anchored top-left below the bar; 264×264 container absorbs Layer B drift.
// AC-3: SystemStats is a plain type (not singleton) — instantiate locally here,
//        identical to AmbientLayer.qml's pattern.
// AC-2: GpuStats IS a singleton; gated on available so -1 sentinel flows to widget.
// AC-4: ShaderEffect and fragmentShader URL live inside LogomarkWidget.qml.

PanelWindow {
    id: logomark
    property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mocr-logomark"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // 264×264 absorbs ±4px drift on all four sides with headroom to spare.
    implicitWidth: 264
    implicitHeight: 264
    exclusiveZone: 0
    color: "transparent"
    mask: Region {}  // empty region → pointer events pass through to windows below

    anchors { top: true; left: true }

    // barHeightCenter = 32; gap = 8 → top edge at 40px below screen top.
    margins.top:  Geometry.barHeightCenter + 8
    margins.left: 8

    // AC-3: own SystemStats instance (plain type, not singleton)
    Services.SystemStats { id: sysStats }

    LogomarkWidget {
        anchors.centerIn: parent
        width: 240; height: 240

        // Layer B drift is handled inside LogomarkWidget via transform: Translate.

        // AC-3: cpuUsage from local sysStats instance
        cpuUsage: sysStats.cpuUsage

        // AC-2: GpuStats is a singleton. Pass -1 when unavailable so the inner
        // ring's state machine stays idle (gpuUsage < 60 when -1).
        gpuUsage: Services.GpuStats.available ? Services.GpuStats.gpuUsage : -1
    }
}
