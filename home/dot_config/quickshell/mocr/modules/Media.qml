import QtQuick
import Quickshell.Services.Mpris
import "../theme"
import "../components"

// MPRIS now-playing module for the calm center cluster.
ModuleContainer {
    id: root
    property var parentBar

    readonly property var players: Mpris.players.values ? Mpris.players.values : []
    readonly property var activePlayer: {
        var vals = root.players
        if (!vals || vals.length === 0) return null
        for (var i = 0; i < vals.length; i++) {
            var p = vals[i]
            var state = p && p.playbackState !== undefined ? String(p.playbackState).toLowerCase() : ""
            if (state.indexOf("playing") >= 0) return p
        }
        return vals[0]
    }
    readonly property bool hasPlayer: activePlayer !== null
    readonly property string stateText: hasPlayer && activePlayer.playbackState !== undefined ? String(activePlayer.playbackState).toLowerCase() : ""
    readonly property bool playing: stateText.indexOf("playing") >= 0
    visualRole: root.playing ? "leader" : "telemetry"
    readonly property string artistText: hasPlayer && activePlayer.trackArtist ? String(activePlayer.trackArtist) : ""
    readonly property string titleText: hasPlayer && activePlayer.trackTitle ? String(activePlayer.trackTitle) : ""
    readonly property string displayText: {
        if (!hasPlayer) return ""
        if (artistText.length > 0 && titleText.length > 0) return artistText + " — " + titleText
        if (titleText.length > 0) return titleText
        if (artistText.length > 0) return artistText
        return "MPRIS"
    }

    visible: hasPlayer
    implicitWidth: visible ? Math.min(320, Geometry.borderWidth + playbackRow.implicitWidth + Geometry.barPaddingModule * 2) : 0
    implicitHeight: Geometry.barHeightCenter
    clip: true

    function callIfPresent(fnName) {
        if (root.activePlayer && typeof root.activePlayer[fnName] === "function") root.activePlayer[fnName]()
    }

    contentItem: [
        Row {
            id: playbackRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 6

            Text {
                text: root.playing ? "▶" : "⏸"
                color: Colors.cyan
                font.family: Geometry.fontFamily
                font.pixelSize: Geometry.fontSize
                font.weight: Geometry.fontWeight
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                width: Math.min(290, implicitWidth)
                text: root.displayText
                color: Colors.fg
                font.family: Geometry.fontFamily
                font.pixelSize: Geometry.fontSize
                font.weight: Geometry.fontWeight
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    ]

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.callIfPresent("togglePlaying")
        onWheel: function(wheel) {
            if (wheel.angleDelta.y > 0) root.callIfPresent("next")
            else if (wheel.angleDelta.y < 0) root.callIfPresent("previous")
        }
    }
}
