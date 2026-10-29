// ActionExecutor — runs an investigate-burst entry's argv with allowlist
// enforcement (FEAT-nostromo-console chunk 2). The console row delegate
// instantiates one of these per active execution and binds argv,
// actionKind, and the parsed allowlist; calling run() validates and
// spawns the Process.
//
// Public API surface (matches spec §Chunk 2):
//
//   inputs:
//     argv             — string[]; the command vector
//     actionKind       — schema enum: read_only_shell | mutating_shell |
//                        file_open | doc_link | none
//     allowlist        — parsed JSON object loaded from
//                        policy/action-allowlist.json
//
//   outputs:
//     running          — true while the Process is live
//     exitCode         — -1 sentinel until Process exits
//     stdoutBuffer     — bounded 16 KB rolling buffer of stdout
//     stderrBuffer     — bounded 16 KB rolling buffer of stderr
//     downgradeReason  — non-empty when run() blocked; the row delegate
//                        renders it as the row's denial tooltip
//
//   signals:
//     completed(int)   — fires after Process exit with the exit code
//     blocked(string)  — fires when allowlist enforcement denies argv;
//                        no Process is spawned
//
//   methods:
//     run()            — validate → spawn (or block)
//     cancel()         — SIGTERM, then SIGKILL after a 2-second grace
//
// The component does NOT load the allowlist itself — Console.qml owns
// the FileView that reads action-allowlist.json once at construction
// and binds it down. That keeps file I/O off the per-row hot path and
// lets the Console show a single banner if the file fails to parse.

import QtQuick
import Quickshell.Io

Item {
    id: executor
    visible: false
    width: 0; height: 0

    // ── Inputs ────────────────────────────────────────────────────
    property var argv: []
    property string actionKind: "none"
    property var allowlist: null

    // True when both polkit .policy files are installed AND the
    // allowlist exposes polkit_elevatable_binaries. False forces the
    // existing copy_only fallback regardless of allowlist contents.
    // Probed once at Console.qml construction (FileView checks against
    // /usr/share/polkit-1/actions/com.brian.nostromo.pacman.policy and
    // .../com.brian.nostromo.systemctl-system.policy).
    property bool polkitAvailable: false

    // ── Outputs ───────────────────────────────────────────────────
    property bool running: false
    property int exitCode: -1
    property string stdoutBuffer: ""
    property string stderrBuffer: ""
    property string downgradeReason: ""

    signal completed(int code)
    signal blocked(string reason)

    // ── Tunables ──────────────────────────────────────────────────
    // Buffer cap is per-stream. Past the cap we keep the most recent
    // bytes plus a single "... [truncated] ..." prefix so the user
    // sees that truncation occurred and which end was kept (the tail,
    // since most diagnostic output is interesting at the end).
    readonly property int bufferCapBytes: 16 * 1024
    // Grace window between SIGTERM and SIGKILL on cancel(). Long
    // enough that journalctl/curl/etc finish flushing; short enough
    // that a stuck child does not survive the user pressing Esc.
    readonly property int killGraceMs: 2000

    // ── Internal state ────────────────────────────────────────────
    // Truncation marker prepended once on first overflow. Subsequent
    // appends just rotate the bounded tail.
    readonly property string _truncMarker: "... [truncated] ...\n"

    // ── Process + parsers ────────────────────────────────────────
    Process {
        id: proc
        running: false
        stdout: SplitParser {
            onRead: data => { executor._appendStdout(data + "\n") }
        }
        stderr: SplitParser {
            onRead: data => { executor._appendStderr(data + "\n") }
        }
        onExited: (code, status) => {
            executor.exitCode = code
            executor.running = false
            killTimer.stop()
            executor.completed(code)
        }
    }

    Timer {
        id: killTimer
        interval: executor.killGraceMs
        repeat: false
        onTriggered: {
            if (proc.running) proc.signal(9)
        }
    }

    // ── Public methods ───────────────────────────────────────────
    function run() {
        console.log("[EXEC] run actionKind=" + actionKind
            + " argv=" + JSON.stringify(argv))
        // Reset per-invocation state so re-runs from the same row do
        // not show stale stdout from the previous attempt.
        stdoutBuffer = ""
        stderrBuffer = ""
        exitCode = -1
        downgradeReason = ""

        var v = _validate()
        if (!v.ok) {
            console.log("[EXEC] validate failed: " + v.reason)
            downgradeReason = v.reason
            blocked(v.reason)
            return
        }

        console.log("[EXEC] spawning " + JSON.stringify(v.argv))
        proc.command = v.argv
        running = true
        proc.running = true
    }

    function cancel() {
        if (!running) return
        // SIGTERM first; the Timer escalates to SIGKILL if the child
        // does not exit within killGraceMs.
        proc.signal(15)
        killTimer.restart()
    }

    // ── Buffer helpers ───────────────────────────────────────────
    function _appendStdout(chunk) {
        stdoutBuffer = _appendBounded(stdoutBuffer, chunk)
    }

    function _appendStderr(chunk) {
        stderrBuffer = _appendBounded(stderrBuffer, chunk)
    }

    function _appendBounded(buf, chunk) {
        var combined = buf + chunk
        if (combined.length <= bufferCapBytes) return combined
        // Keep the most recent (cap - markerLen) bytes; prepend marker.
        var keep = bufferCapBytes - _truncMarker.length
        if (keep < 0) keep = 0
        return _truncMarker + combined.substring(combined.length - keep)
    }

    // ── Allowlist enforcement ────────────────────────────────────
    // Returns { ok: bool, argv: string[], reason: string }.
    // On ok=true, argv is the vector to spawn (may be re-prefixed —
    // doc_link / file_open prepend xdg-open). On ok=false, reason
    // explains why for the row tooltip and the blocked() signal.
    function _validate() {
        if (!argv || !Array.isArray(argv) || argv.length === 0
            || actionKind === "none") {
            return _fail("Informational item — nothing to run.")
        }

        if (actionKind === "doc_link") {
            // Schema invariant (FEAT-nostromo-schema-bump): doc_link
            // argv has one element, validated http(s) at row-render
            // time. xdg-open handles the rest.
            return _ok(["xdg-open", argv[0]])
        }

        if (actionKind === "file_open") {
            // Schema invariant: argv[0] is an absolute path. xdg-open
            // dispatches to the user's editor / file manager.
            return _ok(["xdg-open", argv[0]])
        }

        if (!allowlist) {
            return _fail("Allowlist unavailable — copy and run manually.")
        }

        if (actionKind === "read_only_shell") {
            if (!_inList(allowlist.read_only_binaries, argv[0])) {
                return _fail("Binary `" + argv[0]
                    + "` not in read-only allowlist — copy and run manually.")
            }
            return _ok(argv)
        }

        if (actionKind === "mutating_shell") {
            if (!_inList(allowlist.mutating_binaries, argv[0])) {
                return _fail("Binary `" + argv[0]
                    + "` not in mutating allowlist — copy and run manually.")
            }

            // SCOPE CHECK — systemctl --user lives outside the
            // root-required gate AND uses a separate subcommand list
            // (the user-scope subcommand list is a strict subset of
            // the system-scope one but the wiring is independent so
            // future divergence is cheap).
            if (argv[0] === "systemctl" && argv[1] === "--user") {
                if (argv.length < 3) {
                    return _fail("systemctl --user requires a subcommand — copy and run manually.")
                }
                if (!_inList(allowlist.systemctl_user_subcommand_allowlist, argv[2])) {
                    return _fail("Unknown user-scope systemctl subcommand `"
                        + argv[2] + "` — copy and run manually.")
                }
                return _ok(argv)
            }

            // ROOT-REQUIRED GUARD — applied AFTER the user-scope
            // exemption above. v2 routes through pkexec when the
            // policy files are present on disk AND the allowlist
            // exposes the binary as polkit-elevatable. Falls back to
            // the v1 copy_only behavior when either gate fails.
            if (_inList(allowlist.polkit_elevatable_binaries || [], argv[0])
                && polkitAvailable) {
                // Subcommand and flag checks still apply on the
                // unwrapped argv — they validate USER intent,
                // independent of how the binary is invoked. Run them
                // BEFORE prepending pkexec so the indices match the
                // existing list contracts.
                var subListPk = (allowlist.mutating_subcommand_allowlist
                    || ({}))[argv[0]]
                if (subListPk) {
                    if (argv.length < 2) {
                        return _fail("Binary `" + argv[0]
                            + "` requires a subcommand — copy and run manually.")
                    }
                    if (!_inList(subListPk, argv[1])) {
                        return _fail("Unknown subcommand `" + argv[1]
                            + "` for `" + argv[0]
                            + "` — copy and run manually.")
                    }
                }
                // pkexec wrap. Resolve the binary to its absolute
                // path so the invocation matches what the .policy
                // file's exec.path annotation declares (pkexec
                // compares argv[1] against the annotation literally,
                // not by basename).
                //
                // pkexec exit-code semantics surfaced through the
                // executor's `completed` signal:
                //   127 — auth dialog dismissed (cancel / Esc)
                //   126 — not authorized
                //   any other code — the wrapped binary's exit
                // The row's amber stderr block already renders
                // non-zero exits; no special handling needed here.
                var absPath = _absolutePathFor(argv[0])
                if (!absPath) {
                    return _fail("Cannot resolve absolute path for `"
                        + argv[0] + "` — copy and run manually.")
                }
                var wrapped = ["pkexec", absPath].concat(argv.slice(1))
                return _ok(wrapped)
            }
            // Legacy v1 behaviour — recognise root-required binaries
            // that the v2 path did NOT take (allowlist missing the
            // new field, or polkit unavailable) and downgrade.
            if (_inList(allowlist.root_required_binaries || [], argv[0])) {
                return _fail("Requires root — copy and run manually.")
            }

            // SUBCOMMAND CHECK
            var subList = (allowlist.mutating_subcommand_allowlist
                || ({}))[argv[0]]
            if (subList) {
                if (argv.length < 2) {
                    return _fail("Binary `" + argv[0]
                        + "` requires a subcommand — copy and run manually.")
                }
                if (!_inList(subList, argv[1])) {
                    return _fail("Unknown subcommand `" + argv[1]
                        + "` for `" + argv[0]
                        + "` — copy and run manually.")
                }
            }

            // FLAG CHECK — tailscale set has its own flag allowlist
            // because `tailscale set` accepts cluster-wide options
            // (advertise-exit-node, shields-up=false) the binary
            // gate alone does not catch.
            if (argv[0] === "tailscale" && argv[1] === "set") {
                if (argv.length < 3) {
                    return _fail("tailscale set requires a flag — copy and run manually.")
                }
                if (!_inList(allowlist.tailscale_set_flag_allowlist, argv[2])) {
                    return _fail("tailscale set flag `" + argv[2]
                        + "` not in allowlist — copy and run manually.")
                }
            }

            return _ok(argv)
        }

        return _fail("Unknown action_kind `" + actionKind + "`.")
    }

    function _inList(list, value) {
        if (!list || !Array.isArray(list)) return false
        for (var i = 0; i < list.length; i++) {
            if (list[i] === value) return true
        }
        return false
    }

    // Hard-coded absolute path map for the v1 polkit-elevatable
    // binaries. Keeping this static avoids spawning `which` at
    // validate time. New polkit-elevatable binaries added in
    // follow-up specs MUST add their absolute path here AND ship a
    // corresponding .policy file with a matching exec.path annotation.
    function _absolutePathFor(binary) {
        var paths = {
            "pacman":    "/usr/bin/pacman",
            "systemctl": "/usr/bin/systemctl"
        }
        return paths[binary] || ""
    }

    function _ok(argvOut) {
        return { ok: true, argv: argvOut, reason: "" }
    }

    function _fail(reason) {
        return { ok: false, argv: [], reason: reason }
    }
}
