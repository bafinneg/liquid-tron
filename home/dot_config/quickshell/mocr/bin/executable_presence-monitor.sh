#!/usr/bin/env bash
# presence-monitor.sh — lock-state sidecar for FEAT-nostromo-llm PresenceState.
#
# Emits a single line (LOCKED or UNLOCKED) for every logind LockedHint
# transition, newline-terminated, on stdout. PresenceState.qml wires the
# output into the `_lockActive` property via a SplitParser.
#
# Primary path: `gdbus monitor` on the system bus, watching logind's
# session object. gdbus uses plain AddMatch to subscribe to signals
# addressed to any listener — no privileged operations, no security-
# policy denials in the journal. This replaced the original
# `dbus-monitor` approach, which as a debugging tool always tries
# `org.freedesktop.DBus.Monitoring.BecomeMonitor` first; that method
# is restricted to root by dbus-broker on Arch, producing a
# "security policy denied ... BecomeMonitor" line in the system
# journal every time the sidecar started. dbus-monitor does fall
# back to AddMatch silently, so the original code worked — but the
# denial messages fed back into JournalInterpreter's tail, causing
# the ambient scroll to narrate its own plumbing noise. gdbus never
# attempts the restricted call and keeps the journal clean.
#
# Fallback: if gdbus is absent (unlikely; it ships in glib2 which is
# a near-universal GTK dependency), poll `loginctl show-session auto
# -p LockedHint --value` every 5s.
#
# The first line emitted is ALWAYS the current state at process start
# so PresenceState can seed `_lockActive` without waiting for the
# first transition. Subsequent lines fire only on actual transitions.
set -euo pipefail

emit() { printf '%s\n' "$1"; }

current_state() {
    local v
    v=$(loginctl show-session auto -p LockedHint --value 2>/dev/null || echo "no")
    [ "$v" = "yes" ] && echo "LOCKED" || echo "UNLOCKED"
}

# Seed PresenceState with the current state before waiting on any signal.
initial=$(current_state)
emit "$initial"
last="$initial"

if command -v gdbus >/dev/null 2>&1; then
    # Event-driven path. `gdbus monitor` prints one line per signal
    # from the watched object. We filter for PropertiesChanged
    # mentions of LockedHint, then re-read the value via loginctl
    # (the signal payload does contain the new value but gdbus's
    # output format is not guaranteed stable across glib releases;
    # loginctl is the canonical source and runs in under 10 ms).
    gdbus monitor \
        --system \
        --dest org.freedesktop.login1 \
        --object-path /org/freedesktop/login1/session/auto |
    while IFS= read -r line; do
        if printf '%s' "$line" | grep -q 'LockedHint'; then
            current=$(current_state)
            if [ "$current" != "$last" ]; then
                emit "$current"
                last="$current"
            fi
        fi
    done
else
    # Polling fallback. 5s cadence matches the spec; the polling loop is
    # intentionally simple — no jitter, no backoff.
    while :; do
        sleep 5
        current=$(current_state)
        if [ "$current" != "$last" ]; then
            emit "$current"
            last="$current"
        fi
    done
fi
