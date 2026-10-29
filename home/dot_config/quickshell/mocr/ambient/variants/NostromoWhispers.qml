// Nostromo Whispers — slow amber scroll on the bottom third of the side
// monitors, 1/3 screen width from the outer edge.
//
// Both scope[0] (DP-2) and scope[1] (DP-4) render the scroll. The two
// monitors duplicate the viewing surface; v1 accepts the redundant
// emission.
//
// Content pipeline (FEAT-nostromo-llm, supersedes FEAT-nostromo-polish):
//   Services.JournalInterpreter (singleton)
//     ├─ owns the journalctl tail (was per-variant before this rewrite)
//     ├─ batches parsed objects, POSTs to local ollama (gemma3:4b)
//     ├─ emits semantic-summary entries via interpretedLine
//     └─ falls back to raw-formatted entries on any failure
//   This variant subscribes to interpretedLine and recapBurst, pushes
//   entries into _pending, and renders via the existing three-Text row
//   delegate. The render pipeline (slide animation, priority color,
//   category column, viewport geometry, opacity bump+decay) is
//   unchanged.
//
// Scroll model: DISCRETE slide on each new entry, NOT continuous pan.
// Per spec §Reactivity — "no artificial tween, the content is the
// reactivity, scroll is quiet when machine is quiet". Slide duration
// derives from lineHeight / scrollPxPerSec.
//
// Per slide:
//   - New entry from JournalInterpreter → push to _pending; if
//     slideAnim idle, drain one immediately.
//   - _drainOne: pop pending head, append to _lines (evicting oldest
//     if > maxLines), set scrollY=lineHeight (Column jumps one row
//     BELOW settled), start slideAnim which animates scrollY→0 Linear.
//   - While slideAnim running, new arrivals queue; onFinished drains
//     one at a time. _pending capped at maxPending (drop oldest on
//     overflow).
//
// OLED safety:
//   - Hard pause: AmbientLayer Loader.active destroys the variant on
//     fullscreen pause; resume rebuilds with empty buffer / idle
//     slideAnim. Same pattern as MatrixBezels / BladeRunnerStripes.
//   - Soft idle fade: REMOVED in FEAT-nostromo-llm chunk 6. The
//     sentinel-mode model from this spec needs the variant to remain
//     responsive during user absence so the return-recap burst lands
//     visibly. The 3-minute fade-to-zero from FEAT-nostromo-polish
//     would have darkened the scroll exactly when the recap is
//     supposed to surface. Stale-pixel risk remaining is the last
//     emitted line on quiet side monitors — accepted as the cost of
//     the sentinel value.
//
// Binding safety: `Process.running` is no longer present here (the
// JournalInterpreter singleton owns the tail). This variant has no
// child processes; Component.onDestruction is empty.

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../services" as Services
import "../../theme"

Item {
    id: root

    // AmbientLayer passes modelData.name (e.g. "DP-2"). Variants resolve
    // their role from palette monitor_scope via Ambient.qml.
    required property string screenName

    // ── Role resolution ────────────────────────────────────
    readonly property int roleIndex: Ambient.monitorScope.indexOf(screenName)
    // Both side monitors scroll (no left/right role asymmetry).
    readonly property bool inScope: roleIndex === 0 || roleIndex === 1
    // Side of the monitor where the outer edge lives.
    // scope[0] → outer edge is LEFT (DP-2), scope[1] → outer edge is RIGHT (DP-4).
    readonly property bool outerLeft: roleIndex === 0

    visible: inScope

    // ── Region geometry (bottom third, 1/3 width from outer edge) ──
    readonly property int regionW: Math.floor(width / 3)
    readonly property int regionH: Math.floor(height / 3)
    readonly property int regionX: outerLeft ? 0 : width - regionW
    readonly property int regionY: height - regionH

    // ── Scroll + buffer configuration ───────────────────────
    readonly property int maxLines: 20
    readonly property int maxPending: 40
    readonly property int fontSize: 27
    readonly property int lineHeight: 44
    readonly property real scrollPxPerSec: 8.0
    readonly property int slideDurationMs: Math.round((lineHeight / scrollPxPerSec) * 1000)

    // Visible rolling buffer (newest at end).
    property var _lines: []
    // Pending queue — entries that arrived while slideAnim was running.
    property var _pending: []

    // ── Opacity ───────────────────────────────────────────
    // Permanently full alpha (modulated only by Ambient.maxOpacity).
    // The 0.35/0.65 bump+decay machinery served the old non-readMode
    // baseline; with readMode baked in (FEAT-nostromo-readability) the
    // scroll lives at full alpha, so the dim base + bump is dead weight.
    // Hard pause via Loader.active is the sole OLED safeguard.
    opacity: Ambient.maxOpacity

    // ── Slide animation ─────────────────────────────────────
    // scrollY = 0 → Column settled (bottom-anchored at viewport.bottom).
    // scrollY = lineHeight → Column one line BELOW settled (off-screen).
    // Column.anchors.bottomMargin: -scrollY (negative bottomMargin pushes
    // the column DOWN in Qt Quick anchor math), so as scrollY animates
    // lineHeight → 0, bottomMargin goes -lineHeight → 0, Column rises.
    property real scrollY: 0

    // Last-row height seed for the slide animation. Updated in
    // _drainOne before slideAnim.start(); the NumberAnimation reads
    // it for `from` and `duration` so two-line rows slide their full
    // height at the same px/sec cadence as one-line rows.
    property real _lastRowHeight: lineHeight

    NumberAnimation {
        id: slideAnim
        target: root
        property: "scrollY"
        from: root._lastRowHeight
        to: 0
        duration: Math.round((root._lastRowHeight / root.scrollPxPerSec) * 1000)
        easing.type: Easing.Linear
        onFinished: {
            if (root._pending.length > 0) root._drainOne()
        }
    }

    // Approximate the wrapped-row height for the slide-anim seed. The
    // delegate's actual height is bound to msgText.contentHeight (exact),
    // but the animation needs a value at drain-time before layout has
    // run. Heuristic: project msg width against the available column
    // pixels; if it exceeds, the row will wrap to two lines.
    function _projectedRowHeight(line) {
        var avail = col.width
                    - Math.ceil(root.fontSize * 0.6 * ((line.time || "").length))
                    - root.fontSize * 6   // cat column (Layout.preferredWidth)
                    - 2 * 8               // RowLayout.spacing × 2
        var needed = root.fontSize * 0.6 * ((line.msg || "").length)
        return needed > avail ? root.lineHeight * 2 : root.lineHeight
    }

    function _drainOne() {
        if (_pending.length === 0) return
        var line = _pending[0]
        _pending = _pending.slice(1)
        var next = _lines.slice()
        next.push(line)
        if (next.length > maxLines) next = next.slice(1)
        _lines = next
        _lastRowHeight = _projectedRowHeight(line)
        scrollY = _lastRowHeight
        slideAnim.start()
    }

    // ── Priority → color ────────────────────────────────────
    // JournalInterpreter emits priority strings "0".."6" (7 is filtered
    // upstream). _priorityColor covers the full range and defaults to
    // base amber when PRIORITY is missing (some native-protocol writers
    // omit it; default to "info" not "debug" so missing-priority
    // entries still render at the same level).
    readonly property color priorityColorCrit: "#ff8855"      // 0..3 — emerg/alert/crit/err
    readonly property color priorityColorWarn: "#ffb040"      // 4    — warning
    readonly property color priorityColorBase: Colors.amber   // 5..6 — notice/info (+ missing)

    function _priorityColor(priority: string): color {
        if (!priority) return priorityColorBase
        var p = parseInt(priority, 10)
        if (isNaN(p)) return priorityColorBase
        if (p <= 3) return priorityColorCrit
        if (p === 4) return priorityColorWarn
        return priorityColorBase
    }

    // ── Interpreter subscription ───────────────────────────
    // Single-line append-and-drain: same shape as the old _pushLine
    // tail. The entry already has {time, cat, msg, priority} so no
    // parse/filter/format pass is needed here.
    function _onInterpretedLine(entry) {
        if (!entry || !root.inScope) return
        var next = _pending.slice()
        next.push(entry)
        while (next.length > maxPending) next = next.slice(1)
        _pending = next
        if (!slideAnim.running) _drainOne()
    }

    // Burst handler — three callers feed it via the same recapBurst signal:
    //
    //   1. Recap path (FEAT-nostromo-llm chunk 5): JournalInterpreter.
    //      consolidateRecap() emits 3–6 entries with priority forced to
    //      "3" (red-amber tint via _priorityColor) on absent → present
    //      transitions.
    //   2. Investigate path (FEAT-nostromo-investigate): on Super+J,
    //      JournalInterpreter.investigateLast() emits 3–5 cat="INVEST"
    //      entries with priority "4" (warning amber). The entry's cat
    //      column visually distinguishes investigate output from recap
    //      output; no delegate change is required.
    //   3. Console-ready synthetic burst (FEAT-nostromo-console chunk 5):
    //      after a successful investigate, the strip receives ONE
    //      cat="INVEST" entry — msg="Action items ready. Press Super+J."
    //      — instead of the full action list. The full content flows to
    //      the Console via investigateReady. The strip's role for
    //      INVEST is the peripheral signal, not the delivery surface.
    //
    // All three callers shape entries into the standard {time, cat, msg,
    // priority} record, so the burst handler treats them identically.
    function _onRecapBurst(entries) {
        console.log("[NW] _onRecapBurst screen=" + screenName + " roleIndex=" + roleIndex + " inScope=" + root.inScope + " entriesLen=" + (entries ? entries.length : "null"))
        if (!entries || !root.inScope) return
        if (entries.length === 0) return
        var next = _pending.slice()
        for (var i = 0; i < entries.length; i++) next.push(entries[i])
        while (next.length > maxPending) next = next.slice(1)
        _pending = next
        if (!slideAnim.running) _drainOne()
    }

    Connections {
        target: Services.JournalInterpreter
        function onInterpretedLine(entry) { root._onInterpretedLine(entry) }
        function onRecapBurst(entries)    { root._onRecapBurst(entries) }
    }

    // ── Presence subscription (chunk 5) ───────────────────
    // Fires consolidateRecap() once per absent true → false transition.
    // _wasAbsent is seeded at Component.onCompleted so a variant
    // created mid-absence does not emit a recap on its first
    // transition (the absence "belonged to" a prior variant lifetime).
    // `consolidateRecap` itself is single-flight inside the singleton,
    // so simultaneous fires from both monitors collapse to one LLM
    // call and one `recapBurst` emission — both monitors still receive
    // the signal via the Connections block above.
    property bool _wasAbsent: false

    Connections {
        target: Services.PresenceState
        function onAbsentChanged() {
            var nowAbsent = Services.PresenceState.absent
            if (root._wasAbsent && !nowAbsent) {
                Services.JournalInterpreter.consolidateRecap()
            }
            root._wasAbsent = nowAbsent
        }
    }

    Component.onCompleted: {
        _wasAbsent = Services.PresenceState.absent
    }

    Component.onDestruction: {
        // No child processes to stop — the journalctl tail moved into
        // Services.JournalInterpreter in this rewrite.
    }

    // ── Viewport + scrolling column ─────────────────────────
    Item {
        id: viewport
        x: root.regionX
        y: root.regionY
        width: root.regionW
        height: root.regionH
        clip: true

        Column {
            id: col
            width: viewport.width
            spacing: 0
            anchors.bottom: viewport.bottom
            anchors.bottomMargin: -root.scrollY

            Repeater {
                model: root._lines
                // Row delegate: three Texts with independent color/weight.
                //   time  → dimmed amber (reference field, recedes visually)
                //   cat   → bright amber, fixed-width (category column
                //           aligns across rows — the eye lands here first)
                //   msg   → priority-tinted (0..3 red-amber, 4 bright,
                //           5..6 base) — severity at a glance
                delegate: RowLayout {
                    id: row
                    required property var modelData
                    width: col.width
                    // Single-line rows take lineHeight; two-line rows
                    // grow to the wrapped contentHeight. msgText is
                    // exact; the slide-anim seed in _drainOne uses the
                    // projected approximation instead.
                    height: Math.max(root.lineHeight,
                                     Math.ceil(msgText.contentHeight))
                    spacing: 8

                    Text {
                        text: row.modelData.time
                        color: Qt.rgba(0.85, 0.70, 0.45, 1.0)
                        font.family: Geometry.fontFamily
                        font.pixelSize: root.fontSize
                        textFormat: Text.PlainText
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: row.modelData.cat
                        color: Qt.rgba(1.0, 0.80, 0.35, 1.0)
                        font.family: Geometry.fontFamily
                        font.pixelSize: root.fontSize
                        textFormat: Text.PlainText
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        Layout.preferredWidth: root.fontSize * 6
                    }
                    Text {
                        id: msgText
                        text: row.modelData.msg
                        color: root._priorityColor(row.modelData.priority)
                        font.family: Geometry.fontFamily
                        font.pixelSize: root.fontSize
                        textFormat: Text.PlainText
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
