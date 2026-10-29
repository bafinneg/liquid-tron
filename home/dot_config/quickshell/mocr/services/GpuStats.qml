pragma Singleton

import QtQuick
import Quickshell.Io

// GPU telemetry singleton — polls `nvidia-smi` every 2s for aggregate
// utilization, thermals, VRAM, and power. Consumers get stable numeric
// values even when nvidia-smi is absent or fails.
Item {
    id: stats
    visible: false
    width: 0; height: 0

    readonly property int gpuUsage: _gpuUsage
    readonly property var gpuHistory: _gpuHistory
    readonly property bool available: _available
    readonly property int gpuTemp: _gpuTemp
    readonly property int vramUsed: _vramUsed
    readonly property int vramTotal: _vramTotal
    readonly property real powerDraw: _powerDraw
    readonly property var vramHistory: _vramHistory

    property int _gpuUsage: 0
    property var _gpuHistory: []
    property bool _available: false
    property bool _gotSampleThisTick: false
    property int _gpuTemp: 0
    property int _vramUsed: 0
    property int _vramTotal: 0
    property real _powerDraw: 0
    property var _vramHistory: []

    readonly property int _maxHistory: 60

    function _pushHistory(arr, val) {
        var a = arr.slice()
        a.push(val)
        if (a.length > _maxHistory) a.shift()
        return a
    }

    Process {
        id: pollProcess
        command: ["bash", "-c",
            "if ! command -v nvidia-smi >/dev/null 2>&1; then echo 'UNAVAILABLE'; exit 0; fi\n" +
            "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits 2>/dev/null | head -1"
        ]
        stdout: SplitParser {
            onRead: data => { stats._parseLine(data) }
        }
        onExited: {
            if (stats._available && stats._gotSampleThisTick) {
                stats._gpuHistory = stats._pushHistory(stats._gpuHistory, stats._gpuUsage)
                var vramPct = stats._vramTotal > 0 ? Math.round(100 * stats._vramUsed / stats._vramTotal) : 0
                stats._vramHistory = stats._pushHistory(stats._vramHistory, Math.max(0, Math.min(100, vramPct)))
            }
            stats._gotSampleThisTick = false
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!pollProcess.running) pollProcess.running = true
        }
    }

    function _resetUnavailable() {
        _available = false
        _gpuUsage = 0
        _gpuTemp = 0
        _vramUsed = 0
        _vramTotal = 0
        _powerDraw = 0
    }

    function _parseLine(line: string): void {
        var raw = line.trim()
        if (raw === "UNAVAILABLE" || raw.length === 0) {
            _resetUnavailable()
            return
        }
        var parts = raw.split(",")
        if (parts.length < 5) {
            console.warn("GpuStats parse error: expected 5 CSV fields, got", parts.length)
            _resetUnavailable()
            return
        }
        var usage = parseInt(parts[0].trim())
        var temp = parseInt(parts[1].trim())
        var used = parseInt(parts[2].trim())
        var total = parseInt(parts[3].trim())
        var power = parseFloat(parts[4].trim())
        if (isNaN(usage) || isNaN(temp) || isNaN(used) || isNaN(total) || isNaN(power)) {
            console.warn("GpuStats parse error: non-numeric CSV line", raw)
            _resetUnavailable()
            return
        }
        _available = true
        _gpuUsage = Math.max(0, Math.min(100, usage))
        _gpuTemp = Math.max(0, temp)
        _vramUsed = Math.max(0, used)
        _vramTotal = Math.max(0, total)
        _powerDraw = Math.max(0, power)
        _gotSampleThisTick = true
    }
}
