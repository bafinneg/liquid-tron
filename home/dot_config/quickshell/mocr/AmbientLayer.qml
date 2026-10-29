import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "ambient/variants"
import "services" as Services
import "theme"

// Per-monitor WlrLayer.Background surface that hosts a theme-selected
// ambient variant (matrix-bezels, blade-runner-stripes, nostromo-whispers, prismatic-veil).
// The variant is chosen by the `Ambient` singleton, rendered from
// shared/themes/palettes/<theme>.yaml at apply-theme.sh time.
//
// Chunk 4 (FEAT-ambient-layer): original three variants wired — matrix-bezels,
// blade-runner-stripes, nostromo-whispers. prismatic-veil added post-launch.
// Loader.active pauses the
// variant when any in-scope monitor has a fullscreen client
// (Hyprland.workspaces.hasFullscreen). Destroying the variant on pause
// gives it fresh random state on resume, satisfying the OLED "no static
// bright pixel >4s" constraint for free.
//
// GPU telemetry is served by Services.GpuStats (singleton, not
// instantiated per AmbientLayer) because GPU state is system-wide.
// Variants access it directly; no property needs to cross this layer.
PanelWindow {
    id: ambient
    property var modelData

    screen: modelData
    // Guard the .name dereference: Variants assigns modelData asynchronously,
    // so the binding can fire with modelData still undefined during init.
    visible: !!modelData && Ambient.monitorScope.indexOf(modelData.name) !== -1

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "mocr-ambient"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    color: "transparent"

    // Per-monitor SystemStats instance (not singleton). GpuStats IS a
    // singleton because GPU is one system-wide device; SystemStats
    // isn't because its per-AmbientLayer polling is already modest
    // and singletonizing it requires factoring out its hwmon
    // discovery state.
    Services.SystemStats { id: sysStats }

    // True when any monitor in `Ambient.monitorScope` currently has a
    // fullscreen client. The iteration reads every workspace's
    // hasFullscreen so the QML engine tracks all of them as dependencies
    // (a short-circuit would miss updates from workspaces after the
    // first fullscreen one).
    property bool anyScopeFullscreen: {
        var scope = Ambient.monitorScope
        var ws = Hyprland.workspaces
        var found = false
        for (var i = 0; i < ws.values.length; i++) {
            var w = ws.values[i]
            var fs = !!(w && w.hasFullscreen)
            var name = (w && w.monitor) ? w.monitor.name : ""
            if (fs && scope.indexOf(name) !== -1) found = true
        }
        return found
    }

    Loader {
        id: variantLoader
        anchors.fill: parent
        // Gate loading on: (a) this monitor is in scope, (b) no fullscreen
        // pause. When inactive, the component is destroyed; when re-activated,
        // a fresh MatrixBezels (or future variant) is constructed with new
        // random seeds — OLED-safe by construction.
        active: ambient.visible && !ambient.anyScopeFullscreen
        sourceComponent: {
            switch (Ambient.variant) {
                case "matrix-bezels":         return matrixComp
                case "blade-runner-stripes":  return bladeComp
                case "nostromo-whispers":     return nostromoComp
                case "prismatic-veil":        return prismaticComp
                default: return null
            }
        }
    }

    Component {
        id: matrixComp
        MatrixBezels {
            screenName: ambient.modelData ? ambient.modelData.name : ""
            sysStats: sysStats
        }
    }

    Component {
        id: bladeComp
        BladeRunnerStripes {
            screenName: ambient.modelData ? ambient.modelData.name : ""
            sysStats: sysStats
        }
    }

    Component {
        id: nostromoComp
        NostromoWhispers {
            screenName: ambient.modelData ? ambient.modelData.name : ""
        }
    }

    Component {
        id: prismaticComp
        PrismaticVeil {}
    }
}
