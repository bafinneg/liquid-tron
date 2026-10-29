pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Workspace overview/state service — FEAT-workspace-overview and
// FEAT-workspace-split-monitor.
//
// IpcHandler "overview" receives `qs -c mocr ipc call overview toggle` from
// hypr-overview-trigger and emits overviewToggleRequested.
//
// IpcHandler "workspaces" provides a scriptable state read for acceptance
// testing:
//   qs -c mocr ipc call workspaces state
Item {
    id: service
    visible: false

    signal overviewToggleRequested()

    // workspace ID (int) → { screenName: string }
    property var thumbnailCache: ({})
    property string lastStateJson: "{}"

    function localNumber(globalId) {
        if (globalId < 1) return -1
        return ((globalId - 1) % 6) + 1
    }

    function buildState() {
        var monitors = ({})
        var vals = Hyprland.workspaces.values

        for (var i = 0; i < vals.length; i++) {
            var w = vals[i]
            if (!w || !w.monitor || w.id < 1) continue

            var name = w.monitor.name
            if (!monitors[name]) {
                monitors[name] = ({
                    name: name,
                    activeWorkspaceId: w.monitor.activeWorkspace ? w.monitor.activeWorkspace.id : -1,
                    activeLocalWorkspace: w.monitor.activeWorkspace ? service.localNumber(w.monitor.activeWorkspace.id) : -1,
                    workspaces: []
                })
            }

            monitors[name].workspaces.push({
                id: w.id,
                local: service.localNumber(w.id),
                active: w.monitor.activeWorkspace ? w.id === w.monitor.activeWorkspace.id : false
            })
        }

        return {
            workspaceCountPerMonitor: 6,
            monitors: monitors
        }
    }

    function refreshStateJson() {
        service.lastStateJson = JSON.stringify(service.buildState())
        return service.lastStateJson
    }

    function dumpState() {
        console.log("MOCR_WORKSPACES_STATE " + service.refreshStateJson())
    }

    function refreshThumbnailCache() {
        var updated = {}
        for (var i = 0; i < Hyprland.workspaces.values.length; i++) {
            var w = Hyprland.workspaces.values[i]
            if (w && w.monitor) {
                updated[w.id] = { screenName: w.monitor.name }
            }
        }
        service.thumbnailCache = updated
        service.refreshStateJson()
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: service.refreshThumbnailCache()
    }

    Component.onCompleted: service.refreshThumbnailCache()

    IpcHandler {
        target: "overview"
        function toggle() { service.overviewToggleRequested() }
    }

    IpcHandler {
        target: "workspaces"
        property string stateJson: service.lastStateJson
        function state() {
            service.refreshStateJson()
            stateJson = service.lastStateJson
            console.log("MOCR_WORKSPACES_STATE " + service.lastStateJson)
        }
    }
}
