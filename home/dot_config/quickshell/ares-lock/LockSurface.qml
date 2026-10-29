// One Ares lock surface per monitor (FEAT-ares-sentinel-lock).
// Primary (centre PG42UQ): the large optic, telemetry voice, credential line and HUD.
// Peripheral (side AW2725Qs): a smaller sentinel optic. Every surface draws the subject reticle when the
// pointer is on it, so the cursor is never unobserved.
import QtQuick

Item {
    id: surf

    readonly property var ctx: LockContext
    property real screenX: 0
    property real screenY: 0
    property bool primary: true

    readonly property color cyan: "#0abdc6"
    readonly property color dimCyan: "#0a5a60"
    readonly property color red: "#ff003c"
    readonly property color amber: "#ff8c00"
    readonly property color blue: "#0072ff"
    // Layout unit: 1.0 on a 3840x2160 surface (was *2, which doubled everything on the real 4K lock).
    readonly property real u: Math.min(width / 3840, height / 2160)
    // Red holds through the 2-minute alert after a denial; amber still shows while PAM checks.
    readonly property bool alertRed: ctx.state === "denied" || (ctx.redAlert && ctx.state !== "checking" && ctx.state !== "granted")
    readonly property color stateColor: ctx.state === "checking" ? amber
        : alertRed ? red
        : ctx.caps ? blue : cyan

    // Burn-in drift: the whole composition moves along a slow Lissajous path (±48 px at 4K).
    property real driftT: 0
    Timer { interval: 2000; running: true; repeat: true; onTriggered: surf.driftT += 2 }
    readonly property real driftX: Math.sin(driftT / 173) * 48 * u
    readonly property real driftY: Math.sin(driftT / 241 + 1.3) * 30 * u

    // Local pointer
    property real px: -1
    property real py: -1
    property bool pointerHere: false

    Rectangle { anchors.fill: parent; color: "black" }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BlankCursor
        onPositionChanged: mouse => {
            surf.px = mouse.x; surf.py = mouse.y; surf.pointerHere = true;
            surf.ctx.pointerMoved(surf.screenX + mouse.x, surf.screenY + mouse.y);
        }
        onEntered: surf.pointerHere = true
        onExited: surf.pointerHere = false
        onPressed: keyCatcher.forceActiveFocus()
    }

    Item {
        id: keyCatcher
        focus: true
        Keys.onPressed: event => surf.ctx.handleKey(event)
    }

    // Grant: the console powers down like a CRT (vertical collapse, then horizontal).
    property real collapseY: 1.0
    property real collapseX: 1.0
    Connections {
        target: surf.ctx
        function onGranted() { grantAnim.restart(); }
        function onDenied(count) { shake.restart(); flash.restart(); }
        function onStateChanged() {
            if (surf.ctx.state === "watch" && surf.collapseY < 1) { surf.collapseY = 1; surf.collapseX = 1; }
        }
    }
    SequentialAnimation {
        id: grantAnim
        PauseAnimation { duration: 520 }
        NumberAnimation { target: surf; property: "collapseY"; to: 0.004; duration: 220; easing.type: Easing.InCubic }
        NumberAnimation { target: surf; property: "collapseX"; to: 0.0; duration: 160; easing.type: Easing.InCubic }
    }

    Item {
        id: stage
        anchors.fill: parent
        transform: Scale {
            origin.x: stage.width / 2; origin.y: stage.height / 2
            xScale: surf.collapseX; yScale: surf.collapseY
        }

        // Deny flash: a red edge vignette.
        Rectangle {
            id: vignette
            anchors.fill: parent
            color: "transparent"
            border.color: surf.red
            border.width: 18 * surf.u
            opacity: 0
            NumberAnimation on opacity { id: flash; running: false; from: 0.85; to: 0; duration: 900; easing.type: Easing.OutCubic }
        }
        Rectangle {   // persistent thin red frame after three failures
            anchors.fill: parent
            color: "transparent"
            border.color: surf.red
            border.width: 2 * surf.u
            opacity: surf.ctx.failures >= 3 || surf.ctx.redAlert ? 0.55 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }

        Item {
            id: comp
            x: surf.driftX; y: surf.driftY
            width: parent.width; height: parent.height

            // The Ares helm: the one figure. Side monitors carry no figure of their own; the helm turns to
            // face the subject wherever the pointer is, and the side screens only mark the subject.
            Helm {
                id: optic
                visible: surf.primary
                width: 1200 * surf.u
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.42 - height / 2
                centerGX: surf.screenX + comp.x + x + width / 2
                centerGY: surf.screenY + comp.y + y + height / 2
                reachX: 5200 * surf.u      // unchanged on the real 4K lock after the u fix (was 2600 * 2u)
                reachY: 2800 * surf.u
            }

            // ---------- Primary only: voice + credential line ----------
            Column {
                visible: surf.primary
                anchors.horizontalCenter: parent.horizontalCenter
                y: optic.y + optic.height + 10 * surf.u
                spacing: 34 * surf.u

                TypeLine {
                    anchors.horizontalCenter: parent.horizontalCenter
                    target: surf.ctx.message
                    serial: surf.ctx.messageSerial
                    scramble: surf.ctx.state === "denied"
                    color: surf.alertRed ? surf.red : surf.ctx.state === "granted" ? "#bfffff" : surf.cyan
                    font.pixelSize: 42 * surf.u
                    font.letterSpacing: 7 * surf.u
                }

                // Credential line: anonymous pulses. Each keystroke excites random cells; length is never shown.
                Item {
                    id: cred
                    width: 760 * surf.u; height: 46 * surf.u
                    anchors.horizontalCenter: parent.horizontalCenter
                    property real shakeP: 0      // 1 -> 0 over the shake
                    readonly property real shakeX: Math.sin(shakeP * 46) * shakeP * 30 * surf.u
                    transform: Translate { x: cred.shakeX }
                    property var heat: []
                    property int cells: 38
                    Component.onCompleted: { const h = []; for (let i = 0; i < cells; i++) h.push(0); heat = h; }

                    Connections {
                        target: surf.ctx
                        function onKeystroke(erase) {
                            const h = cred.heat.slice();
                            const hits = erase ? 6 : 3;
                            for (let i = 0; i < hits; i++) {
                                const c = Math.floor(Math.random() * cred.cells);
                                h[c] = erase ? -1 : 1;
                            }
                            cred.heat = h;
                        }
                    }
                    Timer {
                        interval: 33; running: cred.visible; repeat: true
                        onTriggered: {
                            const h = cred.heat.slice();
                            let any = false;
                            for (let i = 0; i < h.length; i++) {
                                if (h[i] !== 0) { h[i] *= 0.86; if (Math.abs(h[i]) < 0.03) h[i] = 0; any = true; }
                            }
                            if (any) cred.heat = h;
                        }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6 * surf.u
                        Repeater {
                            model: cred.cells
                            Rectangle {
                                required property int index
                                readonly property real v: cred.heat[index] || 0
                                readonly property bool armed: surf.ctx.buffer.length > 0
                                width: 14 * surf.u
                                height: (6 + Math.abs(v) * 34) * surf.u
                                anchors.verticalCenter: parent.verticalCenter
                                color: v < 0 ? surf.dimCyan : surf.stateColor
                                opacity: surf.ctx.state === "checking"
                                    ? 0.35 + 0.65 * Math.abs(Math.sin((Date.now() / 90 + index) * 0.5 + checkPulse.t))
                                    : (armed ? 0.32 : 0.12) + Math.abs(v) * 0.68
                            }
                        }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2 * surf.u; color: surf.stateColor; opacity: 0.6 }
                    Text {
                        anchors.left: parent.right; anchors.leftMargin: 18 * surf.u
                        anchors.verticalCenter: parent.verticalCenter
                        text: surf.ctx.caps ? "CAPS" : ""
                        color: surf.blue
                        font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 20 * surf.u
                    }
                    NumberAnimation {
                        id: shake
                        target: cred; property: "shakeP"
                        from: 1; to: 0; duration: 560
                        easing.type: Easing.Linear
                    }
                    Item {
                        id: checkPulse
                        property real t: 0
                        NumberAnimation on t { from: 0; to: 100; duration: 100000; loops: Animation.Infinite; running: surf.ctx.state === "checking" }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: {
                        const s = Math.floor((clock.now - surf.ctx.lockedAt) / 1000);
                        const hh = String(Math.floor(s / 3600)).padStart(2, "0");
                        const mm = String(Math.floor(s / 60) % 60).padStart(2, "0");
                        const ss = String(s % 60).padStart(2, "0");
                        return "SEALED " + hh + ":" + mm + ":" + ss
                            + "   ·   ATTEMPTS " + String(surf.ctx.failures).padStart(2, "0")
                            + "   ·   VOICE " + (surf.ctx.voiceSource.indexOf("ollama") === 0 ? "LOCAL-LLM" : "BUILTIN");
                    }
                    color: surf.ctx.failures >= 3 ? surf.red : surf.dimCyan
                    font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 22 * surf.u
                    font.letterSpacing: 3 * surf.u
                }
            }

            // ---------- HUD ----------
            Column {   // top-left: identity and state
                visible: surf.primary
                x: 64 * surf.u; y: 56 * surf.u
                spacing: 10 * surf.u
                Text {
                    text: "ARES // SENTINEL"
                    color: surf.cyan; opacity: 0.8
                    font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 22 * surf.u; font.letterSpacing: 7 * surf.u
                }
                Text {
                    text: "STATE " + surf.ctx.state.toUpperCase()
                    color: surf.stateColor; opacity: 0.7
                    font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 20 * surf.u; font.letterSpacing: 4 * surf.u
                }
                Text {   // optical sensor status; hidden when no camera is attached
                    visible: surf.ctx.camState === "ok" || surf.ctx.camState === "start" || surf.ctx.camState === "lost"
                    // A lost or covered camera is not announced (it would tell an intruder they are unseen).
                    text: "OPTIC " + (surf.ctx.camSimulated ? "SIMULATED" : "ONLINE")
                    color: surf.dimCyan
                    font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 20 * surf.u; font.letterSpacing: 4 * surf.u
                }
            }

            Column {   // top-right: clock
                visible: surf.primary
                anchors.right: parent.right; anchors.rightMargin: 64 * surf.u
                y: 52 * surf.u
                Text {
                    anchors.right: parent.right
                    text: Qt.formatTime(new Date(clock.now), "HH:mm")
                    color: surf.cyan; opacity: surf.ctx.dormant ? 0.35 : 0.85
                    font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 96 * surf.u; font.weight: Font.Light
                }
                Text {
                    anchors.right: parent.right
                    text: Qt.formatDate(new Date(clock.now), "dddd dd MMM yyyy").toUpperCase()
                    color: surf.dimCyan
                    font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 20 * surf.u; font.letterSpacing: 4 * surf.u
                }
            }

            Column {   // bottom-left: incident log (appears after failures)
                visible: surf.primary
                x: 64 * surf.u
                anchors.bottom: parent.bottom; anchors.bottomMargin: 56 * surf.u
                spacing: 6 * surf.u
                Repeater {
                    model: incidents
                    Text {
                        required property string line
                        text: line
                        color: surf.red; opacity: 0.75
                        font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 21 * surf.u; font.letterSpacing: 3 * surf.u
                    }
                }
                Text {
                    text: "PERIMETER  " + (surf.ctx.preview ? "PREVIEW" : "ALL DISPLAYS SEALED")
                    color: surf.dimCyan
                    font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 21 * surf.u; font.letterSpacing: 3 * surf.u
                }
            }

            Text {   // every monitor, bottom-right: live subject coordinates
                anchors.right: parent.right; anchors.rightMargin: 64 * surf.u
                anchors.bottom: parent.bottom; anchors.bottomMargin: 56 * surf.u
                text: {
                    const c = surf.ctx;
                    const now = clock.now;
                    // Posture-free: subject count, bearing, and how long the current subject has been observed.
                    if (c.camState === "ok" && c.camSeenAt > 0 && now - c.camSeenAt < c.camHoldMs) {
                        // Bearing of the helm's gaze: it keeps drifting with the head during the concealment hold.
                        const deg = Math.round(c.gazeYaw * 45);
                        const held = Math.max(0, Math.floor((now - c.camTrackStart) / 1000));
                        const mm = Math.floor(held / 60), ss = held % 60;
                        return "OPTIC  SUBJECTS " + String(Math.max(1, c.camN)).padStart(2, "0")
                            + "  BRG " + (deg >= 0 ? "+" : "-") + String(Math.abs(deg)).padStart(2, "0")
                            + "  OBSERVED " + (mm > 99 ? "99+" : String(mm).padStart(2, "0")) + ":" + String(ss).padStart(2, "0");
                    }
                    // Camera running: the count always shows, even when the room is empty.
                    if (c.camState === "ok") return "OPTIC  SUBJECTS 00  PERIMETER SWEEP";
                    if (c.pointerValid)
                        return "SUBJECT  X " + String(Math.round(c.pointerX)).padStart(5, "0")
                            + "  Y " + String(Math.round(c.pointerY)).padStart(5, "0");
                    return "SUBJECT  ACQUIRING";
                }
                color: surf.ctx.failures >= 3 ? surf.red : surf.dimCyan
                opacity: surf.ctx.dormant ? 0.4 : 0.9
                font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 21 * surf.u; font.letterSpacing: 3 * surf.u
            }
        }

        // ---------- Tracking bracket: sits on Ares's focus point (where the helm is looking) ----------
        // The helm's pose already carries the smoothing, so the bracket follows it directly and the two never
        // disagree. Tight and labelled SUBJECT when Ares is locked on someone; wider and labelled SCAN while it
        // patrols. It crosses onto the side monitors when Ares looks that far.
        Item {
            id: reticle
            readonly property real lockOn: surf.ctx.failures >= 3 ? 1 : surf.ctx.gazeLock
            // Acquisition: on a real arrival the bracket drops in wide and bright, collapses onto the subject with
            // a hard snap and reads SUBJECT ACQUIRED for a moment ("it sees me"). acq runs 1 -> 0.
            property real acq: 0            // 1 -> 0: wide bright bracket collapsing onto the subject
            property real flare: 0          // the snap: a brief thick, white-hot bracket once it lands
            property real _labelUntil: 0
            readonly property real size: (150 - 62 * lockOn + 420 * acq * acq) * surf.u
            Connections {
                target: surf.ctx
                function onArrived() { reticle._labelUntil = Date.now() + 2200; acquire.restart(); }
            }
            SequentialAnimation {
                id: acquire
                NumberAnimation { target: reticle; property: "acq"; from: 1; to: 0; duration: 900; easing.type: Easing.InOutCubic }
                NumberAnimation { target: reticle; property: "flare"; from: 1; to: 0; duration: 1100; easing.type: Easing.OutCubic }
            }
            readonly property real rx: surf.ctx.gazeX - surf.screenX
            readonly property real ry: Math.max(size / 2, Math.min(surf.height - size / 2, surf.ctx.gazeY - surf.screenY))
            visible: surf.ctx.gazeOn && !surf.ctx.dormant && rx > -size && rx < surf.width + size
            opacity: Math.min(1, 0.45 + 0.55 * lockOn + acq)
            x: rx - size / 2; y: ry - size / 2
            width: size; height: size

            Repeater {
                model: 4
                Item {
                    required property int index
                    readonly property bool r: index % 2 === 1
                    readonly property bool b: index > 1
                    x: r ? reticle.width - 26 * surf.u : 0
                    y: b ? reticle.height - 26 * surf.u : 0
                    width: 26 * surf.u; height: 26 * surf.u
                    readonly property color c: Qt.tint(surf.stateColor, Qt.rgba(0.85, 1, 1, Math.max(reticle.acq, reticle.flare) * 0.8))
                    readonly property real t: (3 + 3 * reticle.flare) * surf.u
                    Rectangle { width: parent.width; height: parent.t; y: parent.b ? parent.height - height : 0; color: parent.c }
                    Rectangle { width: parent.t; height: parent.height; x: parent.r ? parent.width - width : 0; color: parent.c }
                }
            }
            Text {
                anchors.left: parent.right; anchors.leftMargin: 8 * surf.u
                anchors.top: parent.top
                text: surf.ctx.failures >= 3 ? "HOSTILE"
                    : clock.now < reticle._labelUntil ? "SUBJECT ACQUIRED"
                    : reticle.lockOn > 0.6 ? "SUBJECT" : "SCAN"
                color: reticle.flare > 0.05 ? Qt.tint(surf.stateColor, Qt.rgba(0.85, 1, 1, reticle.flare * 0.8)) : surf.stateColor
                opacity: 0.9
                font.family: "IosevkaTerm Nerd Font Mono"; font.pixelSize: 26 * surf.u; font.letterSpacing: 4 * surf.u
            }
        }
    }

    ListModel { id: incidents }
    Connections {
        target: surf.ctx
        function onDenied(count) {
            if (count >= 2) {
                incidents.append({ line: "INCIDENT " + String(count).padStart(2, "0") + "  "
                    + Qt.formatTime(new Date(), "HH:mm:ss") + "  CREDENTIAL MISMATCH" });
                while (incidents.count > 6) incidents.remove(0);
            }
        }
    }

    QtObject {
        id: clock
        property real now: Date.now()
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.now = Date.now() }

    Component.onCompleted: {
        if (!surf.ctx) {
            console.error("ares-lock: surface has no LockContext; exiting so the launcher falls back to hyprlock");
            Qt.exit(4);
            return;
        }
        keyCatcher.forceActiveFocus();
    }
}
