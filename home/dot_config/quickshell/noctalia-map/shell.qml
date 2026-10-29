import Quickshell
import QtQuick

ShellRoot {
    id: shell

    // FEAT-lt26r-5 OD-G: the Map lives on the center display, resolved by monitor model (the ASUS PG42UQ),
    // else the middle display by x-position. No connector name is ever trusted (INVARIANTS 6).
    readonly property string centerModel: "PG42UQ"
    readonly property var hostScreen: {
        var screens = []
        for (var i = 0; i < Quickshell.screens.length; i++) {
            var candidate = Quickshell.screens[i]
            if (!candidate) continue
            if (candidate.model === shell.centerModel) return candidate
            screens.push(candidate)
        }
        if (screens.length === 0) return null
        screens.sort(function(a, b) { return a.x - b.x })
        return screens[Math.floor(screens.length / 2)]
    }

    Loader {
        active: shell.hostScreen !== null
        sourceComponent: Component {
            SystemMap {
                screen: shell.hostScreen
                hostConnector: shell.hostScreen ? shell.hostScreen.name : ""
            }
        }
    }

    Timer {
        interval: 4000
        running: shell.hostScreen === null
        onTriggered: Qt.quit()
    }
}
