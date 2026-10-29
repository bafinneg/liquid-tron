pragma Singleton
import QtQuick
import Quickshell.Io

// Watches the latest local daily anomaly digest without changing the digest pipeline.
Item {
    id: service
    visible: false
    width: 0
    height: 0

    property string latestDate: ""
    property string latestText: ""
    property int staleDays: -1
    readonly property bool available: latestDate !== ""
    property string _textBuffer: ""

    function _dateToUtc(text) {
        var parts = (text || "").split("-")
        if (parts.length !== 3) return NaN
        var year = Number(parts[0])
        var month = Number(parts[1])
        var day = Number(parts[2])
        if (!isFinite(year) || !isFinite(month) || !isFinite(day)) return NaN
        return Date.UTC(year, month - 1, day)
    }

    function _staleness(dateText, todayText) {
        var latest = _dateToUtc(dateText)
        var today = _dateToUtc(todayText)
        if (isNaN(latest) || isNaN(today)) return -1
        return Math.max(0, Math.floor((today - latest) / 86400000))
    }

    function _refreshText(filename) {
        if (digestReader.running) digestReader.running = false
        _textBuffer = ""
        digestReader.targetFilename = filename
        digestReader.running = true
    }

    function _applySnapshot(data) {
        var fields = (data || "").trim().split("|")
        var filename = fields.length > 0 ? fields[0] : ""
        var today = fields.length > 2 ? fields[2] : ""
        if (filename === "") {
            latestDate = ""
            latestText = ""
            staleDays = -1
            return
        }

        var dateText = filename.replace(/\.md$/, "")
        if (!/^\d{4}-\d{2}-\d{2}$/.test(dateText)) return
        latestDate = dateText
        staleDays = _staleness(dateText, today)
        _refreshText(filename)
    }

    // Emits only when the newest filename, its mtime, or the local day changes.
    Process {
        id: digestPoll
        running: true
        command: ["bash", "-c",
            "dir=\"$HOME/home-infra/.local/digests\"; last=\"\"; " +
            "while :; do " +
              "newest=$(ls -1t \"$dir\"/[0-9]*-[0-9]*-[0-9]*.md 2>/dev/null | head -n 1 || true); " +
              "if [ -n \"$newest\" ]; then filename=${newest##*/}; mtime=$(stat -c %Y -- \"$newest\" 2>/dev/null || echo 0); else filename=\"\"; mtime=\"\"; fi; " +
              "today=$(date +%F); cur=\"$filename|$mtime|$today\"; " +
              "if [ \"$cur\" != \"$last\" ]; then printf '%s\\n' \"$cur\"; last=\"$cur\"; fi; " +
              "sleep 60; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: data => service._applySnapshot(data)
        }
        onRunningChanged: {
            if (!running) digestPollRespawn.start()
        }
    }

    Timer {
        id: digestPollRespawn
        interval: 5000
        repeat: false
        onTriggered: {
            if (!digestPoll.running) digestPoll.running = true
        }
    }

    Process {
        id: digestReader
        property string targetFilename: ""
        running: false
        command: ["bash", "-c", "cat -- \"$HOME/home-infra/.local/digests/$1\" 2>/dev/null || true", "digest-reader", targetFilename]
        stdout: SplitParser {
            onRead: data => service._textBuffer += data + "\n"
        }
        onExited: service.latestText = service._textBuffer
    }
}
