import QtQuick
import Quickshell.Io
import "../theme"
import "../components"

// Volume module: "VOL NN%", tweened value updates. Healthy volume uses
// restrained cyan; muted, unavailable, or over-limit audio uses semantic amber.
// Click toggles VolumePicker popover in the shelf. Scroll adjusts volume.

ModuleContainer {
    id: root

    property var parentBar
    sourceActive: parentBar && parentBar.activePopoverId === "vol"
    property int volumePercent: 0
    property bool isMuted: false
    property bool hasData: false
    readonly property bool warningState: hasData && (isMuted || volumePercent > 100)
    moduleState: warningState ? "warning" : "normal"
    // Startup/unavailable audio is legible at full weight without firing the
    // warning pulse before the first wpctl sample arrives.
    visualWeight: hasData ? 0.66 : 1.0
    readonly property color volumeColor: (!hasData || isMuted || volumePercent > 100)
        ? Colors.amber : Colors.cyan

    Process {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => {
                var line = data.trim()
                if (line.startsWith("Volume:")) {
                    root.isMuted = line.indexOf("[MUTED]") >= 0
                    var numStr = line.replace("Volume:", "").replace("[MUTED]", "").trim()
                    root.volumePercent = Math.round(parseFloat(numStr) * 100)
                    root.hasData = true
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!volProc.running)
                volProc.running = true
        }
    }

    property int _scrollAccum: 0

    Timer {
        id: scrollDebounce
        interval: 10
        onTriggered: {
            if (root._scrollAccum === 0) return
            var pct = Math.abs(root._scrollAccum)
            volScrollProc.step = pct + (root._scrollAccum > 0 ? "%+" : "%-")
            root._scrollAccum = 0
            if (!volScrollProc.running)
                volScrollProc.running = true
        }
    }

    Process {
        id: volScrollProc
        property string step: "1%+"
        command: ["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", step]
    }

    TextMetrics {
        id: volMetrics
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
        text: "VOL 100%"
    }

    contentItem: [
        Item {
            implicitWidth: volMetrics.advanceWidth
            implicitHeight: Geometry.barHeightCenter

            Text {
                id: mutedLabel
                visible: root.isMuted || !root.hasData
                text: "VOL  \u2500\u2500"
                color: root.volumeColor
                font.family: Geometry.fontFamily
                font.pixelSize: Geometry.fontSize
                font.weight: Geometry.fontWeight
                verticalAlignment: Text.AlignVCenter
                height: Geometry.barHeightCenter
            }

            TweenedNumber {
                id: tweenedVol
                visible: root.hasData && !root.isMuted
                value: root.volumePercent
                prefix: "VOL "
                suffix: "%"
                padWidth: 3
                textColor: root.volumeColor
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton
                onClicked: root.parentBar.togglePopover("vol")
                onWheel: function(event) {
                    var dir = event.angleDelta.y > 0 ? 1 : -1
                    root._scrollAccum += dir
                    root.volumePercent = Math.max(0, Math.min(100, root.volumePercent + dir))
                    scrollDebounce.restart()
                }
            }
        }
    ]
}
