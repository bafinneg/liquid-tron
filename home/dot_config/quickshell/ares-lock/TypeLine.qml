// Telemetry line that types itself out; on deny it decodes out of scrambled glyphs.
import QtQuick

Text {
    id: tl
    property string target: ""
    property int serial: 0
    property bool scramble: false
    property int _n: 0
    property string _noise: "▚▞▙▛▜▟░▒#%/\\<>"

    textFormat: Text.PlainText
    font.family: "IosevkaTerm Nerd Font Mono"
    property real spacingRatio: 0.18
    font.letterSpacing: Math.round(spacingRatio * 34)

    function _render() {
        let s = target.substring(0, _n);
        if (scramble) {
            const tail = Math.min(4, target.length - _n);
            for (let i = 0; i < tail; i++) s += _noise[Math.floor(Math.random() * _noise.length)];
        }
        text = s + (_n < target.length || (Date.now() / 530 | 0) % 2 === 0 ? "▌" : " ");
    }

    onSerialChanged: { _n = 0; typer.restart(); }
    Timer {
        id: typer
        interval: tl.scramble ? 34 : 24; repeat: true
        onTriggered: { if (tl._n < tl.target.length) tl._n++; tl._render(); }
    }
    Timer { interval: 530; running: true; repeat: true; onTriggered: tl._render() }
}
