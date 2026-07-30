#!/bin/bash
# install-orchestration.sh — install (or drift-check) the orchestration layer:
# the routed agent stable (agents/*.md -> ~/.claude/agents/) and the routing
# rubric (docs/orchestration-rubric.md -> marked block in ~/.claude/CLAUDE.md).
# CONTINUITY-LAYER:orchestration-installer-v1
#
#   bash scripts/install-orchestration.sh            # install / repair
#   bash scripts/install-orchestration.sh --check    # report drift, exit 1 on drift
#
# User-level on purpose: the orchestrator workflow lives in other projects; the
# stable and rubric must exist wherever a session starts. The rubric rides
# ~/.claude/CLAUDE.md between ORCHESTRATION-RUBRIC markers so re-installs replace
# our block and never touch surrounding user content.

set -u

MODE="${1:-install}"
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
AGENTS_SRC="$REPO_DIR/agents"
AGENTS_DEST="$HOME/.claude/agents"
RUBRIC="$REPO_DIR/docs/orchestration-rubric.md"
UCLAUDE="$HOME/.claude/CLAUDE.md"
MARK_START="<!-- ORCHESTRATION-RUBRIC:v1"
MARK_END="<!-- /ORCHESTRATION-RUBRIC:v1 -->"

PY=""
for c in python3 python py; do
    if "$c" -c "pass" >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -n "$PY" ] || { echo "[FAIL] no working python (python3/python/py all failed a real probe)"; exit 1; }

DRIFT=0

# ── 1. agent stable ─────────────────────────────────────────────────────────
for f in "$AGENTS_SRC"/*.md; do
    name=$(basename "$f")
    dest="$AGENTS_DEST/$name"
    if cmp -s "$f" "$dest" 2>/dev/null; then
        echo "[ OK ] agent current: $name"
    elif [ "$MODE" = "--check" ]; then
        echo "[DRIFT] agent missing or stale: $name"
        DRIFT=1
    else
        mkdir -p "$AGENTS_DEST"
        cp "$f" "$dest"
        echo "[FIXED] agent installed: $name"
    fi
done

# ── 2. rubric block in ~/.claude/CLAUDE.md ──────────────────────────────────
export ORCH_RUBRIC="$RUBRIC" ORCH_UCLAUDE="$UCLAUDE" ORCH_MODE="$MODE" \
       ORCH_MS="$MARK_START" ORCH_ME="$MARK_END"
"$PY" - <<'PYEOF'
import os, re, sys, time

rubric_path = os.environ["ORCH_RUBRIC"]
uclaude = os.environ["ORCH_UCLAUDE"]
check = os.environ["ORCH_MODE"] == "--check"
ms, me = os.environ["ORCH_MS"], os.environ["ORCH_ME"]

with open(rubric_path, encoding="utf-8") as f:
    block = f.read().strip() + "\n"

try:
    with open(uclaude, encoding="utf-8") as f:
        content = f.read()
except FileNotFoundError:
    content = ""

pattern = re.compile(re.escape(ms) + r".*?" + re.escape(me) + r"\n?", re.DOTALL)
m = pattern.search(content)
current = m.group(0) if m else None

if current is not None and current.strip() + "\n" == block:
    print("[ OK ] rubric block current in ~/.claude/CLAUDE.md")
    sys.exit(0)
if check:
    print("[DRIFT] rubric block missing or stale in ~/.claude/CLAUDE.md")
    sys.exit(2)

if content:
    backup = f"{uclaude}.bak-orchestration-{int(time.time())}"
    with open(backup, "w", encoding="utf-8") as f:
        f.write(content)

new = pattern.sub(block, content) if m else (content.rstrip() + "\n\n" if content else "") + block
with open(uclaude, "w", encoding="utf-8") as f:
    f.write(new)
print("[FIXED] rubric block written to ~/.claude/CLAUDE.md")
PYEOF
rc=$?
if [ "$rc" -eq 2 ]; then DRIFT=1; elif [ "$rc" -ne 0 ]; then exit 1; fi

if [ "$MODE" = "--check" ]; then
    [ "$DRIFT" -eq 0 ] && echo "== orchestration layer: no drift ==" || echo "== orchestration layer: DRIFT DETECTED (run install-orchestration.sh to repair) =="
    exit "$DRIFT"
fi
echo "== orchestration layer installed =="
