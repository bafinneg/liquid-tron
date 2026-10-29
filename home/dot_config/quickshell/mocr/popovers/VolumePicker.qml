import QtQuick
import Quickshell.Io
import "../theme"
import "../components"

// Volume picker content: audio sink list + volume slider.
// Uses wpctl for audio state (own Processes, no stats dependency).

Item {
    id: volPicker

    property var _sinks: []
    property int _defaultId: -1
    property real _volume: 0
    property bool _muted: false
    property var _pendingSinks: []

    Component.onCompleted: _startPoll()

    function _startPoll() {
        _pendingSinks = []
        if (!sinkPollProc.running)
            sinkPollProc.running = true
    }

    Process {
        id: sinkPollProc
        command: ["bash", "-c", volPicker._pollScript()]
        stdout: SplitParser {
            onRead: data => volPicker._parseLine(data)
        }
        onExited: volPicker._sinks = volPicker._pendingSinks
    }

    function _pollScript() {
        return [
            "set -euo pipefail",
            "did=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | head -1 | sed 's/[^0-9]*\\([0-9]*\\).*/\\1/')",
            "echo \"DEFAULT:$did\"",
            "vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo 'Volume: 0')",
            "echo \"DEFVOL:$vol\"",
            "section=",
            "while IFS= read -r line; do",
            "  case \"$line\" in",
            "    *Sinks:*) section=sinks; continue ;;",
            "    *Sources:*|*Filters:*|*Streams:*)",
            "      [ \"$section\" = sinks ] && break",
            "      continue ;;",
            "  esac",
            "  [ \"$section\" != sinks ] && continue",
            "  id=$(echo \"$line\" | sed -n 's/[^0-9]*\\([0-9]\\+\\)\\..*/\\1/p' | head -1)",
            "  [ -z \"$id\" ] && continue",
            "  nm=$(echo \"$line\" | sed 's/^[^0-9]*[0-9]*\\.[[:space:]]*//' | sed 's/[[:space:]]*\\[vol:.*//')",
            "  echo \"SINK:$id:$nm\"",
            "done < <(wpctl status 2>/dev/null)"
        ].join("\n")
    }

    function _parseLine(line) {
        if (line.startsWith("DEFAULT:")) {
            _defaultId = parseInt(line.substring(8)) || -1
        } else if (line.startsWith("DEFVOL:")) {
            var vstr = line.substring(7)
            _muted = vstr.indexOf("[MUTED]") >= 0
            var numStr = vstr.replace("Volume:", "").replace("[MUTED]", "").trim()
            _volume = parseFloat(numStr) || 0
        } else if (line.startsWith("SINK:")) {
            var rest = line.substring(5)
            var ci = rest.indexOf(":")
            if (ci >= 0) {
                _pendingSinks.push({
                    sinkId: parseInt(rest.substring(0, ci)),
                    name: rest.substring(ci + 1)
                })
            }
        }
    }

    Process {
        id: switchSinkProc
        property string targetId: "0"
        command: ["wpctl", "set-default", targetId]
        onExited: volPicker._startPoll()
    }

    Process {
        id: volSetProc
        property string vol: "0.50"
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", vol]
    }

    Timer {
        id: volSetTimer
        interval: 80
        onTriggered: {
            volSetProc.vol = volPicker._volume.toFixed(2)
            if (!volSetProc.running)
                volSetProc.running = true
        }
    }

    // Scroll anywhere to adjust volume
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(event) {
            volPicker._volume = Math.max(0,
                Math.min(1, volPicker._volume + (event.angleDelta.y > 0 ? 0.01 : -0.01)))
            volSetTimer.restart()
        }
    }

    Column {
        anchors.fill: parent
        spacing: 6

        Text {
            text: "AUDIO SINKS"
            color: Colors.fg_dim
            font.family: Geometry.fontFamily
            font.pixelSize: 10
            font.weight: Geometry.fontWeight
        }

        Column {
            width: parent.width
            spacing: 2

            Repeater {
                model: volPicker._sinks.length

                Rectangle {
                    id: sinkRow
                    required property int index

                    property var _sink: index < volPicker._sinks.length
                        ? volPicker._sinks[index] : null
                    property bool _isDefault: _sink
                        ? _sink.sinkId === volPicker._defaultId : false

                    width: parent ? parent.width : 0
                    height: 20
                    radius: Geometry.radiusInteractive
                    color: _isDefault ? Qt.alpha(Colors.amber, 0.15) : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 12
                        text: sinkRow._sink ? sinkRow._sink.name : ""
                        elide: Text.ElideRight
                        color: sinkRow._isDefault ? Colors.amber : Colors.fg
                        font.family: Geometry.fontFamily
                        font.pixelSize: 10
                        font.weight: Geometry.fontWeight
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (sinkRow._sink) {
                                switchSinkProc.targetId = sinkRow._sink.sinkId.toString()
                                if (!switchSinkProc.running)
                                    switchSinkProc.running = true
                            }
                        }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Colors.fg_dark }

        Row {
            width: parent.width
            spacing: 6
            Text {
                text: "VOLUME"; color: Colors.fg_dim
                font.family: Geometry.fontFamily; font.pixelSize: 10; font.weight: Geometry.fontWeight
            }
            Text {
                text: volPicker._muted ? "MUTED" : Math.round(volPicker._volume * 100) + "%"
                color: volPicker._muted ? Colors.red : Colors.amber
                font.family: Geometry.fontFamily; font.pixelSize: 10; font.weight: Geometry.fontWeight
            }
        }

        Item {
            width: parent.width
            height: 14

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 4; radius: 2
                color: Colors.bg_dark
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(parent.width, parent.width * volPicker._volume))
                height: 4; radius: 2
                color: volPicker._muted ? Colors.fg_dark : Colors.amber
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(parent.width - width, parent.width * volPicker._volume - width / 2))
                width: 8; height: 8; radius: 4
                color: volPicker._muted ? Colors.fg_dark : Colors.amber
            }

            MouseArea {
                anchors.fill: parent
                anchors.topMargin: -6
                anchors.bottomMargin: -6
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => _setVol(mouse.x)
                onPositionChanged: mouse => { if (pressed) _setVol(mouse.x) }
                onWheel: function(event) {
                    volPicker._volume = Math.max(0,
                        Math.min(1, volPicker._volume + (event.angleDelta.y > 0 ? 0.01 : -0.01)))
                    volSetTimer.restart()
                }

                function _setVol(mx) {
                    volPicker._volume = Math.max(0, Math.min(1, mx / width))
                    volSetTimer.restart()
                }
            }
        }
    }
}
