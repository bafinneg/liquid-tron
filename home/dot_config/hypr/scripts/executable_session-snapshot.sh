#!/usr/bin/env bash
# Snapshot all open Hyprland windows to ~/.local/state/hypr-session/last.json.
# Called by hypr-session-snapshot.service (periodic + at session stop).
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-session"
SNAPSHOT_FILE="$STATE_DIR/last.json"
CONF_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/session-restore.conf"

mkdir -p "$STATE_DIR"

# Resolve HYPRLAND_INSTANCE_SIGNATURE if not imported by systemd.
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hypr_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
    # shellcheck disable=SC2012
    HYPRLAND_INSTANCE_SIGNATURE=$(ls "$hypr_dir/" 2>/dev/null | head -1 || true)
fi

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    echo "session-snapshot: HYPRLAND_INSTANCE_SIGNATURE unresolvable — aborting" >&2
    exit 1
fi

export HYPRLAND_INSTANCE_SIGNATURE

python3 - "$SNAPSHOT_FILE" "$CONF_FILE" <<'PYEOF'
import sys, json, os, re, subprocess

snapshot_file = sys.argv[1]
conf_file     = sys.argv[2]

# Parse [skip] classes from session-restore.conf.
skip_classes = set()
if os.path.exists(conf_file):
    in_skip = False
    for line in open(conf_file):
        line = line.rstrip()
        if re.match(r'^\[skip\]', line, re.IGNORECASE):
            in_skip = True; continue
        if re.match(r'^\[', line):
            in_skip = False; continue
        if in_skip and '=' in line:
            key = line.split('=')[0].strip()
            if key:
                skip_classes.add(key)

result = subprocess.run(['hyprctl', 'clients', '-j'],
                        capture_output=True, text=True, check=True)
clients = json.loads(result.stdout)

out = []
for c in clients:
    if c.get('workspace', {}).get('id', -1) < 1:
        continue
    if c.get('class', '') in skip_classes:
        continue
    pid = c.get('pid', 0)
    try:
        raw = open(f'/proc/{pid}/cmdline', 'rb').read()
        argv = [a.decode('utf-8', errors='replace') for a in raw.split(b'\x00') if a]
    except OSError:
        argv = [c.get('class', '')]
    out.append({
        'class':        c.get('class', ''),
        'workspace_id': c['workspace']['id'],
        'pid':          pid,
        'cmdline':      argv,
    })

tmp = snapshot_file + '.tmp'
with open(tmp, 'w') as f:
    json.dump(out, f, indent=2)
    f.write('\n')
os.replace(tmp, snapshot_file)
print(f'session-snapshot: wrote {len(out)} entries to {snapshot_file}', flush=True)
PYEOF
