pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
// Sibling singleton — NotificationInterpreter rewrites every accepted
// notification asynchronously. `.` refers to this file's directory
// (services/); qmldir registers both singletons in the `services`
// module. Same import idiom JournalInterpreter uses for PresenceState.
import "." as Siblings

// Notification service singleton — owns the D-Bus notification server,
// filters suppressed notifications, manages toast queue and history.
// Registered as singleton in services/qmldir. Access as NotificationService.
//
// activeToasts and historyList store plain JS objects (not C++ QObject refs)
// because QML property bindings cannot read C++ QObject properties from
// JS array elements. Notification refs are kept in a parallel _notifRefs
// map keyed by toast index for dismiss/pause operations.

Item {
    id: svc
    visible: false
    width: 0; height: 0

    // ── Public API ────────────────────────────────────────────

    // Active toast queue (max 5). Each: { summary, body, appName, urgency, notifId, image, appType, receivedAt }
    property var activeToasts: []

    // History — JS array of plain objects, newest first.
    // Each: { summary, body, appName, urgency, notifId, image, appType, receivedAt }
    // `notifId` (FEAT-notification-interpreter) lets the async rewrite
    // callback locate and mutate the matching history entry in place.
    property var historyList: []

    // Unread count.
    property int unreadCount: 0

    // Last time the history popover was viewed; used for unread tinting.
    property real lastViewedAt: 0

    // Critical toasts are persistent enough to notice but still bounded.
    readonly property int criticalTimeoutMs: 60000

    // True when any active toast has Critical urgency.
    property bool hasActiveCritical: false

    // DP-3 bridge — written by Bar.qml on DP-3 instance via Component.onCompleted.
    property var centerScreen: null
    property bool popoverShelfOpen: false
    property int popoverShelfHeight: 0

    // Center-monitor bar handle (FEAT-nostromo-console). Written by
    // Bar.qml on DP-3. The Nostromo Console is a PopupWindow that
    // needs `anchor.window` to be the bar's PanelWindow; shell.qml
    // instantiates a single Console and reads the handle from here.
    // Null until the DP-3 bar finishes Component.onCompleted — the
    // Console renders nothing while null, same convention as
    // NotificationToastStack with centerScreen.
    property var centerBar: null

    // Cross-bar popover coordination (INFRA-002 style).
    // When a shelf opens on one screen, others must close.
    // Each PopoverShelf writes its screen name here; others react by clearing.
    property string activePopoverScreen: ""

    // ── Notification ref lookup (by notifId) ──────────────────

    property var _notifRefs: ({})

    function _notifRefFor(notifId) {
        return _notifRefs[notifId] || null
    }

    // ── Actions ───────────────────────────────────────────────

    // IDs currently being closed — prevents re-entrancy when dismiss()
    // fires the closed signal back into _onToastClosed.
    property var _closing: ({})

    function dismissToastAt(index) {
        if (index < 0 || index >= activeToasts.length) return
        var toast = activeToasts[index]
        dismissToastByNotifId(toast.notifId)
    }

    function dismissToastByNotifId(notifId) {
        var ref = _notifRefFor(notifId)
        if (ref) {
            _removeTimer(notifId)
            ref.dismiss()
        }
    }

    function pauseToastAt(index) {
        if (index < 0 || index >= activeToasts.length) return
        var id = activeToasts[index].notifId
        if (_timers[id]) _timers[id].stop()
    }

    function resumeToastAt(index) {
        if (index < 0 || index >= activeToasts.length) return
        var id = activeToasts[index].notifId
        if (_timers[id]) _timers[id].restart()
    }

    function dismissHistoryAt(index) {
        if (index < 0 || index >= historyList.length) return
        var list = historyList.slice()
        list.splice(index, 1)
        historyList = list
    }

    function clearHistory() {
        historyList = []
        unreadCount = 0
    }

    function clearActiveToasts() {
        var toasts = activeToasts.slice()
        for (var i = 0; i < toasts.length; i++) {
            var id = toasts[i].notifId
            _removeTimer(id)
            _closing[id] = true
            var ref = _notifRefs[id]
            if (ref) ref.dismiss()
            delete _notifRefs[id]
        }
        activeToasts = []
        hasActiveCritical = false
        _closing = ({})
    }

    function clearAll() {
        clearHistory()
        clearActiveToasts()
    }

    function markRead() {
        unreadCount = 0
        lastViewedAt = Date.now()
    }

    // ── App detection ─────────────────────────────────────────
    // Returns "alfred", "claude", or "" (default).
    // Claude Code sends OSC 99 via Kitty: appName="kitty", summary="Claude Code".
    // Alfred is Claude Code running in home-infra context.
    function detectAppType(summary, body) {
        var s = (summary || "").toLowerCase()
        var b = (body || "").toLowerCase()
        if (s.indexOf("claude") < 0) return ""
        if (b.indexOf("alfred") >= 0 || b.indexOf("home-infra") >= 0)
            return "alfred"
        return "claude"
    }

    // ── HTML stripping ────────────────────────────────────────

    function stripHtml(text) {
        if (!text) return ""
        return text.replace(/<[^>]*>/g, "")
    }

    // ── Suppression patterns ──────────────────────────────────

    readonly property var _suppressPatterns: [
        /aquamarine/i,
        /CRTC/i,
        /wl_display_connect/,
        /page-flip/
    ]

    function _isSuppressed(notification) {
        var body = notification.body || ""
        var summary = notification.summary || ""
        var text = summary + " " + body
        for (var i = 0; i < _suppressPatterns.length; i++) {
            if (_suppressPatterns[i].test(text)) return true
        }
        return false
    }

    // ── Timer tracking ────────────────────────────────────────

    property var _timers: ({})

    function _removeTimer(notifId) {
        if (_timers[notifId]) {
            _timers[notifId].stop()
            _timers[notifId].destroy()
            delete _timers[notifId]
        }
    }

    // ── Notification server ───────────────────────────────────

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: false
        imageSupported: true
        persistenceSupported: false

        onNotification: function(notification) {
            if (svc._isSuppressed(notification)) {
                notification.dismiss()
                return
            }

            // Snapshot all data from the C++ object into plain JS
            var summary = notification.summary || ""
            var body = svc.stripHtml(notification.body || "")
            var appName = notification.appName || ""
            var urgency = notification.urgency
            var notifId = notification.id
            var receivedAt = Date.now()
            var image = notification.image || ""
            if (!image && notification.appIcon) {
                image = Quickshell.iconPath(notification.appIcon) || ""
            }
            var appType = svc.detectAppType(summary, body)

            // Rewrite Alfred notifications: "Claude Code" / "Alfred did X" → "Alfred" / "did X"
            if (appType === "alfred") {
                summary = "Alfred"
                body = body.replace(/^alfred\s*/i, "")
            }

            // Store the C++ ref for later dismiss/pause
            svc._notifRefs[notifId] = notification

            // Add to history (newest first, max 50)
            var hist = svc.historyList.slice()
            hist.unshift({ summary: summary, body: body, appName: appName, urgency: urgency, notifId: notifId, image: image, appType: appType, receivedAt: receivedAt })
            if (hist.length > 50) hist = hist.slice(0, 50)
            svc.historyList = hist
            svc.unreadCount++

            // Add to active toast queue
            svc._addToast(summary, body, appName, urgency, notifId, image, appType, receivedAt, notification)

            // Async DATA-TNG rewrite (FEAT-notification-interpreter). The
            // toast and history entries above are already admitted with
            // original text; the interpreter callback mutates the
            // matching entries in place ~1-3s later on a healthy ollama
            // daemon. On rawMode / failure / overflow the callback fires
            // immediately with nulls and we keep the original text.
            Siblings.NotificationInterpreter.interpret(
                notifId, summary, body, urgency, appName,
                svc._onRewriteReady)
        }
    }

    // Async-rewrite callback (FEAT-notification-interpreter). Locates
    // the matching toast and history entries by notifId and updates
    // their summary/body in place. Re-assigns each list to a sliced
    // copy so QML bindings fire and the delegates re-render.
    function _onRewriteReady(notifId, newSummary, newBody) {
        if (newSummary === null || newSummary === undefined) return

        // Toast may have been auto-expired or manually dismissed before
        // the rewrite arrives — silent no-op when the lookup misses.
        var toasts = activeToasts.slice()
        var toastChanged = false
        for (var i = 0; i < toasts.length; i++) {
            if (toasts[i].notifId === notifId) {
                var t = {}
                for (var k in toasts[i]) t[k] = toasts[i][k]
                t.summary = newSummary
                t.body = newBody || ""
                toasts[i] = t
                toastChanged = true
                break
            }
        }
        if (toastChanged) activeToasts = toasts

        // History may still hold an entry for the same notification even
        // after the toast is gone (50-entry window). Update it so the
        // history list stays consistent with what the user saw rewritten.
        var hist = historyList.slice()
        var histChanged = false
        for (var j = 0; j < hist.length; j++) {
            if (hist[j].notifId === notifId) {
                var h = {}
                for (var hk in hist[j]) h[hk] = hist[j][hk]
                h.summary = newSummary
                h.body = newBody || ""
                hist[j] = h
                histChanged = true
                break
            }
        }
        if (histChanged) historyList = hist
    }

    function _addToast(summary, body, appName, urgency, notifId, image, appType, receivedAt, notification) {
        var toasts = activeToasts.slice()

        // Overflow: if 5 toasts visible, displace oldest non-critical
        if (toasts.length >= 5) {
            var displaced = false
            for (var i = 0; i < toasts.length; i++) {
                if (toasts[i].urgency !== NotificationUrgency.Critical) {
                    var oldRef = _notifRefFor(toasts[i].notifId)
                    _removeTimer(toasts[i].notifId)
                    if (oldRef) oldRef.dismiss()
                    toasts.splice(i, 1)
                    displaced = true
                    break
                }
            }
            if (!displaced) return
        }

        var entry = {
            summary: summary,
            body: body,
            appName: appName,
            urgency: urgency,
            notifId: notifId,
            image: image,
            appType: appType,
            receivedAt: receivedAt
        }
        toasts.push(entry)
        activeToasts = toasts
        _updateHasActiveCritical()

        // Auto-expire all toasts. Critical urgency uses a longer hard cap.
        var timeoutMs = (urgency === NotificationUrgency.Critical)
                        ? svc.criticalTimeoutMs : 10000
        var timer = _timerComponent.createObject(svc, {
            "_notifId": notifId,
            "interval": timeoutMs
        })
        _timers[notifId] = timer
        timer.start()

        // Listen for external dismissal/expiry
        notification.closed.connect(function() {
            svc._onToastClosed(notifId)
        })
    }

    function _onToastClosed(notifId) {
        if (_closing[notifId]) return
        _closing[notifId] = true
        _removeTimer(notifId)
        var ref = _notifRefs[notifId]
        if (ref) ref.dismiss()
        delete _notifRefs[notifId]
        var toasts = activeToasts.slice()
        for (var i = 0; i < toasts.length; i++) {
            if (toasts[i].notifId === notifId) {
                toasts.splice(i, 1)
                break
            }
        }
        activeToasts = toasts
        delete _closing[notifId]
        _updateHasActiveCritical()
    }

    function _updateHasActiveCritical() {
        for (var i = 0; i < activeToasts.length; i++) {
            if (activeToasts[i].urgency === NotificationUrgency.Critical) {
                hasActiveCritical = true
                return
            }
        }
        hasActiveCritical = false
    }

    // ── Auto-expire timer component ───────────────────────────

    Component {
        id: _timerComponent

        Timer {
            property int _notifId: 0
            repeat: false
            onTriggered: {
                svc._onToastClosed(_notifId)
                destroy()
            }
        }
    }
}
