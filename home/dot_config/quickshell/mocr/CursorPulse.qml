import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "theme"

// Per-monitor cursor pulse overlay — FEAT-workspace-bar-atlas Phase 4.
//
// Renders a brief 300ms expanding cyan ring at the cursor's current position
// whenever a workspace swap fires on the focused monitor. With hyprland.conf
// cursor { no_warps = true }, the cursor stays on the originating monitor, so
// the ring signals "I acted from here."
//
// Input: WlrKeyboardFocus.None prevents keyboard-focus theft. Pointer events
// pass through by default when no pointer handlers are registered; the window
// is also hidden (visible=false) between pulses so the compositor sees no
// input region when idle.

PanelWindow {
    id: cursorPulse
    property var modelData

    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mocr-cursor-pulse"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    color: "transparent"
    visible: false  // hidden between pulses — no input region for compositor

    // Screen-local cursor coordinates (populated from hyprctl cursorpos -j).
    property real cursorLocalX: 0
    property real cursorLocalY: 0

    // Expanding ring radius, animated from 10 → 80px over 300ms.
    property real ringRadius: 10

    // ── Workspace-change tracking — FEAT-workspace-split-monitor. ──
    // Fires on this monitor's active workspace change. Plugin-managed global
    // workspace IDs may be 1-9; the old named-workspace 1-7 guard is gone.
    readonly property int focusedActiveId: {
        if (!Hyprland.focusedMonitor) return -1
        var w = Hyprland.focusedMonitor.activeWorkspace
        return w ? w.id : -1
    }
    property int prevFocusedActiveId: -1
    property var prevFocusedMonitor: null

    onFocusedActiveIdChanged: {
        var mon = Hyprland.focusedMonitor
        var newId = cursorPulse.focusedActiveId
        var oldId = cursorPulse.prevFocusedActiveId

        // Guard: same monitor object changed its active workspace (not a monitor-focus hop).
        if (mon !== null && mon === cursorPulse.prevFocusedMonitor
                && newId >= 1
                && oldId >= 1
                && newId !== oldId
                && cursorPulse.modelData
                && mon.name === cursorPulse.modelData.name) {
            cursorPosQuery.running = true
        }
        cursorPulse.prevFocusedMonitor  = mon
        cursorPulse.prevFocusedActiveId = newId
    }

    // Query cursor position from Hyprland, then fire the ring animation.
    // modelData.x / modelData.y give the screen's compositor offset (pixels).
    Process {
        id: cursorPosQuery
        running: false
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: SplitParser {
            onRead: function(data) {
                try {
                    var pos = JSON.parse(data)
                    if (pos && typeof pos.x === "number" && typeof pos.y === "number") {
                        var sx = cursorPulse.modelData ? cursorPulse.modelData.x : 0
                        var sy = cursorPulse.modelData ? cursorPulse.modelData.y : 0
                        cursorPulse.cursorLocalX = pos.x - sx
                        cursorPulse.cursorLocalY = pos.y - sy
                        ringAnim.restart()
                    }
                } catch (e) {}
            }
        }
    }

    // Ring animation: expand radius 10→80px and fade 0.85→0 in parallel over 300ms.
    ParallelAnimation {
        id: ringAnim
        onStarted: {
            cursorPulse.visible = true
            ringItem.opacity = 0.85
        }
        NumberAnimation {
            target: cursorPulse
            property: "ringRadius"
            from: 10; to: 80
            duration: 300
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: ringItem
            property: "opacity"
            from: 0.85; to: 0.0
            duration: 300
            easing.type: Easing.InCubic
        }
        onStopped: cursorPulse.visible = false
    }

    // The ring: hollow circle that expands and fades.
    Rectangle {
        id: ringItem
        x: cursorPulse.cursorLocalX - cursorPulse.ringRadius
        y: cursorPulse.cursorLocalY - cursorPulse.ringRadius
        width:  cursorPulse.ringRadius * 2
        height: cursorPulse.ringRadius * 2
        radius: cursorPulse.ringRadius
        color: "transparent"
        border.color: Colors.cyan
        border.width: 2
        opacity: 0
    }
}
