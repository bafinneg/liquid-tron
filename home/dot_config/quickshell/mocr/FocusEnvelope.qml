import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "theme"

// Per-monitor, bounded active-window acquisition feedback.
// It deliberately reads only Hyprland's activated toplevel, monitor, and
// compositor geometry; no application-owned content is rendered or exported.
PanelWindow {
    id: focusEnvelope
    property var modelData

    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mocr-focus-envelope"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    color: "transparent"
    // No pointer handlers are registered; this transparent transient owns no input.
    visible: envelopeVisible
    // An empty click-through mask leaves no clickable region while visible.
    mask: Region {}

    readonly property string monitorName: modelData ? modelData.name : ""
    readonly property real railLength: 28
    readonly property real railWidth: 2
    readonly property real railGap: 2

    property bool envelopeVisible: false
    property var targetToplevel: null
    property var targetMonitor: null
    property var targetWorkspace: null
    property real targetX: 0
    property real targetY: 0
    property real targetWidth: 0
    property real targetHeight: 0
    property real envelopeOpacity: 0
    property real traceProgress: 0

    function isFiniteNumber(value) {
        return typeof value === "number" && isFinite(value)
    }

    function railTrace(index) {
        return Math.max(0, Math.min(1, traceProgress * 4 - index))
    }

    function clearImmediately() {
        focusEffect.stop()
        envelopeVisible = false
        envelopeOpacity = 0
        traceProgress = 0
        targetToplevel = null
        targetMonitor = null
        targetWorkspace = null
        targetX = 0
        targetY = 0
        targetWidth = 0
        targetHeight = 0
    }

    function finishEffect() {
        envelopeVisible = false
        envelopeOpacity = 0
        traceProgress = 0
    }

    function refreshTarget() {
        var toplevels = Hyprland.toplevels.values
        var candidate = null

        for (var i = 0; i < toplevels.length; i++) {
            var toplevel = toplevels[i]
            if (toplevel && toplevel.activated && toplevel.monitor
                    && toplevel.monitor.name === focusEnvelope.monitorName) {
                candidate = toplevel
                break
            }
        }

        if (!candidate || !candidate.monitor) {
            clearImmediately()
            return
        }

        var monitor = candidate.monitor
        var workspace = monitor.activeWorkspace
        if (!workspace || workspace.hasFullscreen) {
            clearImmediately()
            return
        }

        var ipc = candidate.lastIpcObject
        var at = ipc ? ipc.at : null
        var size = ipc ? ipc.size : null
        if (!at || !size || at.length < 2 || size.length < 2
                || !isFiniteNumber(at[0]) || !isFiniteNumber(at[1])
                || !isFiniteNumber(size[0]) || !isFiniteNumber(size[1])
                || !isFiniteNumber(monitor.x) || !isFiniteNumber(monitor.y)
                || !isFiniteNumber(monitor.width) || !isFiniteNumber(monitor.height)
                || size[0] <= 0 || size[1] <= 0
                || monitor.width <= 0 || monitor.height <= 0) {
            clearImmediately()
            return
        }

        var localX = at[0] - monitor.x
        var localY = at[1] - monitor.y
        var windowWidth = size[0]
        var windowHeight = size[1]

        // Rails must fit completely outside the window on this monitor. Suppress
        // edge-snapped or off-monitor geometry rather than clipping partial rails.
        var outerRailMargin = railGap + railLength
        if (localX < outerRailMargin || localY < outerRailMargin
                || localX + windowWidth + outerRailMargin > monitor.width
                || localY + windowHeight + outerRailMargin > monitor.height) {
            clearImmediately()
            return
        }

        var changed = candidate !== targetToplevel
                || monitor !== targetMonitor
                || workspace !== targetWorkspace
                || localX !== targetX
                || localY !== targetY
                || windowWidth !== targetWidth
                || windowHeight !== targetHeight

        targetToplevel = candidate
        targetMonitor = monitor
        targetWorkspace = workspace
        targetX = localX
        targetY = localY
        targetWidth = windowWidth
        targetHeight = windowHeight

        if (changed) focusEffect.restart()
    }

    // A Repeater observes the live model reactively. It refreshes the selected
    // target without forcing an effect for unrelated toplevel lifecycle events.
    Repeater {
        model: Hyprland.toplevels
        onCountChanged: focusEnvelope.refreshTarget()

        delegate: Item {
            required property var modelData
            readonly property bool isActivated: modelData ? modelData.activated : false
            readonly property var observedMonitor: modelData ? modelData.monitor : null
            readonly property var observedIpc: modelData ? modelData.lastIpcObject : null
            readonly property var observedWorkspace: observedMonitor ? observedMonitor.activeWorkspace : null
            readonly property bool observedFullscreen: observedWorkspace ? observedWorkspace.hasFullscreen : false
            readonly property real observedMonitorX: observedMonitor ? observedMonitor.x : 0
            readonly property real observedMonitorY: observedMonitor ? observedMonitor.y : 0
            readonly property real observedMonitorWidth: observedMonitor ? observedMonitor.width : 0
            readonly property real observedMonitorHeight: observedMonitor ? observedMonitor.height : 0

            visible: false
            width: 0
            height: 0

            Component.onCompleted: focusEnvelope.refreshTarget()
            Component.onDestruction: focusEnvelope.refreshTarget()
            onIsActivatedChanged: focusEnvelope.refreshTarget()
            onObservedMonitorChanged: focusEnvelope.refreshTarget()
            onObservedIpcChanged: focusEnvelope.refreshTarget()
            onObservedWorkspaceChanged: focusEnvelope.refreshTarget()
            onObservedFullscreenChanged: focusEnvelope.refreshTarget()
            onObservedMonitorXChanged: focusEnvelope.refreshTarget()
            onObservedMonitorYChanged: focusEnvelope.refreshTarget()
            onObservedMonitorWidthChanged: focusEnvelope.refreshTarget()
            onObservedMonitorHeightChanged: focusEnvelope.refreshTarget()
        }
    }

    // 90ms acquisition, one 360ms four-corner trace, then a 300ms decay:
    // fully absent again 750ms after the event. restart() replaces, never stacks.
    SequentialAnimation {
        id: focusEffect

        ScriptAction {
            script: {
                focusEnvelope.envelopeVisible = true
                focusEnvelope.envelopeOpacity = 0
                focusEnvelope.traceProgress = 0
            }
        }
        NumberAnimation {
            target: focusEnvelope
            property: "envelopeOpacity"
            from: 0
            to: 1
            duration: 90
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: focusEnvelope
            property: "traceProgress"
            from: 0
            to: 1
            duration: 360
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: focusEnvelope
            property: "envelopeOpacity"
            from: 1
            to: 0
            duration: 300
            easing.type: Easing.InCubic
        }
        ScriptAction { script: focusEnvelope.finishEffect() }
    }

    component CornerRail: Item {
        required property bool rightSide
        required property bool bottomSide
        required property real traceAmount

        width: focusEnvelope.railLength
        height: focusEnvelope.railLength
        visible: focusEnvelope.envelopeVisible && traceAmount > 0.001
        opacity: focusEnvelope.envelopeOpacity

        Rectangle {
            width: parent.width * parent.traceAmount
            height: focusEnvelope.railWidth
            x: parent.rightSide ? 0 : parent.width - width
            y: parent.bottomSide ? 0 : parent.height - height
            gradient: Gradient {
                GradientStop { position: 0.0; color: Colors.cyan }
                GradientStop { position: 1.0; color: Colors.blue }
            }
        }

        Rectangle {
            width: focusEnvelope.railWidth
            height: parent.height * parent.traceAmount
            x: parent.rightSide ? 0 : parent.width - width
            y: parent.bottomSide ? 0 : parent.height - height
            gradient: Gradient {
                GradientStop { position: 0.0; color: Colors.cyan }
                GradientStop { position: 1.0; color: Colors.blue }
            }
        }
    }

    // Four and only four transient corner rails; each remains outside the window.
    CornerRail {
        x: focusEnvelope.targetX - focusEnvelope.railGap - focusEnvelope.railLength
        y: focusEnvelope.targetY - focusEnvelope.railGap - focusEnvelope.railLength
        rightSide: false
        bottomSide: false
        traceAmount: focusEnvelope.railTrace(0)
    }

    CornerRail {
        x: focusEnvelope.targetX + focusEnvelope.targetWidth + focusEnvelope.railGap
        y: focusEnvelope.targetY - focusEnvelope.railGap - focusEnvelope.railLength
        rightSide: true
        bottomSide: false
        traceAmount: focusEnvelope.railTrace(1)
    }

    CornerRail {
        x: focusEnvelope.targetX - focusEnvelope.railGap - focusEnvelope.railLength
        y: focusEnvelope.targetY + focusEnvelope.targetHeight + focusEnvelope.railGap
        rightSide: false
        bottomSide: true
        traceAmount: focusEnvelope.railTrace(2)
    }

    CornerRail {
        x: focusEnvelope.targetX + focusEnvelope.targetWidth + focusEnvelope.railGap
        y: focusEnvelope.targetY + focusEnvelope.targetHeight + focusEnvelope.railGap
        rightSide: true
        bottomSide: true
        traceAmount: focusEnvelope.railTrace(3)
    }
}
