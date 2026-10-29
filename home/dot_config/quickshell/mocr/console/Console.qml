// Console — the Nostromo Console surface (FEAT-nostromo-console chunk 4).
//
// PopupWindow anchored to the DP-3 bar, summoned by Super+J via the
// `console.toggle` IPC handler on JournalInterpreter. Two stacked panes
// (toggled via a tab strip at the top):
//
//   1. Recent — last N emitted ambient lines from JournalInterpreter's
//      recentEntries ring. Click [Investigate] on any row to fire a
//      targeted investigate against that entry's emitTs (amendment
//      2026-04-26 §3). This is the default pane on open.
//
//   2. Investigate — the most recent INVEST burst (rendered via
//      ConsoleRow with full action machinery). Replaced wholesale on
//      each investigateReady; previous rows + their executors are
//      destroyed by the model swap.
//
// Click-outside dismissal is HyprlandFocusGrab. Esc also closes.
// Toggling Super+J while open closes the console; while closed it
// opens to the Recent pane (amendment 2026-04-26 §5 — opening does NOT
// auto-fire investigate; the user picks an entry or clicks the
// "Investigate latest" button to invoke the legacy untargeted path).
//
// The allowlist is loaded once at construction via FileView. Parse
// failure disables the [Run] buttons (rows fall back to [Copy]) and a
// banner explains.

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../theme"
import "../services" as Services

PopupWindow {
    id: root

    // ── Inputs ────────────────────────────────────────────────────
    // The bar PanelWindow this PopupWindow anchors to. Provided by
    // shell.qml from Services.NotificationService.centerBar; the
    // popup renders nothing until the bridge resolves.
    property var bar: null

    // ── Anchor / geometry ────────────────────────────────────────
    // Anchored below the DP-3 bar, horizontally centered. PopupWindow
    // expects anchor.rect coordinates in the parent window's frame.
    anchor.window: bar
    anchor.rect.x: bar ? Math.max(0, (bar.width - root.implicitWidth) / 2) : 0
    anchor.rect.y: bar ? bar.height + 8 : 0
    anchor.rect.width: root.implicitWidth
    anchor.rect.height: root.implicitHeight

    implicitWidth: 720
    implicitHeight: 520
    visible: false
    color: "transparent"

    // ── State ────────────────────────────────────────────────────
    // _entries: latest INVEST burst, REPLACED (not appended) on each
    // investigateReady — preserves chunk-4 spec verification "second
    // investigateReady REPLACES the row list".
    property var _entries: []
    // _allowlist: parsed JSON object loaded once via FileView. Null if
    // the file failed to parse — banner surfaces the problem and rows
    // render with [Run] disabled.
    property var _allowlist: null
    property bool _allowlistFailed: false
    // Polkit-policy presence probes. Both .policy files must load for
    // _polkitAvailable to be true; either failure forces the
    // ActionExecutor copy_only fallback for root-required binaries.
    // Mirrors the allowlist FileView's load-once-at-construction
    // pattern; same path conventions as the deployed
    // /usr/share/polkit-1/actions/ system tree.
    property bool _pacmanPolicyLoaded: false
    property bool _systemctlPolicyLoaded: false
    readonly property bool _polkitAvailable: _pacmanPolicyLoaded
        && _systemctlPolicyLoaded
    // mode: "recent" | "invest" — drives which ListView is visible.
    // Default "recent" so opening lands on the recent pane (amendment).
    property string mode: "recent"
    // _rawContextForInvest: passed to ConsoleRow as rawContext for the
    // INVEST pane only. Pulled fresh from JournalInterpreter.lastEmit
    // each time a burst lands.
    property var _rawContextForInvest: []

    // _investigating: true while an investigate IPC is in flight. Set
    // by _fireInvestigate(); cleared by either onInvestigateReady,
    // onInvestigateFailed, or the watchdog Timer below. Drives the
    // "Investigating…" placeholder + button-disabled state across the
    // surface so the user gets immediate feedback for what is otherwise
    // a multi-second LLM round-trip on qwen2.5:14b.
    property bool _investigating: false

    // _streamBuf: token-by-token output from the LLM during streaming.
    // Reset on investigateThinkingStarted, appended to on each
    // investigateProgress chunk, persists through investigateReady
    // (alongside the rows) AND through investigateFailed (so the
    // user can read what the model produced even when it didn't
    // map to actionable rows). Cleared at the start of the next
    // investigation.
    property string _streamBuf: ""

    // _lastFailureReason: human-readable explanation surfaced inside
    // the Invest pane when an investigation produces no rows. Set by
    // onInvestigateFailed; cleared on investigateThinkingStarted /
    // investigateReady. Drives the failure banner below.
    property string _lastFailureReason: ""

    // _resolved: derived flag — true when the most recent eval verdict
    // contains an entry whose msg starts with "Resolved." and
    // action_kind is "none". When true, a green banner appears at the
    // top of the body inviting the user to close ([Done]).
    readonly property bool _resolved: {
        if (!_entries || _entries.length === 0) return false
        for (var i = 0; i < _entries.length; i++) {
            var e = _entries[i]
            if (!e || typeof e !== "object") continue
            var msg = e.msg || ""
            if (e.action_kind === "none" && /^resolved[.:]/i.test(msg)) {
                return true
            }
        }
        return false
    }

    // _lastInvestigatedEntryId: emitTs of the entry the current
    // _entries burst was generated from. Captured by _fireInvestigate
    // so the [Ask for fixes] resolver-request button knows which
    // source entry to ask the LLM about. Empty string = "Investigate
    // latest" (untargeted) path.
    property string _lastInvestigatedEntryId: ""

    // _allInvestigations: derived flag — true when the current Invest
    // burst contains entries AND every entry has
    // action_kind="read_only_shell". Drives the "These are all
    // investigations. Ask for fixes?" banner. False when the burst
    // includes any mutating_shell / file_open / doc_link, or when
    // _entries is empty.
    readonly property bool _allInvestigations: {
        if (!_entries || _entries.length === 0) return false
        for (var i = 0; i < _entries.length; i++) {
            var e = _entries[i]
            if (!e || typeof e !== "object") return false
            if (e.action_kind !== "read_only_shell") return false
        }
        return true
    }

    function _resetConsoleState() {
        // Called by [Done] and on console close → open transitions so
        // a stale "Resolved" banner / failed reason / row list doesn't
        // leak into the next session.
        root._entries = []
        root._streamBuf = ""
        root._lastFailureReason = ""
        root._rawContextForInvest = []
        root._lastInvestigatedEntryId = ""
        root.mode = "recent"
    }

    function _askForFixes() {
        // Ask the LLM for resolver-only actions against the same
        // source entry that produced the current burst. Routes
        // through the same investigateProgress / investigateReady
        // signals so the UI handles it identically to a fresh
        // investigate — fresh stream, fresh rows.
        Services.JournalInterpreter.requestResolvers(
            root._lastInvestigatedEntryId)
    }

    // _copyConfirm: brief "Copied!" feedback on the stream panel's
    // [Copy] button. Flips true on click, back to false after 1.5s.
    property bool _copyConfirm: false

    Timer {
        id: copyConfirmTimer
        interval: 1500
        repeat: false
        onTriggered: root._copyConfirm = false
    }

    // Process for piping the reasoning trace into wl-copy via base64
    // (handles arbitrary multiline content with quotes/backslashes
    // safely — same pattern as the ollama call).
    Process {
        id: copyReasoningProc
        running: false
    }

    function _copyReasoningToClipboard() {
        if (root._streamBuf.length === 0) return
        var b64 = Qt.btoa(root._streamBuf)
        copyReasoningProc.command = ["bash", "-c",
            "printf '%s' '" + b64 + "' | base64 -d | wl-copy"
        ]
        copyReasoningProc.running = true
        root._copyConfirm = true
        copyConfirmTimer.restart()
    }

    // ── Allowlist load ───────────────────────────────────────────
    // FileView reads the JSON once at construction. The path matches
    // the policy directory shipped via stow + the spec body.
    FileView {
        id: allowlistFile
        path: Quickshell.env("HOME") + "/.config/quickshell/mocr/policy/action-allowlist.json"
        blockLoading: true
        onLoaded: {
            try {
                root._allowlist = JSON.parse(allowlistFile.text())
                root._allowlistFailed = false
            } catch (e) {
                root._allowlist = null
                root._allowlistFailed = true
                console.warn("[CONSOLE] allowlist parse failed: " + e)
            }
        }
        onLoadFailed: function(err) {
            root._allowlist = null
            root._allowlistFailed = true
            console.warn("[CONSOLE] allowlist load failed: " + err)
        }
    }

    // ── Polkit policy probes ────────────────────────────────────
    // FileView reads on each .policy file. Only checks presence /
    // readability — the actual policy semantics live in the kernel
    // polkit daemon. Either failure leaves _polkitAvailable false and
    // ActionExecutor falls back to copy_only for root-required
    // binaries (see FEAT-nostromo-console-polkit chunk 3).
    FileView {
        id: pacmanPolicyFile
        path: "/usr/share/polkit-1/actions/com.brian.nostromo.pacman.policy"
        blockLoading: true
        onLoaded: { root._pacmanPolicyLoaded = true }
        onLoadFailed: function(err) {
            root._pacmanPolicyLoaded = false
            console.log("[CONSOLE] pacman.policy probe miss: " + err)
        }
    }
    FileView {
        id: systemctlPolicyFile
        path: "/usr/share/polkit-1/actions/com.brian.nostromo.systemctl-system.policy"
        blockLoading: true
        onLoaded: { root._systemctlPolicyLoaded = true }
        onLoadFailed: function(err) {
            root._systemctlPolicyLoaded = false
            console.log("[CONSOLE] systemctl-system.policy probe miss: " + err)
        }
    }

    // ── Wayland-native click-outside dismissal ──────────────────
    HyprlandFocusGrab {
        windows: [root]
        active: root.visible
        onCleared: root.visible = false
    }

    // ── Signal wiring ────────────────────────────────────────────
    // investigateReady → swap _entries (chunk 4 contract — REPLACE
    // not append) and snapshot the raw context for ConsoleRow's
    // expanded view. Auto-switch to the Investigate pane so the user
    // sees the new burst immediately.
    //
    // consoleToggleRequested → if open, close. If closed, open to the
    // Recent pane (amendment §5: opening does NOT auto-fire
    // investigate; the user picks).
    Connections {
        target: Services.JournalInterpreter
        function onInvestigateReady(entries) {
            // Don't clear _streamBuf here — keep the reasoning trace
            // visible above the action rows so the user can review what
            // the model produced before committing to a click. Cleared
            // only on the next investigateThinkingStarted.
            root._investigating = false
            root._lastFailureReason = ""
            root._entries = entries || []
            var le = Services.JournalInterpreter.lastEmit
            root._rawContextForInvest = (le && le.raw) ? le.raw : []
            root.mode = "invest"
            root.visible = true
        }
        function onInvestigateFailed(reason) {
            // Keep the streamed trace (so the user can see what the
            // model produced) and surface the failure reason as a
            // banner inside the Invest pane. The strip-side recapBurst
            // already carries a one-line summary; the in-pane banner
            // gives the full explanation + a clear next step.
            root._investigating = false
            root._lastFailureReason = reason || "Investigation failed."
            // Make sure the user is looking at the pane that holds the
            // banner — auto-switching to invest costs nothing here.
            root.mode = "invest"
            root.visible = true
        }
        function onInvestigateThinkingStarted() {
            // Fired by JournalInterpreter._runOllamaStreaming() before
            // the curl Process starts. Reset entries, stream buffer,
            // and the prior failure reason — fresh slate for the new
            // run. Mode-switch to invest happens in _fireInvestigate
            // already; we don't need to repeat it here.
            root._streamBuf = ""
            root._entries = []
            root._lastFailureReason = ""
        }
        function onInvestigateProgress(chunk) {
            // Each chunk is the `.response` field of one ollama NDJSON
            // envelope — typically 1-3 tokens worth of characters.
            // Append to the buffer; the placeholder Text re-renders
            // and Flickable auto-scrolls to bottom (see binding below).
            root._streamBuf += chunk
        }
        function onConsoleToggleRequested() {
            if (root.visible) {
                root.visible = false
            } else {
                // Fresh open — reset stale state from any previous
                // session so the user always lands on a clean Recent
                // pane, no leftover banners from an earlier run.
                root._resetConsoleState()
                root.visible = true
            }
        }
    }

    // Watchdog. If neither investigateReady nor investigateFailed fires
    // within 35s (just past the 30s ollama request timeout in
    // JournalInterpreter), assume something dropped on the floor and
    // clear the busy flag so the surface re-enables. Defense in depth —
    // the signals above should always fire first.
    Timer {
        id: investigateWatchdog
        interval: 35000
        repeat: false
        running: root._investigating
        onTriggered: {
            console.warn("[CONSOLE] investigate watchdog fired — clearing _investigating")
            root._investigating = false
        }
    }

    // ── Esc closes ───────────────────────────────────────────────
    Shortcut {
        sequences: ["Escape"]
        enabled: root.visible
        onActivated: root.visible = false
    }

    // ── Chrome ───────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: Geometry.radiusChrome
        color: Qt.alpha(Colors.bg_alt, 0.92)
        border.width: Geometry.borderWidthAccent
        border.color: Colors.cyan

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            // ── Tab strip ────────────────────────────────────────
            Row {
                id: tabs
                width: parent.width
                spacing: 6

                Repeater {
                    model: [
                        { id: "recent", label: "Recent" },
                        { id: "invest", label: "Investigate" }
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool _active: root.mode === modelData.id
                        width: tabText.implicitWidth + 18
                        height: tabText.implicitHeight + 8
                        radius: Geometry.radiusInteractive
                        color: _active ? Qt.alpha(Colors.cyan, 0.20)
                            : tabMouse.containsMouse
                                ? Qt.alpha(Colors.bg_inset, 0.90)
                                : "transparent"
                        border.width: _active ? 1 : 0
                        border.color: Colors.cyan

                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent._active ? Colors.cyan : Colors.fg_dim
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize
                            font.weight: parent._active ? Font.Bold : Font.Medium
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.mode = modelData.id
                        }
                    }
                }

                // Spacer
                Item { width: 8; height: 1 }

                // "Investigate latest" button — only on Recent pane.
                // Provides the legacy untargeted-investigate path so
                // Brian can still trigger "summarize the most recent
                // batch" without picking a specific entry. See
                // amendment §5 for why this lives here rather than
                // wired to Super+J.
                Rectangle {
                    visible: root.mode === "recent"
                    width: investAllText.implicitWidth + 18
                    height: investAllText.implicitHeight + 8
                    radius: Geometry.radiusInteractive
                    color: (investAllMouse.containsMouse && !root._investigating)
                        ? Qt.alpha(Colors.cyan, 0.25) : Colors.bg_inset
                    border.width: 1
                    border.color: Colors.cyan
                    opacity: root._investigating ? 0.5 : 1.0

                    Text {
                        id: investAllText
                        anchors.centerIn: parent
                        text: root._investigating ? "Investigating…" : "Investigate latest"
                        color: Colors.cyan
                        font.family: Geometry.fontFamily
                        font.pixelSize: Geometry.fontSize
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: investAllMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root._investigating
                        cursorShape: root._investigating
                            ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: root._fireInvestigate("")
                    }
                }
            }

            // ── Allowlist banner (only on parse failure) ─────────
            Rectangle {
                visible: root._allowlistFailed
                width: parent.width
                implicitHeight: bannerText.implicitHeight + 10
                radius: Geometry.radiusInteractive
                color: Qt.alpha(Colors.amber, 0.10)
                border.width: 1
                border.color: Colors.amber

                Text {
                    id: bannerText
                    anchors.centerIn: parent
                    width: parent.width - 16
                    text: "Allowlist failed to load — read-only. Rows fall back to copy-to-clipboard."
                    color: Colors.amber
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize
                    font.weight: Geometry.fontWeight
                    wrapMode: Text.WordWrap
                }
            }

            // ── Body area ──────────────────────────────────────
            // Holds three regions stacked vertically:
            //   1. Stream panel — visible while _streamBuf.length > 0.
            //      Shows the LLM's raw output token-by-token while
            //      investigating, then persists as a "reasoning" trace
            //      after the burst lands so the user can review what
            //      the model produced before clicking [Run].
            //   2. ListView — the action rows (or recent entries on
            //      the Recent pane). Anchors below the stream panel
            //      when it's visible; takes the full body height
            //      otherwise.
            //   3. Empty-state placeholder — only when both panes are
            //      empty AND no streaming is happening.
            Item {
                id: bodyArea
                width: parent.width
                height: parent.height - tabs.implicitHeight
                    - (root._allowlistFailed ? 36 : 0) - 12

                // ── Stream panel ───────────────────────────────
                Rectangle {
                    id: streamPanel
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top

                    // Visibility: any time we have streamed content,
                    // whether we're still mid-stream or post-burst.
                    visible: root._streamBuf.length > 0 || root._investigating

                    // Cap stream panel height so action rows below
                    // remain on screen. While investigating with no
                    // rows yet (list empty), expand to fill the body.
                    readonly property real _maxHeight: list.count > 0
                        ? Math.min(220, bodyArea.height * 0.55)
                        : bodyArea.height
                    implicitHeight: _maxHeight
                    height: implicitHeight

                    color: Qt.alpha(Colors.bg_inset, 0.6)
                    radius: Geometry.radiusInteractive
                    border.width: 1
                    border.color: Qt.alpha(Colors.cyan, 0.30)

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        // Header row — label on left, [Copy] on right.
                        Item {
                            id: streamHeaderRow
                            width: parent.width
                            implicitHeight: Math.max(streamHeader.implicitHeight,
                                                      copyReasoningBtn.implicitHeight)

                            Text {
                                id: streamHeader
                                anchors.left: parent.left
                                anchors.right: copyReasoningBtn.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: root._investigating
                                    ? "Nostromo is thinking…"
                                    : "Nostromo's reasoning"
                                color: Colors.cyan
                                font.family: Geometry.fontFamily
                                font.pixelSize: Geometry.fontSize - 1
                                font.weight: Font.Medium
                                font.italic: root._investigating
                                opacity: root._investigating ? 0.85 : 0.65
                                elide: Text.ElideRight

                                SequentialAnimation on opacity {
                                    running: root._investigating
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.85; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                    NumberAnimation { from: 0.35; to: 0.85; duration: 800; easing.type: Easing.InOutQuad }
                                }
                            }

                            // [Copy] reasoning. Disabled while there's
                            // no buffer to copy. Briefly flips to
                            // "Copied!" on click for confirmation.
                            Rectangle {
                                id: copyReasoningBtn
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root._streamBuf.length > 0
                                width: copyReasoningText.implicitWidth + 14
                                implicitHeight: copyReasoningText.implicitHeight + 4
                                height: implicitHeight
                                radius: Geometry.radiusInteractive
                                color: copyReasoningMouse.containsMouse
                                    ? Qt.alpha(Colors.cyan, 0.25)
                                    : Colors.bg_inset
                                border.width: 1
                                border.color: Colors.cyan

                                Text {
                                    id: copyReasoningText
                                    anchors.centerIn: parent
                                    text: root._copyConfirm ? "Copied!" : "Copy"
                                    color: Colors.cyan
                                    font.family: Geometry.fontFamily
                                    font.pixelSize: Geometry.fontSize - 2
                                    font.weight: Font.Medium
                                }

                                MouseArea {
                                    id: copyReasoningMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root._copyReasoningToClipboard()
                                }
                            }
                        }

                        // Body — auto-scrolls while investigating,
                        // free-scroll afterwards. Empty before first
                        // token; placeholder dot dims/brightens to
                        // signal we're alive but waiting.
                        Flickable {
                            id: streamFlick
                            width: parent.width
                            height: parent.height - streamHeaderRow.height
                                - parent.spacing
                            contentWidth: streamText.width
                            contentHeight: streamText.height
                            clip: true
                            interactive: true
                            boundsBehavior: Flickable.StopAtBounds

                            Text {
                                id: streamText
                                width: streamFlick.width
                                text: root._streamBuf.length > 0
                                    ? root._streamBuf
                                    : "(waiting for first token…)"
                                color: root._streamBuf.length > 0
                                    ? Colors.fg : Colors.fg_dim
                                font.family: "monospace"
                                font.pixelSize: Geometry.fontSize - 2
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText

                                // Pin to bottom while investigating —
                                // typewriter effect keeps the latest
                                // tokens in view. After the burst
                                // lands we leave the user free to
                                // scroll up through the trace.
                                onHeightChanged: {
                                    if (root._investigating
                                        && streamText.height > streamFlick.height) {
                                        streamFlick.contentY =
                                            streamText.height - streamFlick.height
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Resolved banner ────────────────────────────
                // Shown when the latest investigate / eval burst
                // contained an entry whose msg starts with "Resolved."
                // and action_kind=none. The eval prompt instructs the
                // model to lead with "Resolved." exactly when the
                // action that just ran addressed the issue, so this is
                // the user's "you can stop now" signal. [Done] closes
                // the console and resets state so the next Super+J is
                // a fresh start.
                Rectangle {
                    id: resolvedBanner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: streamPanel.visible
                        ? streamPanel.bottom : parent.top
                    anchors.topMargin: streamPanel.visible ? 8 : 0
                    visible: root._resolved && !root._investigating
                    height: visible ? resolvedInner.implicitHeight + 14 : 0
                    color: Qt.alpha(Colors.green, 0.18)
                    radius: Geometry.radiusInteractive
                    border.width: 1
                    border.color: Colors.green

                    Item {
                        id: resolvedInner
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        implicitHeight: Math.max(resolvedText.implicitHeight,
                                                  doneBtn.implicitHeight)

                        Text {
                            id: resolvedCheck
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "✓"
                            color: Colors.green
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize + 4
                            font.weight: Font.Bold
                        }

                        Text {
                            id: resolvedText
                            anchors.left: resolvedCheck.right
                            anchors.right: doneBtn.left
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (!root._entries) return "Resolved."
                                for (var i = 0; i < root._entries.length; i++) {
                                    var e = root._entries[i]
                                    if (e && e.action_kind === "none"
                                        && /^resolved[.:]/i.test(e.msg || "")) {
                                        return e.msg
                                    }
                                }
                                return "Resolved."
                            }
                            color: Colors.green
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize
                            font.weight: Font.Medium
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            id: doneBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: doneText.implicitWidth + 18
                            implicitHeight: doneText.implicitHeight + 6
                            height: implicitHeight
                            radius: Geometry.radiusInteractive
                            color: doneMouse.containsMouse
                                ? Qt.alpha(Colors.green, 0.30)
                                : Colors.bg_inset
                            border.width: 1
                            border.color: Colors.green

                            Text {
                                id: doneText
                                anchors.centerIn: parent
                                text: "Done"
                                color: Colors.green
                                font.family: Geometry.fontFamily
                                font.pixelSize: Geometry.fontSize
                                font.weight: Font.Bold
                            }

                            MouseArea {
                                id: doneMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root._resetConsoleState()
                                    root.visible = false
                                }
                            }
                        }
                    }
                }

                // ── Failure banner ─────────────────────────────
                // Visible when a previous investigation/eval failed to
                // produce actionable rows. Holds the full reason text
                // (the strip's recapBurst already showed the one-liner)
                // plus a [Try again] button that re-fires the same
                // untargeted investigate. Stays put until the user
                // either retries or starts a different investigation.
                Rectangle {
                    id: failureBanner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: resolvedBanner.visible
                        ? resolvedBanner.bottom
                        : (streamPanel.visible
                            ? streamPanel.bottom : parent.top)
                    anchors.topMargin: (resolvedBanner.visible
                        || streamPanel.visible) ? 8 : 0
                    visible: root._lastFailureReason.length > 0
                        && !root._investigating
                        && !root._resolved
                    height: visible ? bannerInner.implicitHeight + 14 : 0
                    color: Qt.alpha(Colors.amber, 0.10)
                    radius: Geometry.radiusInteractive
                    border.width: 1
                    border.color: Colors.amber

                    Item {
                        id: bannerInner
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        implicitHeight: Math.max(failureText.implicitHeight,
                                                  retryBtn.implicitHeight)

                        Text {
                            id: failureText
                            anchors.left: parent.left
                            anchors.right: retryBtn.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._lastFailureReason
                            color: Colors.amber
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize - 1
                            font.weight: Geometry.fontWeight
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            id: retryBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: retryText.implicitWidth + 16
                            implicitHeight: retryText.implicitHeight + 6
                            height: implicitHeight
                            radius: Geometry.radiusInteractive
                            color: retryMouse.containsMouse
                                ? Qt.alpha(Colors.amber, 0.30)
                                : Colors.bg_inset
                            border.width: 1
                            border.color: Colors.amber

                            Text {
                                id: retryText
                                anchors.centerIn: parent
                                text: "Try again"
                                color: Colors.amber
                                font.family: Geometry.fontFamily
                                font.pixelSize: Geometry.fontSize - 1
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: retryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._fireInvestigate("")
                            }
                        }
                    }
                }

                // ── "Ask for fixes" banner ─────────────────────
                // Shown when the current Invest burst contains only
                // read_only_shell entries — the LLM proposed only
                // investigations, no resolvers. Click → fires
                // requestResolvers(entryId) which re-engages the LLM
                // with a resolver-only prompt. Same downstream as a
                // fresh investigate, so the UI handles it identically.
                Rectangle {
                    id: askForFixesBanner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: failureBanner.visible
                        ? failureBanner.bottom
                        : (resolvedBanner.visible
                            ? resolvedBanner.bottom
                            : (streamPanel.visible
                                ? streamPanel.bottom : parent.top))
                    anchors.topMargin: (failureBanner.visible
                        || resolvedBanner.visible
                        || streamPanel.visible) ? 8 : 0
                    visible: root.mode === "invest"
                        && root._allInvestigations
                        && !root._investigating
                        && !root._resolved
                        && root._lastFailureReason.length === 0
                    height: visible ? askInner.implicitHeight + 14 : 0
                    color: Qt.alpha(Colors.cyan, 0.10)
                    radius: Geometry.radiusInteractive
                    border.width: 1
                    border.color: Colors.cyan

                    Item {
                        id: askInner
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        implicitHeight: Math.max(askText.implicitHeight,
                                                  askBtn.implicitHeight)

                        Text {
                            id: askText
                            anchors.left: parent.left
                            anchors.right: askBtn.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: "These are all investigations. Want resolver actions instead?"
                            color: Colors.cyan
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize - 1
                            font.weight: Geometry.fontWeight
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            id: askBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: askBtnText.implicitWidth + 16
                            implicitHeight: askBtnText.implicitHeight + 6
                            height: implicitHeight
                            radius: Geometry.radiusInteractive
                            color: askBtnMouse.containsMouse
                                ? Qt.alpha(Colors.cyan, 0.30)
                                : Colors.bg_inset
                            border.width: 1
                            border.color: Colors.cyan

                            Text {
                                id: askBtnText
                                anchors.centerIn: parent
                                text: "Ask for fixes"
                                color: Colors.cyan
                                font.family: Geometry.fontFamily
                                font.pixelSize: Geometry.fontSize - 1
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: askBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._askForFixes()
                            }
                        }
                    }
                }

                // ── ListView ───────────────────────────────────
                ListView {
                    id: list
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: askForFixesBanner.visible
                        ? askForFixesBanner.bottom
                        : (failureBanner.visible
                            ? failureBanner.bottom
                            : (resolvedBanner.visible
                                ? resolvedBanner.bottom
                                : (streamPanel.visible
                                    ? streamPanel.bottom : parent.top)))
                    anchors.bottom: parent.bottom
                    anchors.topMargin: (askForFixesBanner.visible
                        || failureBanner.visible
                        || resolvedBanner.visible
                        || streamPanel.visible) ? 8 : 0
                    clip: true
                    spacing: 4
                    model: root.mode === "recent"
                        ? Services.JournalInterpreter.recentEntries
                        : root._entries
                    delegate: root.mode === "recent" ? recentDelegate : investDelegate
                }

                // ── Idle empty-state placeholder ──────────────
                // Shown only when the entire body would otherwise be
                // empty: not investigating, no stream trace, and the
                // active pane has no rows.
                Text {
                    id: emptyStateLabel
                    visible: !root._investigating
                        && root._streamBuf.length === 0
                        && root._lastFailureReason.length === 0
                        && list.count === 0
                    anchors.centerIn: parent
                    text: root.mode === "recent"
                        ? "No recent entries."
                        : "No investigation yet — pick an entry or click \"Investigate latest\"."
                    color: Colors.fg_dim
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize
                    font.weight: Geometry.fontWeight
                    wrapMode: Text.WordWrap
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    // ── Delegates ────────────────────────────────────────────────
    // investDelegate: full ConsoleRow with action machinery. Rendered
    // for the INVEST burst pane.
    Component {
        id: investDelegate
        ConsoleRow {
            entry: modelData
            rawContext: root._rawContextForInvest
            allowlist: root._allowlist
            polkitAvailable: root._polkitAvailable
        }
    }

    // recentDelegate: small one-line row for the Recent pane.
    // No expand state — just time + cat + msg + [Investigate] button.
    // Wired to fire `qs ipc call investigate now <emitTs>` against the
    // entry's emitTs (the targeting key minted by JournalInterpreter's
    // recent-entries ring).
    Component {
        id: recentDelegate
        Item {
            id: recentRow
            required property var modelData
            width: ListView.view ? ListView.view.width : 700
            implicitHeight: Math.max(recentText.implicitHeight,
                                      recentBtnText.implicitHeight) + 12

            readonly property color _priorityColor: {
                var p = modelData && modelData.priority
                    ? String(modelData.priority) : "4"
                if (p === "0" || p === "1") return Colors.red
                if (p === "2" || p === "3") return Colors.amber
                if (p === "4") return Colors.cyan
                return Colors.fg_dim
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Geometry.radiusInteractive
                color: recentMouse.containsMouse
                    ? Qt.alpha(Colors.bg_alt, 0.6) : "transparent"
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 2
                color: recentRow._priorityColor
                opacity: 0.85
            }

            Text {
                id: recentText
                anchors.left: parent.left
                anchors.right: recentBtn.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                text: {
                    var t = modelData && modelData.time ? modelData.time : ""
                    var c = modelData && modelData.cat ? modelData.cat : "?"
                    var m = modelData && modelData.msg ? modelData.msg : ""
                    return "[" + t + "] " + c + " | " + m
                }
                color: Colors.fg
                font.family: Geometry.fontFamily
                font.pixelSize: Geometry.fontSize
                font.weight: Geometry.fontWeight
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Rectangle {
                id: recentBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 6
                width: recentBtnText.implicitWidth + 18
                height: recentBtnText.implicitHeight + 6
                radius: Geometry.radiusInteractive
                color: (recentBtnMouse.containsMouse && !root._investigating)
                    ? Qt.alpha(Colors.cyan, 0.25) : Colors.bg_inset
                border.width: 1
                border.color: Colors.cyan
                opacity: root._investigating ? 0.5 : 1.0

                Text {
                    id: recentBtnText
                    anchors.centerIn: parent
                    text: root._investigating ? "Investigating…" : "Investigate"
                    color: Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize - 1
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: recentBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !root._investigating
                    cursorShape: root._investigating
                        ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: {
                        var id = modelData && modelData.emitTs
                            ? String(modelData.emitTs) : ""
                        root._fireInvestigate(id)
                    }
                }
            }

            // Whole-row click target — anywhere outside the
            // [Investigate] button fires the same investigation. The
            // explicit button stays as a redundant affordance for
            // discoverability, but the user shouldn't have to aim at
            // the small target. z: -1 keeps the button MouseArea on
            // top so its click handler still wins.
            MouseArea {
                id: recentMouse
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var id = recentRow.modelData
                        && recentRow.modelData.emitTs
                        ? String(recentRow.modelData.emitTs) : ""
                    root._fireInvestigate(id)
                }
            }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────
    // _fireInvestigate — spawns `qs -c mocr ipc call investigate now
    // [entryId]` so the JournalInterpreter does the work and emits a
    // burst back via investigateReady (which lands in our Connections
    // handler above and switches us to the Investigate pane).
    //
    // We use Quickshell.execDetached when available (cleaner: no
    // long-lived Process object, no exit handling). The capability is
    // present in Quickshell 0.2.1.
    function _fireInvestigate(entryId) {
        // Reject re-entry while a previous investigate is still in
        // flight. The IPC handler also gates this via
        // `_investigateInFlight`, but the buttons gate it visibly here.
        if (root._investigating) return
        root._investigating = true
        // Capture the source entry id for downstream actions like
        // [Ask for fixes] (resolver re-roll). Empty string is the
        // legitimate "Investigate latest" untargeted path.
        root._lastInvestigatedEntryId = entryId || ""
        // Immediate pane swap so the user sees the state change before
        // the LLM round-trip completes. Empty-state placeholder will
        // render "Investigating…" until the burst arrives.
        root.mode = "invest"
        var argv = ["qs", "-c", "mocr", "ipc", "call", "investigate", "now"]
        if (entryId && entryId.length > 0) argv.push(entryId)
        Quickshell.execDetached(argv)
    }
}
