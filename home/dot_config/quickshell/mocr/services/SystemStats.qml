import QtQuick
import Quickshell.Io

// Polls /proc/stat, /proc/meminfo, /sys/class/hwmon, /proc/net/dev every 2s.
// Exposes reactive properties for aggregate metrics (used by bar modules) and
// detailed breakdowns (used by detail popovers).
// hwmon index is not stable across reboots — discover k10temp dynamically.

Item {
    id: stats
    visible: false
    width: 0; height: 0

    // ── Exposed properties (aggregate) ─────────────────────
    readonly property int cpuUsage: _cpuUsage       // 0–100
    readonly property int memUsage: _memUsage       // 0–100
    readonly property int temperature: _temperature // °C
    readonly property int netDown: _netDown         // bytes/sec
    readonly property int netUp: _netUp             // bytes/sec
    readonly property bool netConnected: _netConnected

    // ── History arrays (last 60 samples, newest last) ──────
    readonly property var cpuHistory: _cpuHistory
    readonly property var memHistory: _memHistory
    readonly property var tempHistory: _tempHistory
    readonly property var netDownHistory: _netDownHistory
    readonly property var netUpHistory: _netUpHistory

    // ── Per-core CPU (one entry per logical thread) ────────
    readonly property var coreUsages: _coreUsages  // array of ints 0–100

    // ── Detailed meminfo (kB) ──────────────────────────────
    readonly property real memTotalKB: _memTotalKB
    readonly property real memFreeKB: _memFreeKB
    readonly property real memAvailableKB: _memAvailableKB
    readonly property real memBuffersKB: _memBuffersKB
    readonly property real memCachedKB: _memCachedKB

    // ── Per-sensor temperatures ────────────────────────────
    readonly property var tempSensors: _tempSensors  // [{name, value, trend}]

    // ── Network interface metadata ─────────────────────────
    readonly property string netInterface: _netInterface
    readonly property string netIpAddress: _netIpAddress
    readonly property string netLinkSpeed: _netLinkSpeed

    // ── Internal state ─────────────────────────────────────
    property int _cpuUsage: 0
    property int _memUsage: 0
    property int _temperature: 0
    property int _netDown: 0
    property int _netUp: 0
    property bool _netConnected: false

    property var _cpuHistory: []
    property var _memHistory: []
    property var _tempHistory: []
    property var _netDownHistory: []
    property var _netUpHistory: []

    property var _coreUsages: []
    property real _memTotalKB: 0
    property real _memFreeKB: 0
    property real _memAvailableKB: 0
    property real _memBuffersKB: 0
    property real _memCachedKB: 0
    property var _tempSensors: []
    property string _netInterface: ""
    property string _netIpAddress: ""
    property string _netLinkSpeed: ""

    property real _prevCpuTotal: 0
    property real _prevCpuIdle: 0
    property var _prevCoreTotal: []
    property var _prevCoreIdle: []
    property real _prevNetRx: 0
    property real _prevNetTx: 0
    property real _prevNetTime: 0
    property string _hwmonPath: ""
    property string _hwmonOutput: ""
    property var _tempSensorPrev: ({})

    readonly property int _maxHistory: 60

    function _pushHistory(arr, val) {
        var a = arr.slice()
        a.push(val)
        if (a.length > _maxHistory) a.shift()
        return a
    }

    // ── hwmon discovery (returns directory path) ───────────
    // Try k10temp first (CPU die), then asus-ec-sensors (board EC),
    // then nct6799 (Super I/O).  Indices are NOT stable across reboots.
    Process {
        id: hwmonDiscovery
        command: ["bash", "-c",
            "for want in k10temp asusec nct6799; do " +
            "for d in /sys/class/hwmon/hwmon*/; do " +
            "if [ \"$(cat \"$d/name\" 2>/dev/null)\" = \"$want\" ]; then " +
            "echo \"$d\"; exit 0; fi; done; done; echo ''"
        ]
        running: true
        stdout: SplitParser {
            onRead: data => { stats._hwmonOutput += data }
        }
        onExited: {
            stats._hwmonPath = stats._hwmonOutput.trim()
        }
    }

    // ── Polling process ────────────────────────────────────
    Process {
        id: pollProcess
        command: ["bash", "-c", stats._pollScript()]
        stdout: SplitParser {
            onRead: data => { stats._parseLine(data) }
        }
        onExited: {
            stats._cpuHistory = stats._pushHistory(stats._cpuHistory, stats._cpuUsage)
            stats._memHistory = stats._pushHistory(stats._memHistory, stats._memUsage)
            stats._tempHistory = stats._pushHistory(stats._tempHistory, stats._temperature)
            stats._netDownHistory = stats._pushHistory(stats._netDownHistory, stats._netDown)
            stats._netUpHistory = stats._pushHistory(stats._netUpHistory, stats._netUp)
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!pollProcess.running) {
                pollProcess.running = true
            }
        }
    }

    function _pollScript(): string {
        var hwmon = _hwmonPath
        if (hwmon.length > 0 && hwmon[hwmon.length - 1] !== '/') hwmon += '/'
        return [
            "set -euo pipefail",
            // CPU: aggregate + per-core in one pass through /proc/stat
            "cores=''",
            "while read -r name user nice system idle iowait irq softirq steal rest; do",
            "  case \"$name\" in",
            "    cpu)",
            "      total=$((user+nice+system+idle+iowait+irq+softirq+steal))",
            "      echo \"CPU:$total:$idle\"",
            "      ;;",
            "    cpu[0-9]*)",
            "      ctotal=$((user+nice+system+idle+iowait+irq+softirq+steal))",
            "      cores=\"${cores:+$cores,}$ctotal:$idle\"",
            "      ;;",
            "    *) break ;;",
            "  esac",
            "done < /proc/stat",
            "echo \"CORES:$cores\"",
            // Memory: detailed breakdown
            "mt=0; mf=0; ma=0; mb=0; mc=0",
            "while IFS=': ' read -r key val rest; do",
            "  case $key in",
            "    MemTotal) mt=$val;;",
            "    MemFree) mf=$val;;",
            "    MemAvailable) ma=$val;;",
            "    Buffers) mb=$val;;",
            "    Cached) mc=$val;;",
            "  esac",
            "done < /proc/meminfo",
            "echo \"MEM:$mt:$ma\"",
            "echo \"MEMDETAIL:$mt:$mf:$ma:$mb:$mc\"",
            // Temperature: all sensors from discovered hwmon
            "sensors=''",
            hwmon
              ? "for f in " + hwmon + "temp*_input; do\n" +
                "  [ -f \"$f\" ] || continue\n" +
                "  num=${f##*/}; num=${num%_input}; num=${num#temp}\n" +
                "  lbl=$(cat " + hwmon + "temp${num}_label 2>/dev/null || echo \"temp${num}\")\n" +
                "  val=$(cat \"$f\" 2>/dev/null || echo 0)\n" +
                "  sensors=\"${sensors:+$sensors,}${lbl}:${val}\"\n" +
                "done"
              : "true",
            "echo \"TMPSENSORS:$sensors\"",
            hwmon
              ? "echo \"TMP:$(cat " + hwmon + "temp1_input 2>/dev/null || echo 0)\""
              : "echo \"TMP:\"",
            // Network: aggregate bandwidth + interface metadata
            "rx=0; tx=0; iface=''",
            "while read -r line; do",
            "  ifn=${line%%:*}; ifn=${ifn## }",
            "  [ \"$ifn\" = \"lo\" ] && continue",
            "  set -- ${line#*:}",
            "  if [ $# -ge 9 ]; then",
            "    rx=$((rx+$1)); tx=$((tx+$9))",
            "    [ -z \"$iface\" ] && iface=$ifn",
            "  fi",
            "done < <(tail -n+3 /proc/net/dev)",
            "echo \"NET:$rx:$tx:$(date +%s%3N)\"",
            "if [ -n \"$iface\" ]; then",
            "  ip=$(ip -4 addr show \"$iface\" 2>/dev/null | sed -n 's|.*inet \\([^/]*\\)/.*|\\1|p' | head -1)",
            "  speed=$(cat /sys/class/net/$iface/speed 2>/dev/null || echo '?')",
            "  echo \"NETINFO:$iface:${ip:-?}:${speed}\"",
            "fi"
        ].join("\n")
    }

    function _parseLine(line: string): void {
        if (line.startsWith("CPU:")) {
            var parts = line.substring(4).split(":")
            var total = parseFloat(parts[0])
            var idle = parseFloat(parts[1])
            if (_prevCpuTotal > 0) {
                var dTotal = total - _prevCpuTotal
                var dIdle = idle - _prevCpuIdle
                _cpuUsage = dTotal > 0 ? Math.round((1 - dIdle / dTotal) * 100) : 0
            }
            _prevCpuTotal = total
            _prevCpuIdle = idle

        } else if (line.startsWith("CORES:")) {
            var coreData = line.substring(6).split(",")
            var usages = []
            if (_prevCoreTotal.length !== coreData.length) {
                var t = [], u = []
                for (var j = 0; j < coreData.length; j++) { t.push(0); u.push(0) }
                _prevCoreTotal = t
                _prevCoreIdle = u
            }
            for (var i = 0; i < coreData.length; i++) {
                var cp = coreData[i].split(":")
                var ct = parseFloat(cp[0])
                var ci = parseFloat(cp[1])
                if (_prevCoreTotal[i] > 0) {
                    var dcTotal = ct - _prevCoreTotal[i]
                    var dcIdle = ci - _prevCoreIdle[i]
                    usages.push(dcTotal > 0 ? Math.round((1 - dcIdle / dcTotal) * 100) : 0)
                } else {
                    usages.push(0)
                }
                _prevCoreTotal[i] = ct
                _prevCoreIdle[i] = ci
            }
            _coreUsages = usages

        } else if (line.startsWith("MEMDETAIL:")) {
            var md = line.substring(10).split(":")
            _memTotalKB = parseFloat(md[0])
            _memFreeKB = parseFloat(md[1])
            _memAvailableKB = parseFloat(md[2])
            _memBuffersKB = parseFloat(md[3])
            _memCachedKB = parseFloat(md[4])

        } else if (line.startsWith("MEM:")) {
            var mp = line.substring(4).split(":")
            var memTotal = parseFloat(mp[0])
            var memAvail = parseFloat(mp[1])
            _memUsage = memTotal > 0 ? Math.round((1 - memAvail / memTotal) * 100) : 0

        } else if (line.startsWith("TMPSENSORS:")) {
            var sensorStr = line.substring(11)
            if (sensorStr.length === 0) { _tempSensors = []; return }
            var sensorParts = sensorStr.split(",")
            var sensors = []
            var prevMap = _tempSensorPrev
            var newPrev = {}
            for (var s = 0; s < sensorParts.length; s++) {
                var sp = sensorParts[s].split(":")
                if (sp.length >= 2) {
                    var sname = sp[0]
                    var svalue = Math.round(parseInt(sp[1]) / 1000)
                    var prev = prevMap[sname] ? prevMap[sname].slice() : []
                    prev.push(svalue)
                    if (prev.length > 5) prev.shift()
                    newPrev[sname] = prev
                    var trend = "\u2192"  // →
                    if (prev.length >= 2) {
                        var diff = prev[prev.length - 1] - prev[0]
                        if (diff > 1) trend = "\u2191"      // ↑
                        else if (diff < -1) trend = "\u2193" // ↓
                    }
                    sensors.push({name: sname, value: svalue, trend: trend})
                }
            }
            _tempSensorPrev = newPrev
            _tempSensors = sensors

        } else if (line.startsWith("TMP:")) {
            var raw = line.substring(4).trim()
            _temperature = raw.length > 0 ? Math.round(parseInt(raw) / 1000) : -1

        } else if (line.startsWith("NET:")) {
            var np = line.substring(4).split(":")
            var rxBytes = parseFloat(np[0])
            var txBytes = parseFloat(np[1])
            var ts = parseFloat(np[2])
            _netConnected = (rxBytes > 0 || txBytes > 0)
            if (_prevNetTime > 0) {
                var dt = (ts - _prevNetTime) / 1000
                if (dt > 0) {
                    _netDown = Math.round((rxBytes - _prevNetRx) / dt)
                    _netUp = Math.round((txBytes - _prevNetTx) / dt)
                }
            }
            _prevNetRx = rxBytes
            _prevNetTx = txBytes
            _prevNetTime = ts

        } else if (line.startsWith("NETINFO:")) {
            var ni = line.substring(8).split(":")
            if (ni.length >= 3) {
                _netInterface = ni[0]
                _netIpAddress = ni[1]
                _netLinkSpeed = ni[2]
            }
        }
    }
}
