pragma Singleton
import Quickshell
import QtQuick

// Global sweep clock for the Tron-sweep atmospheric animation.
//
// Monitors sweep serially, left → right, based on screen x-coordinate.
// Each monitor's local sweep occupies a 1/N slice of the full cycle;
// outside its slice, the bar's sweep crest extrapolates off-screen and
// is hidden by the bar's clip region.
//
// Per-monitor sweep speed is held constant at perMonitorMs — total
// cycle time scales with screen count so the crest traversal feel
// matches the single-monitor case.
QtObject {
    id: root

    readonly property int perMonitorMs: 25000

    property real globalProgress: 0

    NumberAnimation on globalProgress {
        from: 0; to: 1
        duration: root.perMonitorMs * Math.max(1, root.screenCount)
        loops: Animation.Infinite
        easing.type: Easing.Linear
    }

    readonly property var sortedScreens: {
        let screens = Quickshell.screens.slice()
        screens.sort((a, b) => a.x - b.x)
        return screens
    }

    readonly property int screenCount: sortedScreens.length

    function phaseFor(screen) {
        for (let i = 0; i < sortedScreens.length; i++) {
            if (sortedScreens[i].name === screen.name) return i
        }
        return 0
    }

    // Maps globalProgress into this screen's local [0, 1] sweep.
    // Values outside [0, 1] are intentional — the sweep rect is 3× bar
    // width, so extrapolation keeps the crest off-screen when inactive.
    function progressFor(screen) {
        let n = Math.max(1, screenCount)
        return (globalProgress - phaseFor(screen) / n) * n
    }
}
