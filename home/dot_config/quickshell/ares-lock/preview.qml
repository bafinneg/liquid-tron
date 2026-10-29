// Ares lock PREVIEW (FEAT-ares-sentinel-lock): an ordinary window, no session lock, fake authenticator.
// Run:  qs -p ~/.config/quickshell/ares-lock/preview.qml     password: ares
// IPC (preview only): qs -p <this file> ipc call arespreview <fn> ...
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Component.onCompleted: { LockContext.preview = true; LockContext.previewPassword = "ares"; }

    FloatingWindow {
        id: win
        title: "ares-lock-preview"
        implicitWidth: 1600
        implicitHeight: 900
        color: "black"

        Row {
            anchors.fill: parent
            LockSurface {
                id: main
                width: 1200; height: 900
                primary: true
                screenX: 0; screenY: 0
            }
            Rectangle { width: 2; height: 900; color: "#0a5a60" }
            LockSurface {
                width: 398; height: 900
                primary: false
                screenX: 1202; screenY: 0
            }
        }
    }

    IpcHandler {
        target: "arespreview"
        function move(x: int, y: int): void { LockContext.pointerMoved(x, y); }
        function type(s: string): void {
            for (let i = 0; i < s.length; i++) LockContext.feedChar(s[i]);
        }
        function enter(): void { LockContext.submit(); }
        function idle(): void { LockContext.lastInput = Date.now() - 61000; LockContext.lastPointer = 0; }
        function status(): string { return LockContext.state + " failures=" + LockContext.failures + " red=" + LockContext.redAlert + " voice=" + LockContext.voiceSource + " cam=" + LockContext.camState + (LockContext.camSimulated ? "(sim)" : "") + " n=" + LockContext.camN + " msg=" + LockContext.message; }
        // Simulated camera (takes over from the real helper until camreal() is called).
        // face(yaw*100, near*100, people): yaw -100 viewer-left .. +100 viewer-right
        function face(yaw: int, near: int, people: int): void {
            LockContext.camSimulated = true;
            const others = [];
            for (let i = 1; i < people; i++) others.push(i % 2 ? 0.7 : -0.6);
            LockContext.presenceLine(JSON.stringify({ v: 1, st: "ok", n: people, yaw: yaw / 100, pitch: 0, near: near / 100,
                conf: 0.9, others: others, motion: 0.02, myaw: null }), true);
        }
        function noface(): void {
            LockContext.camSimulated = true;
            LockContext.presenceLine('{"v":1,"st":"ok","n":0,"motion":0,"myaw":null}', true);
        }
        function camreal(): void { LockContext.camSimulated = false; }
    }
}
