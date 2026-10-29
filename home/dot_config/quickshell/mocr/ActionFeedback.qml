import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "theme"

// Monitor-local action feedback for bounded audio and system-mode state.
PanelWindow {
    id: feedback
    property var modelData
    property var eventSource

    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mocr-action-feedback"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { bottom: true }
    margins.bottom: feedback.modeFeedback ? Geometry.barPaddingOuter * 4 : Geometry.barPaddingOuter * 2
    exclusiveZone: 0
    color: "transparent"
    visible: feedback.active || feedback.panelOpacity > 0.001
    mask: Region {}
    implicitWidth: Math.min(
        feedback.modeFeedback ? 520 : Geometry.actionFeedbackWidth,
        modelData ? Math.max(1, modelData.width - Geometry.barPaddingOuter * 2)
                  : Geometry.actionFeedbackWidth
    )
    implicitHeight: feedback.modeFeedback ? 88 : 58

    readonly property string monitorName: modelData ? modelData.name : ""
    property bool active: false
    property real panelOpacity: 0.0
    property int volumePercent: 0
    property bool muted: false
    property string systemMode: ""
    readonly property bool focusedScreen: {
        var mon = Hyprland.focusedMonitor
        return mon && feedback.modelData && mon.name === feedback.monitorName
    }
    readonly property bool modeFeedback: systemMode === "gaming" || systemMode === "intelligent"
    readonly property string displayText: modeFeedback
        ? (systemMode === "gaming" ? "MODE // GAMING" : "MODE // INTELLIGENT")
        : muted ? "AUDIO // MUTED"
                : "AUDIO // " + String(volumePercent) + "%"

    onFocusedScreenChanged: {
        if (!feedback.focusedScreen) feedback.dismissNow()
    }

    function dismissNow() {
        holdTimer.stop()
        entryAnim.stop()
        fadeAnim.stop()
        feedback.panelOpacity = 0.0
        feedback.active = false
    }

    function reveal() {
        if (!feedback.focusedScreen) return
        fadeAnim.stop()
        holdTimer.stop()
        feedback.active = true
        entryAnim.restart()
        holdTimer.restart()
    }

    function showVolume(percent) {
        feedback.systemMode = ""
        feedback.muted = false
        feedback.volumePercent = Math.max(0, Math.min(100, percent))
        feedback.reveal()
    }

    function showMute() {
        feedback.systemMode = ""
        feedback.muted = true
        feedback.volumePercent = 0
        feedback.reveal()
    }

    function showMode(mode) {
        if (mode !== "gaming" && mode !== "intelligent") return
        feedback.systemMode = mode
        feedback.muted = false
        feedback.volumePercent = 0
        feedback.reveal()
    }

    Connections {
        target: feedback.eventSource
        function onActionFeedbackVolume(percent) { feedback.showVolume(percent) }
        function onActionFeedbackMute() { feedback.showMute() }
        function onActionFeedbackMode(mode) { feedback.showMode(mode) }
    }

    Timer {
        id: holdTimer
        interval: Motion.durationActionFeedbackHold
        repeat: false
        onTriggered: fadeAnim.restart()
    }

    NumberAnimation {
        id: entryAnim
        target: feedback
        property: "panelOpacity"
        to: 1.0
        duration: 90
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: fadeAnim
        target: feedback
        property: "panelOpacity"
        to: 0.0
        duration: Motion.durationTween
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.decay
        onFinished: feedback.active = false
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Geometry.actionFeedbackRadiusChrome
        color: Qt.alpha(Colors.bg_dark, 0.96)
        border.width: feedback.modeFeedback ? Geometry.borderWidthAccent : Geometry.borderWidth
        border.color: Qt.alpha(Colors.cyan, feedback.modeFeedback ? 0.82 : 0.48)
        opacity: feedback.panelOpacity

        Rectangle {
            anchors.fill: parent
            anchors.margins: 5
            radius: Geometry.actionFeedbackRadiusMeter
            color: feedback.modeFeedback ? Qt.alpha(Colors.bg_inset, 0.76) : Qt.alpha(Colors.bg_alt, 0.72)
            border.width: Geometry.borderWidth
            border.color: Qt.alpha(Colors.blue, feedback.modeFeedback ? 0.36 : 0.24)
            z: 0
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: feedback.modeFeedback ? 3 : 2
            radius: Geometry.actionFeedbackRadiusMeter
            color: Qt.alpha(Colors.cyan, feedback.modeFeedback ? 0.95 : 0.58)
            z: 1
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 2
            radius: Geometry.actionFeedbackRadiusMeter
            color: Qt.alpha(Colors.blue, feedback.modeFeedback ? 0.86 : 0.44)
            z: 1
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 5
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            width: Geometry.borderWidthAccent
            color: Qt.alpha(Colors.cyan, feedback.modeFeedback ? 0.84 : 0.62)
            z: 1
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Geometry.barPaddingModule + 10
            anchors.rightMargin: Geometry.barPaddingModule
            spacing: feedback.modeFeedback ? 10 : 8
            z: 2

            Text {
                width: parent.width
                text: feedback.displayText
                color: feedback.modeFeedback ? Colors.amber : Colors.cyan
                font.family: Geometry.fontFamily
                font.pixelSize: feedback.modeFeedback ? Geometry.fontSize + 8 : Geometry.fontSize
                font.weight: feedback.modeFeedback ? Font.Bold : Geometry.fontWeight
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                id: meterTrack
                width: parent.width
                height: 2
                radius: Geometry.actionFeedbackRadiusMeter
                color: Qt.alpha(Colors.cyan, 0.25)
                visible: !feedback.modeFeedback

                Rectangle {
                    width: feedback.muted ? 0 : Math.round(meterTrack.width * feedback.volumePercent / 100)
                    height: parent.height
                    radius: Geometry.actionFeedbackRadiusMeter
                    color: !feedback.muted && feedback.volumePercent > 0 ? Colors.amber : "transparent"
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                visible: feedback.muted && !feedback.modeFeedback
                color: Qt.alpha(Colors.red, 0.64)
            }
        }
    }
}
