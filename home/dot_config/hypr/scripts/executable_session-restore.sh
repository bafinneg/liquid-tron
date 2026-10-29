#!/usr/bin/env bash
# Restore the last Hyprland session from ~/.local/state/hypr-session/last.json.
# Called via exec-once at Hyprland startup (conf.d/autostart.conf).
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-session"
SNAPSHOT_FILE="$STATE_DIR/last.json"
LOG_FILE="$STATE_DIR/restore.log"
CONF_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/session-restore.conf"

if [[ ! -f "$SNAPSHOT_FILE" ]]; then
    echo "session-restore: no snapshot found at $SNAPSHOT_FILE — nothing to restore" | tee -a "$LOG_FILE"
    exit 0
fi

# 2s startup delay — let Hyprland finish compositor init before dispatching.
sleep 2

python3 - "$SNAPSHOT_FILE" "$CONF_FILE" "$LOG_FILE" <<'PYEOF'
import sys, json, os, re, subprocess, time

snapshot_file = sys.argv[1]
conf_file     = sys.argv[2]
log_file      = sys.argv[3]

# Parse override map from session-restore.conf.
# [skip]     class = SKIP
# [override] class = replacement-cmdline
skip_classes = set()
overrides    = {}

if os.path.exists(conf_file):
    section = None
    for line in open(conf_file):
        line = line.rstrip()
        m = re.match(r'^\[(\w+)\]', line)
        if m:
            section = m.group(1).lower(); continue
        if section and '=' in line:
            key, _, val = line.partition('=')
            key = key.strip(); val = val.strip()
            if not key:
                continue
            if section == 'skip':
                skip_classes.add(key)
            elif section == 'override':
                overrides[key] = val

with open(snapshot_file) as f:
    entries = json.load(f)

log = open(log_file, 'w')

launched = 0
for entry in entries:
    cls        = entry.get('class', '')
    cmdline    = entry.get('cmdline', [cls])

    if cls in skip_classes:
        log.write(f'SKIP {cls} (in skip list)\n')
        continue

    if cls in overrides:
        cmd = overrides[cls]
        log.write(f'OVERRIDE {cls} → {cmd}\n')
    else:
        # Shell-quote the captured argv.
        cmd = ' '.join(
            a if re.match(r'^[A-Za-z0-9_./:@=+-]+$', a) else f"'{a.replace(chr(39), chr(39)+chr(92)+chr(39)+chr(39))}'"
            for a in cmdline
        )
        log.write(f'RESTORE {cls} → {cmd}\n')

    result = subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.exec_cmd(' + json.dumps(cmd, ensure_ascii=False) + ')'],
                            capture_output=True, text=True)
    if result.returncode != 0:
        log.write(f'  ERROR: {result.stderr.strip()}\n')
    else:
        launched += 1

    time.sleep(0.2)   # 200ms stagger between launches

log.write(f'\nsession-restore: launched {launched}/{len(entries)} entries\n')
log.close()
print(f'session-restore: launched {launched}/{len(entries)} — see {log_file}', flush=True)
PYEOF
