// ConsoleRow — single row delegate for the Nostromo Console
// (FEAT-nostromo-console chunk 3).
//
// Renders one entry of the most-recent investigate burst as a clickable row
// with three visual states:
//
//   1. Collapsed   — single line, [priority-color] cat | msg, plus a
//                    right-edge icon hint (▶ / 📂 / 🔗 / ▾ / 📋).
//   2. Expanded    — same line plus a sub-block showing argv as a quoted
//                    shell command, the relevant raw context lines, and a
//                    [Run] button (or copy fallback). Mutating actions
//                    swap [Run] for an inline confirmation pill.
//   3. Running /
//      completed   — sub-block replaced by the ActionExecutor's stdout
//                    stream. Non-zero exit shows the exit code in amber
//                    plus any stderr.
//
// Mixed-burst handling: validator accepts both extended entries (with
// action_kind + action_argv) and legacy ones. Legacy entries (or true
// "none" entries) render with the ▾ icon, no [Run] button, and the
// "no action proposed" tooltip. They expand to show msg + raw context
// only.
//
// Each row owns one ActionExecutor instance, lazily created on first run
// (before that the property is null and only the validation/render paths
// touch the row). The row never spawns a Process directly — all argv
// validation + spawning is delegated to the executor.

import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "../services" as Services

Item {
    id: row

    // ── Inputs ────────────────────────────────────────────────────
    // entry shape (per FEAT-nostromo-schema-bump):
    //   { time, cat, msg, priority,
    //     action_kind?, action_argv?, action_label?, action_target? }
    // rawContext: array of stripped journal records that fed the LLM.
    //   Used by the expanded view to show the lines behind the row.
    // allowlist: parsed action-allowlist.json (shared, loaded once by
    //   Console.qml).
    property var entry: null
    property var rawContext: []
    property var allowlist: null
    // Threaded down from Console._polkitAvailable. Drives the icon /
    // [Run] gate for root-required-but-polkit-elevatable binaries
    // (pacman, system-scope systemctl). Forwarded verbatim to the
    // inline ActionExecutor.
    property bool polkitAvailable: false

    // ── Computed entry shape ─────────────────────────────────────
    // hasAction is the mixed-burst flag — false for legacy entries
    // (no action_kind field) AND for true "none" entries. Both cases
    // route through the same render path (▾ icon, no Run button).
    readonly property bool hasAction: !!entry
        && ("action_kind" in entry)
        && entry.action_kind !== "none"
    readonly property string actionKind: entry && entry.action_kind
        ? entry.action_kind : "none"
    readonly property var actionArgv: entry && entry.action_argv
        ? entry.action_argv : []

    // ── Row state ─────────────────────────────────────────────────
    // States advance: collapsed → expanded → (pill) → running → done.
    // Default-expanded so the [Run] button is visible immediately —
    // the user doesn't need to click the row first to discover the
    // action. Click on the row (rowMouse) still toggles, so they can
    // collapse if they want a denser view.
    property bool expanded: true
    property bool pillVisible: false
    property bool ranAtLeastOnce: false

    // _evalScheduled: true between action-completes and auto-eval-fires.
    // Drives the "Awaiting evaluation…" hint inside the run-block so
    // the user knows the next step is on the way without having to
    // click [What happened?] manually.
    property bool _evalScheduled: false

    // ── [Ask] state ───────────────────────────────────────────────
    // Pill confirmation now offers Yes / No / Ask. "Ask" expands a
    // text-input + Send/Cancel inside the pill, fires
    // JournalInterpreter.askActionQuestion(...) on Send, then renders
    // the LLM's answer inline. The user can ask follow-up questions
    // or commit to Yes/No once they're satisfied.
    //
    // _askInputVisible — true while the input field + Send button are
    //   shown (after [Ask] click, before Send or Cancel).
    // _askInFlight — true while the singleton ollama call is pending.
    //   While true, this row is the one that will receive the
    //   actionAnswerReady / actionAnswerFailed signal — singleton
    //   single-flight guarantees uniqueness.
    // _askQuestion — current draft of the user's question text.
    // _askAnswer — most recent LLM answer, persists below the
    //   buttons so the user can re-read while deciding.
    property bool _askInputVisible: false
    property bool _askInFlight: false
    property string _askQuestion: ""
    property string _askAnswer: ""

    // Listen for the singleton's answer signals. Only react if THIS
    // row is the one that posted the question (single-flight at the
    // singleton means at most one row's _askInFlight is true).
    Connections {
        target: Services.JournalInterpreter
        function onActionAnswerReady(answer) {
            if (!row._askInFlight) return
            console.log("[ASK] answer landed, len=" + answer.length)
            row._askInFlight = false
            row._askAnswer = answer
        }
        function onActionAnswerFailed(reason) {
            if (!row._askInFlight) return
            console.log("[ASK] answer failed: " + reason)
            row._askInFlight = false
            row._askAnswer = "(error: " + reason + ")"
        }
    }

    // ── Layout ────────────────────────────────────────────────────
    width: ListView.view ? ListView.view.width : implicitWidth
    implicitWidth: 700
    implicitHeight: rowCol.implicitHeight + 8
    clip: true

    Component.onCompleted: {
        console.log("[ROW] created msg="
            + JSON.stringify((entry && entry.msg) || "").substring(0, 100)
            + " actionKind=" + actionKind
            + " hasAction=" + hasAction
            + " wouldAllow=" + _wouldAllow()
            + " expanded=" + expanded
            + " allowlistNull=" + (!allowlist)
            + " argv=" + JSON.stringify(actionArgv))
    }

    // ── Priority accent ──────────────────────────────────────────
    // Map DATA-voice priority (numeric string "0".."7") to a left-edge
    // accent color. 0/1 = red (emerg/alert), 2/3 = amber (crit/err),
    // 4 = cyan (warning — DATA's default), 5/6/7 = fg_dim (info+).
    readonly property color _priorityColor: {
        var p = entry && entry.priority ? String(entry.priority) : "4"
        if (p === "0" || p === "1") return Colors.red
        if (p === "2" || p === "3") return Colors.amber
        if (p === "4") return Colors.cyan
        return Colors.fg_dim
    }

    // ── ActionExecutor ───────────────────────────────────────────
    // Inlined directly (was a Loader before — the lazy gating turned
    // out to race with the synchronous _exec.run() call: Loader.active
    // flipped true on the first click but execLoader.item was still
    // null on the same tick when run() was invoked, so nothing ever
    // executed. Process is cheap when idle (no fork until command is
    // set + running=true), so always-on costs nothing meaningful.
    ActionExecutor {
        id: execInline
        argv: row.actionArgv
        actionKind: row.actionKind
        allowlist: row.allowlist
        polkitAvailable: row.polkitAvailable
        onCompleted: function(code) {
            console.log("[ROW] exec completed code=" + code
                + " argv=" + JSON.stringify(row.actionArgv))
            row.ranAtLeastOnce = true
            // Auto-evaluate shell actions after a 2s grace so the user
            // sees the output settle. Skip file_open / doc_link
            // (xdg-open completion isn't meaningful — the dispatched
            // app keeps running). The grace window also gives the
            // user time to scan the output before it gets replaced
            // by the eval's fresh row list.
            if (row.actionKind === "read_only_shell"
                || row.actionKind === "mutating_shell") {
                row._evalScheduled = true
                autoEvalTimer.restart()
            }
        }
        onBlocked: function(reason) {
            console.log("[ROW] exec blocked: " + reason
                + " argv=" + JSON.stringify(row.actionArgv))
            row.ranAtLeastOnce = true
            // The downgradeReason on the executor is the source of
            // truth; the row reads it via _exec.downgradeReason.
        }
    }
    readonly property var _exec: execInline

    Timer {
        id: autoEvalTimer
        interval: 2000
        repeat: false
        onTriggered: {
            row._evalScheduled = false
            row._onEvaluateClicked()
        }
    }

    function _ensureExec() {
        // No-op — kept for source compatibility with prior callers.
    }

    // ── Background + click target (collapsed row) ────────────────
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Geometry.radiusInteractive
        color: rowMouse.containsMouse
            ? Qt.alpha(Colors.bg_alt, 0.6)
            : "transparent"
        border.width: row.expanded ? 1 : 0
        border.color: Qt.alpha(Colors.cyan, 0.25)
    }

    Rectangle {
        // Left priority accent bar (full row height)
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 2
        color: row._priorityColor
        opacity: 0.85
    }

    Column {
        id: rowCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 4
        spacing: 4

        // ── Collapsed header (always visible) ────────────────────
        Item {
            id: header
            width: parent.width
            implicitHeight: Math.max(headerText.implicitHeight,
                                      iconText.implicitHeight) + 4

            Text {
                id: headerText
                anchors.left: parent.left
                anchors.right: iconText.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter

                text: {
                    var t = entry && entry.time ? entry.time : ""
                    var c = entry && entry.cat ? entry.cat : "?"
                    var m = entry && entry.msg ? entry.msg : ""
                    return "[" + t + "] " + c + " | " + m
                }
                color: Colors.fg
                font.family: Geometry.fontFamily
                font.pixelSize: Geometry.fontSize
                font.weight: Geometry.fontWeight
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Text {
                id: iconText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: row._iconForState()
                color: row._iconColor()
                font.family: Geometry.fontFamily
                font.pixelSize: Geometry.fontSize
                font.weight: Geometry.fontWeight

                // Tooltip via plain Text — no QtQuick.Controls dependency.
                // The visible-on-hover tooltip is handled by the row's
                // MouseArea below via toolTip property; we just expose
                // the string here for the test seam.
                property string tip: row._iconTip()
            }
        }

        // ── Expanded body ────────────────────────────────────────
        // Visible only while row.expanded === true and the row has
        // not yet started running. The body has three parts:
        //   1. Quoted argv (if entry has an action_argv)
        //   2. Raw context lines (if rawContext non-empty)
        //   3. Action button row ([Run] / [Copy] / pill)
        Column {
            id: expandedBody
            width: parent.width
            spacing: 6
            visible: row.expanded
                && !row.pillVisible
                && (!row._exec || !row._exec.running)
                && !row.ranAtLeastOnce
            opacity: visible ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.durationPopover
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.decay
                }
            }

            // Quoted shell command rendering
            Text {
                visible: row.actionArgv.length > 0
                width: parent.width
                text: "$ " + row._quoteArgv(row.actionArgv)
                color: Colors.cyan
                font.family: Geometry.fontFamily
                font.pixelSize: Geometry.fontSize
                font.weight: Font.Medium
                wrapMode: Text.WrapAnywhere
            }

            // Raw context lines (truncated to first 6 for readability;
            // the spec wants "the relevant lines that fed the LLM" and
            // 6 keeps the row compact even on very long bursts).
            Repeater {
                model: row._contextSlice(rawContext, 6)
                Text {
                    required property var modelData
                    width: expandedBody.width
                    text: row._renderRaw(modelData)
                    color: Colors.fg_dim
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize - 2
                    font.weight: Geometry.fontWeight
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideNone
                }
            }

        }

        // ── Action button row ────────────────────────────────────
        // Promoted out of expandedBody (was a child of it) so that
        // visibility depends only on action presence, not on the
        // expanded-state composite gate. The user kept reporting
        // "no action present" when expanded, pillVisible, _exec.running,
        // and ranAtLeastOnce all had to align — too many ways for
        // [Run] to silently disappear. Now the buttons live next to
        // the header and stay visible whenever the entry has an
        // action AND we're not actively running / pill-confirming.
        Row {
            spacing: 8
            visible: (row.hasAction || row._actionKindIsLink())
                && !row.pillVisible
                && (!row._exec || !row._exec.running)
                && !row.ranAtLeastOnce

            // [Run] button — only visible when allowlist permits.
            // For mutating_shell, clicking shows the pill instead
            // of running directly.
            Rectangle {
                visible: row._wouldAllow()
                width: runText.implicitWidth + 16
                height: runText.implicitHeight + 6
                radius: Geometry.radiusInteractive
                color: runMouse.containsMouse
                    ? Qt.alpha(Colors.cyan, 0.25)
                    : Colors.bg_inset
                border.width: 1
                border.color: Colors.cyan

                Text {
                    id: runText
                    anchors.centerIn: parent
                    text: row.actionKind === "mutating_shell"
                          ? "Run…" : "Run"
                    color: Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: runMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row._onRunClicked()
                }
            }

            // [Copy] button — only visible when allowlist denies.
            Rectangle {
                visible: !row._wouldAllow()
                    && (row.hasAction || row._actionKindIsLink())
                width: copyText.implicitWidth + 16
                height: copyText.implicitHeight + 6
                radius: Geometry.radiusInteractive
                color: copyMouse.containsMouse
                    ? Qt.alpha(Colors.amber, 0.25)
                    : Colors.bg_inset
                border.width: 1
                border.color: Colors.amber

                Text {
                    id: copyText
                    anchors.centerIn: parent
                    // Short label so the button doesn't feel cut off
                    // next to a 4-letter [Run]. The reason for the
                    // downgrade is shown via the row's tooltip / the
                    // run-block's downgradeReason text.
                    text: "Copy"
                    color: Colors.amber
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize
                    font.weight: Font.Medium
                }

                // Inline hint explaining WHY [Run] isn't available.
                // For most root_required cases this saves the user a
                // hover or a trip to the run-block to read the reason.
                Text {
                    visible: row.actionKind === "mutating_shell"
                        && (row.actionArgv.length > 0)
                        && (row.actionArgv[0] === "systemctl"
                            || row.actionArgv[0] === "pacman")
                        && !(row.actionArgv[0] === "systemctl"
                            && row.actionArgv[1] === "--user")
                    anchors.verticalCenter: parent.verticalCenter
                    text: "(requires root — copy and run with sudo in a terminal)"
                    color: Colors.fg_dim
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize - 2
                    font.italic: true
                }

                MouseArea {
                    id: copyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row._onCopyClicked()
                }
            }
        }

        // ── Confirmation pill (mutating_shell only) ───────────────
        // Inline (not modal). Three primary actions: Yes (run), No
        // (cancel), Ask (query the LLM about this command without
        // committing). Pressing Enter on the pill confirms (Yes);
        // Esc cancels (No). [Ask] expands an input field for typing
        // a question; the answer renders inline above the buttons
        // and the user can iterate before committing.
        Rectangle {
            id: pill
            width: parent.width
            implicitHeight: pillCol.implicitHeight + 14
            visible: row.pillVisible
            radius: Geometry.radiusInteractive
            color: Qt.alpha(Colors.amber, 0.10)
            border.width: 1
            border.color: Colors.amber
            focus: row.pillVisible && !row._askInputVisible

            Keys.onEscapePressed: row._cancelPill()
            Keys.onReturnPressed: row._confirmPill()
            Keys.onEnterPressed: row._confirmPill()

            Column {
                id: pillCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 7
                spacing: 6

                Text {
                    width: parent.width
                    text: "Approve and execute?"
                    color: Colors.amber
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    text: "$ " + row._quoteArgv(row.actionArgv)
                    color: Colors.fg
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize
                    font.weight: Geometry.fontWeight
                    wrapMode: Text.WrapAnywhere
                }

                // ── Q&A area ─────────────────────────────────
                // Three sub-states stacked top-to-bottom:
                //   1. _askAnswer non-empty → render the LLM's answer
                //      in a bordered box above the input/buttons.
                //   2. _askInputVisible → input field + Send/Cancel.
                //   3. _askInFlight → "Asking…" placeholder.
                //
                // The buttons row at the bottom always shows; its
                // labels swap between Yes/No/Ask and Send/Cancel
                // depending on whether the input is open.

                Rectangle {
                    visible: row._askAnswer.length > 0
                    width: parent.width
                    implicitHeight: answerText.implicitHeight + 12
                    color: Qt.alpha(Colors.cyan, 0.08)
                    radius: Geometry.radiusInteractive
                    border.width: 1
                    border.color: Qt.alpha(Colors.cyan, 0.40)

                    Text {
                        id: answerText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 6
                        text: row._askAnswer
                        color: Colors.fg
                        font.family: Geometry.fontFamily
                        font.pixelSize: Geometry.fontSize - 1
                        font.weight: Geometry.fontWeight
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                    }
                }

                // Input field — visible only after [Ask] click.
                // Submit on Enter; Esc collapses back to default
                // pill buttons.
                Rectangle {
                    id: askInputBox
                    visible: row._askInputVisible
                    width: parent.width
                    implicitHeight: askInput.implicitHeight + 10
                    color: Colors.bg_inset
                    radius: Geometry.radiusInteractive
                    border.width: 1
                    border.color: Colors.cyan

                    TextInput {
                        id: askInput
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 6
                        text: row._askQuestion
                        color: Colors.fg
                        font.family: Geometry.fontFamily
                        font.pixelSize: Geometry.fontSize
                        font.weight: Geometry.fontWeight
                        focus: row._askInputVisible && !row._askInFlight
                        clip: true
                        selectByMouse: true
                        cursorVisible: focus
                        onTextChanged: row._askQuestion = text
                        Keys.onReturnPressed: row._sendAskQuestion()
                        Keys.onEnterPressed: row._sendAskQuestion()
                        Keys.onEscapePressed: row._closeAskInput()
                    }

                    // Hint text when input is empty.
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 6
                        visible: askInput.text.length === 0
                        text: "Ask Data about this command…"
                        color: Colors.fg_dim
                        font.family: Geometry.fontFamily
                        font.pixelSize: Geometry.fontSize
                        font.italic: true
                    }
                }

                // "Asking…" placeholder while the LLM is thinking.
                Text {
                    visible: row._askInFlight
                    width: parent.width
                    text: "Asking Data…"
                    color: Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize - 1
                    font.weight: Font.Medium
                    font.italic: true

                    SequentialAnimation on opacity {
                        running: row._askInFlight
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.45; duration: 600; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 0.45; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                    }
                }

                // Button row — Yes / No / Ask  OR  Send / Cancel.
                Row {
                    spacing: 8
                    layoutDirection: Qt.RightToLeft
                    anchors.right: parent.right

                    // [Yes] — confirm + run. Hidden in input mode.
                    Rectangle {
                        visible: !row._askInputVisible && !row._askInFlight
                        width: pillYesText.implicitWidth + 16
                        height: pillYesText.implicitHeight + 6
                        radius: Geometry.radiusInteractive
                        color: pillYesMouse.containsMouse
                            ? Qt.alpha(Colors.green, 0.30)
                            : Colors.bg_inset
                        border.width: 1
                        border.color: Colors.green

                        Text {
                            id: pillYesText
                            anchors.centerIn: parent
                            text: "Yes"
                            color: Colors.green
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: pillYesMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row._confirmPill()
                        }
                    }

                    // [No] — cancel. Hidden in input mode.
                    Rectangle {
                        visible: !row._askInputVisible && !row._askInFlight
                        width: pillNoText.implicitWidth + 16
                        height: pillNoText.implicitHeight + 6
                        radius: Geometry.radiusInteractive
                        color: pillNoMouse.containsMouse
                            ? Qt.alpha(Colors.red, 0.25)
                            : Colors.bg_inset
                        border.width: 1
                        border.color: Colors.red

                        Text {
                            id: pillNoText
                            anchors.centerIn: parent
                            text: "No"
                            color: Colors.red
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: pillNoMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row._cancelPill()
                        }
                    }

                    // [Ask] — open question input. Hidden in input mode.
                    Rectangle {
                        visible: !row._askInputVisible && !row._askInFlight
                        width: pillAskText.implicitWidth + 16
                        height: pillAskText.implicitHeight + 6
                        radius: Geometry.radiusInteractive
                        color: pillAskMouse.containsMouse
                            ? Qt.alpha(Colors.cyan, 0.25)
                            : Colors.bg_inset
                        border.width: 1
                        border.color: Colors.cyan

                        Text {
                            id: pillAskText
                            anchors.centerIn: parent
                            text: row._askAnswer.length > 0
                                ? "Ask another"
                                : "Ask a question"
                            color: Colors.cyan
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: pillAskMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row._openAskInput()
                        }
                    }

                    // [Send] — fires LLM call. Visible in input mode.
                    Rectangle {
                        visible: row._askInputVisible && !row._askInFlight
                        width: pillSendText.implicitWidth + 16
                        height: pillSendText.implicitHeight + 6
                        radius: Geometry.radiusInteractive
                        color: pillSendMouse.containsMouse
                            ? Qt.alpha(Colors.cyan, 0.30)
                            : Colors.bg_inset
                        border.width: 1
                        border.color: Colors.cyan

                        Text {
                            id: pillSendText
                            anchors.centerIn: parent
                            text: "Send"
                            color: Colors.cyan
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: pillSendMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row._sendAskQuestion()
                        }
                    }

                    // [Close] — back to Yes/No/Ask without asking.
                    Rectangle {
                        visible: row._askInputVisible && !row._askInFlight
                        width: pillCloseAskText.implicitWidth + 16
                        height: pillCloseAskText.implicitHeight + 6
                        radius: Geometry.radiusInteractive
                        color: pillCloseAskMouse.containsMouse
                            ? Qt.alpha(Colors.fg_dim, 0.25)
                            : Colors.bg_inset
                        border.width: 1
                        border.color: Colors.fg_dim

                        Text {
                            id: pillCloseAskText
                            anchors.centerIn: parent
                            text: "Back"
                            color: Colors.fg_dim
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize
                            font.weight: Geometry.fontWeight
                        }

                        MouseArea {
                            id: pillCloseAskMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row._closeAskInput()
                        }
                    }
                }
            }
        }

        // ── Running / completed sub-block ─────────────────────────
        // Replaces the expanded body once the executor starts. Shows
        // a bounded stdout pane (mono, scrolls within the row) plus
        // the exit code in amber on non-zero exits.
        Rectangle {
            id: runBlock
            width: parent.width
            visible: row.ranAtLeastOnce
                || (row._exec && row._exec.running)
            color: Qt.alpha(Colors.bg_dark, 0.85)
            border.width: 1
            border.color: Qt.alpha(Colors.cyan, 0.30)
            radius: Geometry.radiusInteractive
            implicitHeight: Math.min(220, runBlockCol.implicitHeight + 12)
            clip: true

            Column {
                id: runBlockCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                spacing: 4

                Text {
                    width: parent.width
                    text: "$ " + row._quoteArgv(row.actionArgv)
                    color: Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize - 1
                    font.weight: Font.Medium
                    wrapMode: Text.WrapAnywhere
                }

                Flickable {
                    width: parent.width
                    implicitHeight: Math.min(140, stdoutText.implicitHeight)
                    contentHeight: stdoutText.implicitHeight
                    flickableDirection: Flickable.VerticalFlick
                    clip: true

                    Text {
                        id: stdoutText
                        width: parent.width
                        text: row._exec
                            ? (row._exec.stdoutBuffer || "(no output)")
                            : "(no output)"
                        color: Colors.fg
                        font.family: Geometry.fontFamily
                        font.pixelSize: Geometry.fontSize - 2
                        font.weight: Geometry.fontWeight
                        wrapMode: Text.WrapAnywhere
                    }
                }

                Text {
                    visible: row._exec && !row._exec.running
                        && row._exec.exitCode !== 0
                        && row._exec.exitCode !== -1
                    width: parent.width
                    text: row._exec
                        ? ("exit " + row._exec.exitCode
                           + (row._exec.stderrBuffer.length > 0
                              ? "\n" + row._exec.stderrBuffer : ""))
                        : ""
                    color: Colors.amber
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize - 2
                    font.weight: Geometry.fontWeight
                    wrapMode: Text.WrapAnywhere
                }

                // Blocked / downgrade reason — surfaced from the
                // executor when validation refused argv. The row already
                // shows [Copy] in this state, but the reason itself is
                // useful diagnostic.
                Text {
                    visible: row._exec
                        && row._exec.downgradeReason.length > 0
                    width: parent.width
                    text: row._exec ? row._exec.downgradeReason : ""
                    color: Colors.fg_dim
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize - 2
                    font.weight: Geometry.fontWeight
                    wrapMode: Text.WordWrap
                }

                // Auto-eval status: once the action completes, the
                // Timer above schedules evaluateActionResult() in 2s.
                // Show a pulsing hint here so the user knows the next
                // step is on the way without having to click anything.
                Text {
                    visible: row._evalScheduled
                    width: parent.width
                    text: "Evaluating…"
                    color: Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize - 1
                    font.weight: Font.Medium
                    font.italic: true

                    SequentialAnimation on opacity {
                        running: row._evalScheduled
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.45; duration: 600; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 0.45; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                    }
                }

                // Manual eval button — visible after action completes,
                // hidden while the auto-eval Timer is pending (the
                // Evaluating… hint stands in for it). Lets the user
                // re-trigger eval if the auto-fired one's result was
                // unsatisfying. Hidden on blocked rows (nothing to
                // evaluate).
                Row {
                    spacing: 8
                    visible: row._exec && !row._exec.running
                        && row.ranAtLeastOnce
                        && !row._evalScheduled
                        && row._exec.downgradeReason.length === 0

                    Rectangle {
                        width: evalText.implicitWidth + 16
                        height: evalText.implicitHeight + 6
                        radius: Geometry.radiusInteractive
                        color: evalMouse.containsMouse
                            ? Qt.alpha(Colors.cyan, 0.25)
                            : Colors.bg_inset
                        border.width: 1
                        border.color: Colors.cyan

                        Text {
                            id: evalText
                            anchors.centerIn: parent
                            text: "Evaluate again"
                            color: Colors.cyan
                            font.family: Geometry.fontFamily
                            font.pixelSize: Geometry.fontSize - 1
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: evalMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row._onEvaluateClicked()
                        }
                    }
                }
            }
        }
    }

    // ── Click semantics ──────────────────────────────────────────
    // Click anywhere on the row (outside [Run] / [Copy] / pill) toggles
    // expand. Once running, clicks no longer toggle (the run-block UI
    // is the row's primary content).
    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: row._anyAction()
            ? Qt.PointingHandCursor : Qt.ArrowCursor
        propagateComposedEvents: true
        z: -1
        onClicked: function(mouse) {
            if (row.pillVisible) return
            if (row._exec && row._exec.running) return
            row.expanded = !row.expanded
        }
    }

    // ── Helpers ──────────────────────────────────────────────────
    function _iconForState() {
        if (!row.hasAction) return "▾"
        if (!_wouldAllow()) return "📋"
        switch (row.actionKind) {
            case "read_only_shell":
            case "mutating_shell":
                return "▶"
            case "file_open":
                return "📂"
            case "doc_link":
                return "🔗"
        }
        return "▾"
    }

    function _iconColor() {
        if (!row.hasAction) return Colors.fg_dim
        if (!_wouldAllow()) return Colors.amber
        return Colors.cyan
    }

    function _iconTip() {
        if (!row.hasAction) return "no action proposed for this entry"
        if (!_wouldAllow()) return "blocked by allowlist — copy to run manually"
        if (row.actionKind === "mutating_shell")
            return "click to run with confirmation"
        return "click to run"
    }

    // _actionKindIsLink — file_open + doc_link are "link" kinds: they
    // skip the allowlist (xdg-open dispatches) and so always render the
    // [Run] (open) button. Used to gate button visibility separately
    // from hasAction (which counts shell kinds).
    function _actionKindIsLink() {
        return row.actionKind === "file_open"
            || row.actionKind === "doc_link"
    }

    function _anyAction() {
        return row.hasAction || _actionKindIsLink()
    }

    // _wouldAllow — predict whether the executor's _validate() would
    // permit this argv. Mirrors ActionExecutor._validate exactly so the
    // row's icon + button state matches what would happen on click.
    // Pure function over (entry, allowlist) — no side effects.
    function _wouldAllow() {
        if (!row._anyAction()) return false
        if (_actionKindIsLink()) return row.actionArgv.length > 0
        if (!row.allowlist) return false
        var argv = row.actionArgv
        if (!argv || argv.length === 0) return false

        if (row.actionKind === "read_only_shell") {
            return _inList(row.allowlist.read_only_binaries, argv[0])
        }

        if (row.actionKind === "mutating_shell") {
            if (!_inList(row.allowlist.mutating_binaries, argv[0])) return false
            // systemctl --user scope check (root-required exemption).
            if (argv[0] === "systemctl" && argv[1] === "--user") {
                if (argv.length < 3) return false
                return _inList(row.allowlist.systemctl_user_subcommand_allowlist,
                               argv[2])
            }
            // Polkit-elevatable + policy-files-present → [Run]
            // permitted. Subcommand check still applies inside this
            // branch so the icon honours the same gate ActionExecutor
            // does (Cf. FEAT-nostromo-console-polkit chunk 3).
            if (_inList(row.allowlist.polkit_elevatable_binaries || [], argv[0])
                && row.polkitAvailable) {
                var subListPk = (row.allowlist.mutating_subcommand_allowlist
                    || ({}))[argv[0]]
                if (subListPk) {
                    if (argv.length < 2) return false
                    if (!_inList(subListPk, argv[1])) return false
                }
                return true
            }
            // Legacy root-required guard — only fires when the polkit
            // path above did NOT take (no allowlist field, or polkit
            // unavailable). Matches ActionExecutor's branch ordering.
            if (_inList(row.allowlist.root_required_binaries, argv[0])) return false
            // subcommand check.
            var subList = (row.allowlist.mutating_subcommand_allowlist
                || ({}))[argv[0]]
            if (subList) {
                if (argv.length < 2) return false
                if (!_inList(subList, argv[1])) return false
            }
            // tailscale set flag check.
            if (argv[0] === "tailscale" && argv[1] === "set") {
                if (argv.length < 3) return false
                if (!_inList(row.allowlist.tailscale_set_flag_allowlist, argv[2]))
                    return false
            }
            return true
        }
        return false
    }

    function _inList(list, value) {
        if (!list || !Array.isArray(list)) return false
        for (var i = 0; i < list.length; i++) {
            if (list[i] === value) return true
        }
        return false
    }

    // _quoteArgv — shell-renderer for argv display + copy. Args without
    // spaces or shell metas pass through; args with spaces wrap in
    // single quotes; embedded single quotes get backslash-escaped.
    function _quoteArgv(argv) {
        if (!argv || argv.length === 0) return ""
        return argv.map(function(a) {
            var s = String(a)
            if (s.length === 0) return "''"
            if (/^[A-Za-z0-9_./:=@%+,-]+$/.test(s)) return s
            return "'" + s.replace(/'/g, "'\\''") + "'"
        }).join(" ")
    }

    // _contextSlice — takes the rawContext array and picks up to maxN
    // records that look most relevant to this entry. Heuristic: prefer
    // records whose unit/syslog identifier matches entry.cat. Falls back
    // to the most recent maxN records if nothing matches.
    function _contextSlice(raw, maxN) {
        if (!raw || raw.length === 0) return []
        var cat = entry && entry.cat ? String(entry.cat) : ""
        var matches = []
        if (cat.length > 0) {
            for (var i = raw.length - 1; i >= 0 && matches.length < maxN; i--) {
                var r = raw[i]
                var ident = r && (r.SYSLOG_IDENTIFIER || r._SYSTEMD_UNIT || "")
                if (String(ident).indexOf(cat) >= 0) matches.unshift(r)
            }
            if (matches.length > 0) return matches
        }
        // Fallback: tail
        return raw.slice(Math.max(0, raw.length - maxN))
    }

    // _renderRaw — compact one-line view of a raw record for the
    // expanded body. Mirrors NostromoWhispers' formatter shape but
    // keeps the rendering local (the console row does not depend on
    // the variant module).
    function _renderRaw(r) {
        if (!r) return ""
        var ts = r.__REALTIME_TIMESTAMP || ""
        var unit = r.SYSLOG_IDENTIFIER || r._SYSTEMD_UNIT || ""
        var msg = r.MESSAGE || ""
        if (unit.length > 0) return unit + ": " + msg
        return msg
    }

    // ── Click handlers ───────────────────────────────────────────
    function _onRunClicked() {
        console.log("[ROW] run clicked actionKind=" + row.actionKind
            + " wouldAllow=" + _wouldAllow()
            + " argv=" + JSON.stringify(row.actionArgv))
        if (!_wouldAllow()) {
            _onCopyClicked()
            return
        }
        if (row.actionKind === "mutating_shell") {
            row.pillVisible = true
            return
        }
        _exec.run()
    }

    function _confirmPill() {
        console.log("[ROW] pill confirmed argv=" + JSON.stringify(row.actionArgv))
        row.pillVisible = false
        _exec.run()
    }

    function _cancelPill() {
        row.pillVisible = false
        // Reset the [Ask] sub-state so the next time the pill opens
        // the user starts from a clean three-button row.
        row._askInputVisible = false
        row._askQuestion = ""
        row._askAnswer = ""
    }

    // ── Pill [Ask] flow ──────────────────────────────────────────
    function _openAskInput() {
        row._askInputVisible = true
    }

    function _closeAskInput() {
        // Collapse input back to default Yes/No/Ask buttons. Keeps
        // _askAnswer (so the user can re-read while deciding) but
        // clears the question draft so the next [Ask] click opens
        // a clean field.
        row._askInputVisible = false
        row._askQuestion = ""
    }

    function _sendAskQuestion() {
        var q = (row._askQuestion || "").trim()
        if (q.length === 0) return
        if (row._askInFlight) return
        console.log("[ROW] ask sent: " + q.substring(0, 80))
        // Clear the previous answer so the user sees only the new
        // one (and the in-flight pulse) instead of stale text.
        row._askAnswer = ""
        row._askInputVisible = false
        row._askInFlight = true
        Services.JournalInterpreter.askActionQuestion(
            row.entry, row.actionArgv, q)
        row._askQuestion = ""
    }

    function _onCopyClicked() {
        var cmd = _quoteArgv(row.actionArgv)
        if (cmd.length === 0) return
        // Spawn wl-copy with stdin = cmd. Quickshell's Process supports
        // stdin via the `stdinEnabled` + write flow; spec capability gate
        // calls for wl-copy as the universal fallback because
        // Quickshell.Clipboard.text write API isn't exposed in 0.2.1.
        copyProc.command = ["wl-copy", "--", cmd]
        copyProc.running = true
    }

    // Follow-up evaluation — feed exit/stdout/stderr back into the LLM
    // and ask "did it resolve the issue, new issue, next step?". The
    // singleton method routes through the same investigateProgress /
    // investigateReady signals, so the Console swaps to a fresh
    // streaming view automatically and the user sees the eval typed
    // out the same way the original investigate was.
    function _onEvaluateClicked() {
        console.log("[ROW] evaluate clicked exitCode="
            + (row._exec ? row._exec.exitCode : "n/a")
            + " argv=" + JSON.stringify(row.actionArgv))
        if (!row._exec) return
        Services.JournalInterpreter.evaluateActionResult(
            row.entry,
            row.actionArgv,
            row._exec.exitCode,
            row._exec.stdoutBuffer,
            row._exec.stderrBuffer)
    }

    Process {
        id: copyProc
        running: false
    }
}
