#!/usr/bin/env python3
"""Render the source with the host data file and compare with the Stow originals (and the live HOME).

usage: verify_render.py [--stow DIR] [--data FILE] [module ...]

Pass condition: every file the migration table covers renders byte-identical (content, exec bit, symlink
target) to its Stow source, and no extra file is rendered. Live HOME paths that exist are compared too; a
live difference is reported as DRIFT (pre-existing, not a render fault) and does not fail the run.
"""
import argparse, os, subprocess, sys, tempfile, importlib.util

HOME = os.path.expanduser("~")
HI = os.path.join(HOME, "home-infra")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_migrate():
    spec = importlib.util.spec_from_file_location("migrate", f"{HI}/scripts/liquid-tron-migrate/migrate.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def stow_files(m, stow, mod):
    ex = m.MODULES[mod]
    out = subprocess.run(["git", "-C", stow, "ls-files", "-s", "-z", mod], capture_output=True, text=True).stdout
    for line in out.split("\0"):
        if not line:
            continue
        meta, path = line.split("\t", 1)
        rel = path[len(mod) + 1:]
        if "/" not in rel and (rel in m.ROOT_SKIP or rel in m.ROOT_DOCS):
            continue
        if any(rel == e or (e.endswith("/") and rel.startswith(e)) for e in ex):
            continue
        yield rel, meta.split()[0], os.path.join(stow, path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stow", default=f"{HI}/machines/7800x/dotfiles")
    ap.add_argument("--data", default=f"{HI}/machines/7800x/chezmoi/chezmoi.toml")
    ap.add_argument("modules", nargs="*")
    a = ap.parse_args()
    m = load_migrate()
    listed = os.path.join(REPO, "modules.txt")
    migrated = open(listed).read().split() if os.path.exists(listed) else []
    mods = a.modules or migrated
    dest = tempfile.mkdtemp(prefix="lt-render-")
    r = subprocess.run([f"{REPO}/scripts/render.sh", dest, a.data], capture_output=True, text=True)
    if r.returncode:
        print("RENDER FAILED", r.stderr[-800:])
        return 1
    expected, bad, drift, live_ok, missing_live = {}, [], [], 0, 0
    for mod in mods:
        for rel, mode, src in stow_files(m, a.stow, mod):
            expected[rel] = (mode, src)
    # modules not yet migrated are not rendered; only compare files of the requested modules
    for rel, (mode, src) in sorted(expected.items()):
        out = os.path.join(dest, rel)
        if mode == "120000":
            if not os.path.islink(out) or os.readlink(out) != os.readlink(src):
                bad.append(f"symlink {rel}")
            continue
        if not os.path.isfile(out) or os.path.islink(out):
            bad.append(f"missing {rel}")
            continue
        if open(out, "rb").read() != open(src, "rb").read():
            bad.append(f"content {rel}")
        elif (os.stat(out).st_mode & 0o111 != 0) != (mode == "100755"):
            bad.append(f"mode {rel}")
        live = os.path.join(HOME, rel)
        if os.path.exists(live):
            if open(live, "rb").read() == open(src, "rb").read():
                live_ok += 1
            else:
                drift.append(rel)
        else:
            missing_live += 1
    extra = []
    if not a.modules:
        for root, _, files in os.walk(dest):
            for f in files:
                p = os.path.relpath(os.path.join(root, f), dest)
                if p not in expected:
                    extra.append(p)
        for root, dirs, files in os.walk(dest):
            for d in dirs:
                p = os.path.join(root, d)
                if os.path.islink(p):
                    q = os.path.relpath(p, dest)
                    if q not in expected:
                        extra.append(q)
    print(f"files compared {len(expected)}; live identical {live_ok}; live absent {missing_live}; live DRIFT {len(drift)}")
    for d in drift[:10]:
        print("  DRIFT", d)
    for b in bad[:20]:
        print("  FAIL", b)
    for e in extra[:20]:
        print("  EXTRA", e)
    ok = not bad and not extra
    print("PASS" if ok else f"FAIL ({len(bad)} differ, {len(extra)} extra)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
