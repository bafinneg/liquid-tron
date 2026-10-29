pragma Singleton
import QtQuick
import Quickshell.Io

Item {
    id: state
    visible: false; width: 0; height: 0

    property string mode: "intelligent"
    property bool gamingMode: mode === "gaming"

    Process {
        id: modeMon
        running: true
        command: ["bash", "-c",
            "f=\"${XDG_STATE_HOME:-$HOME/.local/state}/system-mode\"; " +
            "last=\"\"; " +
            "while :; do " +
              "cur=$(cat \"$f\" 2>/dev/null || echo intelligent); " +
              "if [ \"$cur\" != \"$last\" ]; then printf '%s\\n' \"$cur\"; last=\"$cur\"; fi; " +
              "sleep 1; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: data => {
                var line = (data || "").trim()
                if (line === "gaming")           state.mode = "gaming"
                else if (line === "intelligent") state.mode = "intelligent"
            }
        }
        onRunningChanged: {
            if (!running) modeMonRespawn.start()
        }
    }

    Timer {
        id: modeMonRespawn
        interval: 5000
        repeat: false
        onTriggered: { if (!modeMon.running) modeMon.running = true }
    }
}
