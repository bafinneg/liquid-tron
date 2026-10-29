pragma Singleton
import QtQuick
import Quickshell.Io

Item {
    id: state
    visible: false; width: 0; height: 0

    property bool active: false

    Process {
        id: anchalMon
        running: true
        command: ["bash", "-c",
            "f=\"${XDG_STATE_HOME:-$HOME/.local/state}/anchal-mode\"; " +
            "last=\"\"; " +
            "while :; do " +
              "cur=$(cat \"$f\" 2>/dev/null || echo off); " +
              "if [ \"$cur\" != \"$last\" ]; then printf '%s\\n' \"$cur\"; last=\"$cur\"; fi; " +
              "sleep 2; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: data => {
                var line = (data || "").trim()
                if (line === "active") state.active = true
                else                  state.active = false
            }
        }
        onRunningChanged: {
            if (!running) anchalMonRespawn.start()
        }
    }
    Timer { id: anchalMonRespawn; interval: 5000; repeat: false;
            onTriggered: { if (!anchalMon.running) anchalMon.running = true } }
}
