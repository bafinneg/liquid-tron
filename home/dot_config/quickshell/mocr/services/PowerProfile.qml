pragma Singleton
import QtQuick
import Quickshell.Io

// Authoritative system power-profile observer. It reads only the active profile
// from power-profiles-daemon's system D-Bus service and exposes power-saver as
// a bounded boolean for display-only lifecycle gates.
Item {
    id: state
    visible: false; width: 0; height: 0

    property bool powerSaving: false

    Process {
        id: profileMon
        running: true
        command: ["bash", "-c",
            "last=''; while :; do " +
            "cur=$(busctl --system get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile 2>/dev/null | tr -d '\"' | awk '{print $2}' || echo unknown); " +
            "if [ \"$cur\" != \"$last\" ]; then printf '%s\\n' \"$cur\"; last=\"$cur\"; fi; " +
            "sleep 2; done"
        ]
        stdout: SplitParser {
            onRead: data => state.powerSaving = (data || "").trim() === "power-saver"
        }
        onRunningChanged: if (!running) profileMonRespawn.start()
    }
    Timer {
        id: profileMonRespawn
        interval: 5000; repeat: false
        onTriggered: if (!profileMon.running) profileMon.running = true
    }
}
