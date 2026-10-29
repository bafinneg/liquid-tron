import Quickshell
import Quickshell.Io
import QtQuick
import "components"
import "console" as Console
import "services" as Services

ShellRoot {
    id: shellRoot

    signal actionFeedbackVolume(int percent)
    signal actionFeedbackMute()
    signal actionFeedbackMode(string mode)

    function boundedAudioPercent(value) {
        if (typeof value !== "string") return -1
        if (!/^(0|[1-9][0-9]?|100)$/.test(value)) return -1
        return Number(value)
    }

    function validSystemMode(value) {
        return value === "gaming" || value === "intelligent"
    }

    IpcHandler {
        target: "action_feedback"

        function volume(value: string): string {
            var percent = shellRoot.boundedAudioPercent(value)
            if (percent < 0) return JSON.stringify({ ok: false })
            shellRoot.actionFeedbackVolume(percent)
            return JSON.stringify({ ok: true })
        }

        function mute(): string {
            shellRoot.actionFeedbackMute()
            return JSON.stringify({ ok: true })
        }

        function mode(value: string): string {
            if (arguments.length !== 1 || !shellRoot.validSystemMode(value)) {
                return JSON.stringify({ ok: false })
            }
            shellRoot.actionFeedbackMode(value)
            return JSON.stringify({ ok: true })
        }
    }

    // Bar renders on center monitor only — FEAT-workspace-bar-atlas-polish C1.
    // Restores DP-3-only filter from FEAT-workspace-ux-overhaul §Phase 0, which
    // was inadvertently widened to Quickshell.screens by atlas Phase 0.
    Variants {
        model: Quickshell.screens.filter(function(s) { return s.name === "DP-3"; })
        Bar {}
    }

    // Side monitor workspace selector — hidden 2px top-edge target on DP-2/DP-4.
    // Keeps the persistent Atlas bar scoped to DP-3 while allowing mouse-driven
    // summons on the side monitors.
    Variants {
        model: Quickshell.screens.filter(function(s) { return s.name === "DP-2" || s.name === "DP-4"; })
        SideWorkspaceSelector {}
    }

    // Side monitor workspace HUD — transient switch feedback on DP-2/DP-4.
    Variants {
        model: Quickshell.screens.filter(function(s) { return s.name === "DP-2" || s.name === "DP-4"; })
        WorkspaceHud {}
    }

    // Ambient layer — WlrLayer.Background substrate per monitor.
    // Visibility is gated per-monitor by Ambient.monitorScope (palette).
    // Renders nothing until a variant is wired (FEAT-ambient-layer).
    Variants {
        model: Quickshell.screens
        AmbientLayer {}
    }

    // DP-3 center ambient substrate — Prismatic Veil depth layer.
    // Hardcoded to DP-3 (ASUS PG42UQ OLED); not routed through Ambient.monitorScope.
    Variants {
        model: Quickshell.screens.filter(function(s) { return s.name === "DP-3"; })
        CenterAmbientLayer {}
    }

    // Unlock splash — snappy 2s variant, triggered by lock wrapper
    Variants {
        model: Quickshell.screens
        UnlockOverlay {}
    }

    // Cursor pulse — 300ms expanding cyan ring at cursor on workspace swap.
    // WlrLayer.Overlay, visible=false between pulses. FEAT-workspace-bar-atlas Phase 4.
    Variants {
        model: Quickshell.screens
        CursorPulse {}
    }

    // Focus envelope — bounded, content-free active-window acquisition feedback.
    Variants {
        model: Quickshell.screens
        FocusEnvelope {}
    }

    // Action feedback — one overlay instance per monitor, one bounded IPC target.
    Variants {
        model: Quickshell.screens
        ActionFeedback { eventSource: shellRoot }
    }

    // Notification toast stack — single instance outside Variants.
    // Screen is bridged from the DP-3 Bar via NotificationService singleton.
    NotificationToastStack {
        screen: Services.NotificationService.centerScreen
    }

    // Workspace overview — single instance, screen snapshotted at toggle time.
    // WlrLayer.Overlay, visible=false until summoned. FEAT-workspace-overview.
    Overview {}

    // Keybind cheatsheet — single instance, visible=false until summoned.
    // FEAT-liquid-tron-desktop-polish-2 C3.
    Cheatsheet {}

    // Nostromo Console — single instance attached to the DP-3 bar.
    // The PopupWindow's `anchor.window` reads from
    // NotificationService.centerBar; renders nothing until the DP-3 bar
    // finishes Component.onCompleted and writes the handle (same null-
    // until-bridged convention as NotificationToastStack with
    // centerScreen). FEAT-nostromo-console chunk 4 / open-question 1.
    Console.Console {
        bar: Services.NotificationService.centerBar
    }

    // Boot splash — fullscreen overlay on every monitor, fades after ~4s.
    // Declared last so its overlay surfaces cover the rest of MOCR-Q during startup.
    Variants {
        model: Quickshell.screens
        SplashOverlay {}
    }
}
