// PresenceState — singleton absence indicator (FEAT-nostromo-llm chunk 3).
//
// `absent` is the logical OR of two independent inputs:
//
//   1. `_lockActive` — driven by `bin/presence-monitor.sh`, which tails
//      logind's LockedHint property on the system bus (dbus-monitor
//      primary, loginctl-poll fallback). Emits LOCKED / UNLOCKED on
//      every transition plus one line at startup to seed the state.
//
//   2. `_hypridleIdle` — driven by a bash loop that polls
//      `${XDG_STATE_HOME:-$HOME/.local/state}/nostromo/hypridle-idle`
//      every 3 seconds and emits IDLE / ACTIVE on transitions. The
//      flag file is created/removed by the 300s hypridle listener
//      (hypridle.conf, same spec).
//
// Both Process blocks respawn after a 5s debounce if their child exits
// (dbus-monitor can die if the system bus restarts; the poll loop
// should never exit but the respawn is defensive). The debounce avoids
// a tight spawn-die-spawn cycle if something on disk is genuinely
// broken.
//
// `absent` drives two sentinel-mode behaviours in JournalInterpreter:
//   - Chunk 4: on false → true transition, if the current window has
//     enough entries and age, close it early into a digest before the
//     absence-phase windows accumulate.
//   - Chunk 5: on true → false transition, NostromoWhispers calls
//     `Services.JournalInterpreter.consolidateRecap()` to emit the
//     "while you were gone" recap burst.
//
// The singleton is stateless across quickshell restarts — on restart
// both inputs are re-read from their sources (loginctl + the flag
// file), so the initial `absent` reflects the current truth regardless
// of whether absence was active across the restart.

pragma Singleton

import QtQuick
import Quickshell.Io

Item {
    id: state
    visible: false
    width: 0; height: 0

    // ── Public API ────────────────────────────────────────────────
    // Bound to the OR of the two inputs — QML re-evaluates on every
    // change and fires the auto-generated `absentChanged` signal only
    // on genuine transitions. Consumers wire `Connections { target:
    // Services.PresenceState; function onAbsentChanged() { ... } }`
    // and read `.absent` in the handler.
    property bool absent: _lockActive || _hypridleIdle

    // ── Internal inputs ───────────────────────────────────────────
    property bool _lockActive: false
    property bool _hypridleIdle: false

    // ── Sidecar script resolution ────────────────────────────────
    // Qt.resolvedUrl returns file:///abs/path. Strip the scheme so
    // Process sees a bare absolute path.
    readonly property string _lockScriptPath: {
        var url = Qt.resolvedUrl("../bin/presence-monitor.sh").toString()
        return url.replace(/^file:\/\//, "")
    }

    // ── Lock-state monitor ───────────────────────────────────────
    Process {
        id: lockMon
        running: true
        command: [state._lockScriptPath]
        stdout: SplitParser {
            onRead: data => {
                var line = (data || "").trim()
                if (line === "LOCKED")        state._lockActive = true
                else if (line === "UNLOCKED") state._lockActive = false
            }
        }
        onRunningChanged: {
            if (!running) lockMonRespawn.start()
        }
    }
    Timer {
        id: lockMonRespawn
        interval: 5000
        repeat: false
        onTriggered: { if (!lockMon.running) lockMon.running = true }
    }

    // ── Hypridle idle-flag monitor ───────────────────────────────
    // Single long-lived bash loop; emits IDLE/ACTIVE only on
    // transitions. 3s poll cadence per spec §Chunk 3 AC.
    Process {
        id: hypridleMon
        running: true
        command: ["bash", "-c",
            "flag=\"${XDG_STATE_HOME:-$HOME/.local/state}/nostromo/hypridle-idle\"; " +
            "last=\"\"; " +
            "while :; do " +
              "if [ -e \"$flag\" ]; then cur=IDLE; else cur=ACTIVE; fi; " +
              "if [ \"$cur\" != \"$last\" ]; then printf '%s\\n' \"$cur\"; last=\"$cur\"; fi; " +
              "sleep 3; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: data => {
                var line = (data || "").trim()
                if (line === "IDLE")        state._hypridleIdle = true
                else if (line === "ACTIVE") state._hypridleIdle = false
            }
        }
        onRunningChanged: {
            if (!running) hypridleMonRespawn.start()
        }
    }
    Timer {
        id: hypridleMonRespawn
        interval: 5000
        repeat: false
        onTriggered: { if (!hypridleMon.running) hypridleMon.running = true }
    }
}
