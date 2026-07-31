#!/bin/bash
# install-continuity.sh — install (or drift-check) the session-journal continuity layer.
# CONTINUITY-LAYER:installer-v1
#
# Installs user-level, deliberately: the WAL must protect every project on the
# machine, not just this repo — the sessions that die hardest are the long
# orchestration runs in *other* projects.
#
#   bash scripts/install-continuity.sh            # install / repair
#   bash scripts/install-continuity.sh --check    # report drift, fix nothing, exit 1 on drift
#
# What it wires (all identified in settings by the string "session-journal.sh",
# so re-running replaces our entries and touches nothing else):
#   PostToolUse *            -> post-tool      (async breadcrumb, the hot path)
#   PreToolUse Agent|Task    -> pre-agent      (manifest: subagent spawn)
#   Stop                     -> stop           (turn-boundary stamp)
#   SubagentStop             -> subagent-stop  (report harvest -> journal+manifest+worker)
#   SessionStart             -> session-start  (sync: header, manifest re-inject, dirty scan)
#   SessionEnd               -> session-end    (clean-close marker)

set -u

MODE="${1:-install}"
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
CANON="$REPO_DIR/hooks/session-journal.sh"
DEST_DIR="$HOME/.claude/hooks"
DEST="$DEST_DIR/session-journal.sh"
SETTINGS="$HOME/.claude/settings.json"
JROOT="$HOME/.claude/session-journals"

PY=""
for c in python3 python py; do
    if "$c" -c "pass" >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -n "$PY" ] || { echo "[FAIL] no working python (python3/python/py all failed a real probe)"; exit 1; }

DRIFT=0

# ── 1. hook file ────────────────────────────────────────────────────────────
if [ ! -f "$CANON" ]; then echo "[FAIL] canon missing: $CANON"; exit 1; fi
if cmp -s "$CANON" "$DEST" 2>/dev/null; then
    echo "[ OK ] hook file current: $DEST"
else
    if [ "$MODE" = "--check" ]; then
        echo "[DRIFT] hook file missing or stale: $DEST"
        DRIFT=1
    else
        mkdir -p "$DEST_DIR"
        cp "$CANON" "$DEST"
        echo "[FIXED] hook file installed: $DEST"
    fi
fi

# ── 2. settings wiring ──────────────────────────────────────────────────────
export CONTINUITY_SETTINGS="$SETTINGS" CONTINUITY_MODE="$MODE"
"$PY" - <<'PYEOF'
import json, os, sys, time

settings_path = os.environ["CONTINUITY_SETTINGS"]
check = os.environ["CONTINUITY_MODE"] == "--check"
MARK = "session-journal.sh"
CMD = 'bash "$HOME/.claude/hooks/session-journal.sh"'

WIRING = {
    "PostToolUse":  {"matcher": "*",          "sub": "post-tool",     "async": True,  "timeout": 30},
    "PreToolUse":   {"matcher": "Agent|Task", "sub": "pre-agent",     "async": True,  "timeout": 30},
    "Stop":         {"matcher": None,          "sub": "stop",          "async": True,  "timeout": 30},
    "SubagentStop": {"matcher": None,          "sub": "subagent-stop", "async": True,  "timeout": 30},
    "SessionStart": {"matcher": None,          "sub": "session-start", "async": False, "timeout": 30},
    "SessionEnd":   {"matcher": None,          "sub": "session-end",   "async": False, "timeout": 15},
}

try:
    with open(settings_path, encoding="utf-8") as f:
        settings = json.load(f)
except FileNotFoundError:
    settings = {}
except Exception as e:
    print(f"[FAIL] cannot parse {settings_path}: {e}")
    sys.exit(1)

hooks = settings.setdefault("hooks", {})

def ours(group):
    return any(MARK in h.get("command", "") for h in group.get("hooks", []))

missing, drift = [], False
for event, spec in WIRING.items():
    groups = hooks.get(event, [])
    have = [g for g in groups if ours(g)]
    entry = {"type": "command", "command": f'{CMD} {spec["sub"]}', "timeout": spec["timeout"]}
    if spec["async"]:
        entry["async"] = True
    group = {"hooks": [entry]}
    if spec["matcher"]:
        group["matcher"] = spec["matcher"]
    if len(have) == 1 and have[0] == group:
        continue
    drift = True
    missing.append(event)
    if not check:
        hooks[event] = [g for g in groups if not ours(g)] + [group]

if not drift:
    print("[ OK ] settings wiring current (6 events)")
    sys.exit(0)
if check:
    print(f"[DRIFT] settings wiring stale or missing for: {', '.join(missing)}")
    sys.exit(2)

backup = f"{settings_path}.bak-continuity-{int(time.time())}"
try:
    if os.path.exists(settings_path):
        with open(settings_path, encoding="utf-8") as f:
            content = f.read()
        with open(backup, "w", encoding="utf-8") as f:
            f.write(content)
except Exception as e:
    print(f"[FAIL] could not back up settings: {e}")
    sys.exit(1)

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
import glob
for old in sorted(glob.glob(settings_path + ".bak-continuity-*"))[:-5]:
    try: os.remove(old)   # keep the 5 newest backups only
    except OSError: pass
print(f"[FIXED] settings wiring written for: {', '.join(missing)} (backup: {os.path.basename(backup)})")
PYEOF
rc=$?
if [ "$rc" -eq 2 ]; then DRIFT=1; elif [ "$rc" -ne 0 ]; then exit 1; fi

# ── 3. journal root ─────────────────────────────────────────────────────────
if [ -d "$JROOT" ]; then
    echo "[ OK ] journal root exists: $JROOT"
else
    if [ "$MODE" = "--check" ]; then
        echo "[DRIFT] journal root missing: $JROOT"
        DRIFT=1
    else
        mkdir -p "$JROOT"
        echo "[FIXED] journal root created: $JROOT"
    fi
fi

if [ "$MODE" = "--check" ]; then
    [ "$DRIFT" -eq 0 ] && echo "== continuity layer: no drift ==" || echo "== continuity layer: DRIFT DETECTED (run install-continuity.sh to repair) =="
    exit "$DRIFT"
fi
echo "== continuity layer installed =="
echo "NOTE: hooks load at session start — running sessions keep their old wiring until restarted."
