#!/bin/bash
# memory-doctor.sh — one-glance impact audit of the four-system memory architecture.
#
# Reports what each system is actually DOING (loaded? injecting? capturing? when last?),
# not what the config claims. Run from a project root:
#
#   bash scripts/memory-doctor.sh [wing-name]
#
# Wing name is read from .claude/AI_CONTEXT.md ("Wing name for this project: <wing>")
# when not passed as an argument. Exit code = number of FAILs.
#
# Every check is read-only. Cross-platform: macOS, Linux, Windows (Git Bash).

FAILS=0
WARNS=0

ok()   { printf '[ OK ] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; WARNS=$((WARNS+1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAILS=$((FAILS+1)); }

echo "== Memory Doctor — $(basename "$PWD") — $(date '+%Y-%m-%d %H:%M') =="
echo ""

# ── 0. Interpreter (everything python-based depends on this) ─────────────────
PY=""
for c in python3 python py; do
    if "$c" -c "pass" >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -n "$PY" ]; then
    ok "Interpreter: $PY ($("$PY" --version 2>&1))"
else
    fail "Interpreter: no working python3/python/py — every python-based hook is dead"
fi

# ── 1. CLAUDE.md + AI_CONTEXT.md ─────────────────────────────────────────────
echo ""
echo "-- System 1: CLAUDE.md --"
if [ -f CLAUDE.md ]; then
    ok "CLAUDE.md exists ($(wc -l < CLAUDE.md | tr -d ' ') lines, modified $(date -r CLAUDE.md '+%Y-%m-%d'))"
    if grep -q '@.claude/AI_CONTEXT.md' CLAUDE.md; then
        ok "AI_CONTEXT.md import present"
    else
        warn "CLAUDE.md does not import @.claude/AI_CONTEXT.md"
    fi
else
    fail "CLAUDE.md missing from project root"
fi
[ -f .claude/AI_CONTEXT.md ] && ok "AI_CONTEXT.md exists" || warn ".claude/AI_CONTEXT.md missing"

# ── 2. Local file memory (native Claude Code project memory) ─────────────────
echo ""
echo "-- System 2: Local file memory --"
MEMDIR=""
if [ -n "$PY" ]; then
    MEMDIR=$("$PY" -c "
import os, glob
base = os.path.basename(os.getcwd()).lower()
key = ''.join(ch if ch.isalnum() else '-' for ch in base)
hits = [d for d in glob.glob(os.path.expanduser('~/.claude/projects/*/memory'))
        if os.path.isdir(d) and key in os.path.dirname(d).lower().replace('_','-')]
hits.sort(key=os.path.getmtime, reverse=True)
print(hits[0] if hits else '')
" 2>/dev/null)
fi
if [ -n "$MEMDIR" ] && [ -f "$MEMDIR/MEMORY.md" ]; then
    N=$(grep -c '^- \[' "$MEMDIR/MEMORY.md" 2>/dev/null || echo 0)
    ok "Memory dir: $MEMDIR ($N indexed entries, MEMORY.md modified $(date -r "$MEMDIR/MEMORY.md" '+%Y-%m-%d'))"
else
    warn "No memory dir with MEMORY.md found for this project under ~/.claude/projects/"
fi

# ── 3. MemPalace ─────────────────────────────────────────────────────────────
echo ""
echo "-- System 3: MemPalace --"
WING="$1"
if [ -z "$WING" ] && [ -f .claude/AI_CONTEXT.md ]; then
    WING=$(grep -i -o 'Wing name for this project: *`\?[a-z0-9_-]*' .claude/AI_CONTEXT.md | sed 's/.*: *`\?//' | head -1)
fi
if [ -z "$WING" ]; then
    warn "No wing name (pass as arg or add 'Wing name for this project: <wing>' to AI_CONTEXT.md)"
else
    WAKE=$(PYTHONIOENCODING=utf-8 mempalace wake-up --wing "$WING" 2>/dev/null \
        || PYTHONIOENCODING=utf-8 "$PY" -m mempalace wake-up --wing "$WING" 2>/dev/null)
    BYTES=$(printf '%s' "$WAKE" | wc -c | tr -d ' ')
    if [ "$BYTES" -gt 200 ]; then
        ok "Wake-up injects for wing '$WING' ($BYTES bytes)"
    else
        fail "Wake-up produces no meaningful output for wing '$WING' ($BYTES bytes) — session start injection is dead"
    fi
fi
if [ -f ~/.mempalace/identity.txt ] && [ -s ~/.mempalace/identity.txt ]; then
    ok "Identity: $(head -c 80 ~/.mempalace/identity.txt)"
else
    warn "~/.mempalace/identity.txt missing or empty"
fi
for hookfile in mempal-precompact-hook.sh mempal-stop-hook.sh; do
    HITS=$(grep -l "MEMPALACE-PATCH:py-fallback-v3" \
        ~/.claude/plugins/marketplaces/mempalace/.claude-plugin/hooks/$hookfile \
        ~/.claude/plugins/cache/mempalace/mempalace/*/hooks/$hookfile 2>/dev/null | wc -l | tr -d ' ')
    if [ "$HITS" -ge 2 ]; then
        ok "Hook patch py-fallback-v3 in $hookfile ($HITS locations)"
    elif [ "$HITS" -eq 1 ]; then
        warn "Hook patch py-fallback-v3 in $hookfile in only 1 location — run scripts/sync-hooks.sh"
    else
        fail "Hook patch py-fallback-v3 MISSING from $hookfile — plugin update likely overwrote it (run scripts/sync-hooks.sh)"
    fi
done
if [ -f .claude/settings.local.json ] && grep -q 'mempalace wake-up' .claude/settings.local.json; then
    ok "SessionStart wake-up hook present in .claude/settings.local.json"
else
    warn "No SessionStart wake-up hook in .claude/settings.local.json (Phase 7f)"
fi

# ── 4. claude-mem ────────────────────────────────────────────────────────────
echo ""
echo "-- System 4: claude-mem --"
PORT="37777"
[ -n "$PY" ] && PORT=$("$PY" -c "
import json, os
try:
    print(json.load(open(os.path.expanduser('~/.claude-mem/settings.json'))).get('CLAUDE_MEM_WORKER_PORT', '37777'))
except Exception:
    print('37777')
" 2>/dev/null)
HEALTH=$(curl -s -m 4 "http://127.0.0.1:$PORT/api/health" 2>/dev/null)
if [ -n "$HEALTH" ] && [ -n "$PY" ]; then
    echo "$HEALTH" | "$PY" -c "
import json, sys
d = json.load(sys.stdin)
up = round(d.get('uptime', 0) / 3600000, 1)
print(f\"[ OK ] Worker alive on :$PORT — v{d.get('version')}, up {up}h, provider {d.get('ai',{}).get('provider')}\")
" 2>/dev/null || ok "Worker alive on :$PORT"
else
    fail "Worker unreachable on :$PORT — no capture, no injection (plugin starts it at session start; check ~/.claude-mem/logs/)"
fi
if [ -n "$HEALTH" ] && [ -n "$PY" ]; then
    "$PY" -c "
import json, os, urllib.request, urllib.parse, datetime
project = os.path.basename(os.getcwd())
q = urllib.parse.quote(project)
try:
    r = urllib.request.urlopen(f'http://127.0.0.1:$PORT/api/observations?project={q}&limit=1&orderBy=date_desc', timeout=4)
    items = json.loads(r.read().decode()).get('items', [])
    if not items:
        print(f'[WARN] No observations captured for project \"{project}\" yet')
    else:
        ts = items[0].get('created_at', '')[:10]
        days = (datetime.date.today() - datetime.date.fromisoformat(ts)).days if ts else '?'
        flag = '[ OK ]' if isinstance(days, int) and days <= 7 else '[WARN]'
        print(f'{flag} Last observation for \"{project}\": {ts} ({days} days ago) — \"{items[0].get(\"title\",\"\")[:60]}\"')
except Exception as e:
    print(f'[WARN] Could not query observations: {e}')
" 2>/dev/null
    FAILED_SUMMARIES=$("$PY" -c "
import json, os, urllib.request, urllib.parse
project = urllib.parse.quote(os.path.basename(os.getcwd()))
try:
    r = urllib.request.urlopen(f'http://127.0.0.1:$PORT/api/context/recent?project={project}&limit=5', timeout=4)
    text = ' '.join(c.get('text','') for c in json.loads(r.read().decode()).get('content',[]))
    print(text.count('failed - no summary available'))
except Exception:
    print('?')
" 2>/dev/null)
    if [ "$FAILED_SUMMARIES" = "0" ]; then
        ok "No failed session summaries in recent history — generation pipeline healthy"
    elif [ "$FAILED_SUMMARIES" = "?" ]; then
        warn "Could not check session summary status"
    else
        warn "$FAILED_SUMMARIES of the last 5 session summaries are 'failed - no summary available' — generator may be broken (check ~/.claude-mem/logs/ for SDK_SPAWN errors)"
    fi
fi
if [ -f .claude/settings.local.json ] && grep -q 'api/context/recent\|api/observations' .claude/settings.local.json; then
    ok "SessionStart claude-mem hook present in .claude/settings.local.json"
else
    warn "No SessionStart claude-mem hook in .claude/settings.local.json (Phase 7f)"
fi

# ── 5. Global hooks — full-command live fire tests ───────────────────────────
echo ""
echo "-- Global hooks (~/.claude/settings.json) --"
if [ -n "$PY" ] && [ -f ~/.claude/settings.json ]; then
    N_HOOKS=$("$PY" -c "
import json, os
d = json.load(open(os.path.expanduser('~/.claude/settings.json')))
print(len(d.get('hooks', {}).get('UserPromptSubmit', [])))
" 2>/dev/null)
    [ "$N_HOOKS" = "2" ] && ok "UserPromptSubmit has 2 hook groups (memory trigger + /compact)" \
        || warn "UserPromptSubmit has $N_HOOKS hook groups, expected 2 (Phases 4 and 9)"

    # Fire the actual saved commands — the only test that catches quoting/interpreter breaks
    idx=0
    for label in "memory-trigger" "compact-interceptor"; do
        CMD=$("$PY" -c "
import json, os
d = json.load(open(os.path.expanduser('~/.claude/settings.json')))
groups = d.get('hooks', {}).get('UserPromptSubmit', [])
print(groups[$idx]['hooks'][0]['command'] if len(groups) > $idx else '')
" 2>/dev/null)
        if [ -z "$CMD" ]; then
            fail "$label hook: not found in settings.json"
        else
            case "$label" in
                memory-trigger)  TRIGGER='{"message": "please remember the doctor test"}' ;;
                *)               TRIGGER='{"message": "/compact"}' ;;
            esac
            OUT=$(echo "$TRIGGER" | bash -c "$CMD" 2>/dev/null)
            NEG=$(echo '{"message": "unrelated"}' | bash -c "$CMD" 2>/dev/null)
            if echo "$OUT" | grep -q 'hookSpecificOutput' && [ -z "$NEG" ]; then
                ok "$label hook fires on trigger, silent otherwise (live-fire test)"
            else
                fail "$label hook broken — trigger output: $(printf '%s' "$OUT" | head -c 40)..., negative: $(printf '%s' "$NEG" | head -c 20)"
            fi
        fi
        idx=$((idx+1))
    done
else
    fail "Cannot test global hooks (no interpreter or no ~/.claude/settings.json)"
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
date +%s > "$HOME/.claude/memory-doctor.last" 2>/dev/null   # tune-up cadence stamp
echo ""
if [ "$FAILS" -eq 0 ] && [ "$WARNS" -eq 0 ]; then
    echo "== VERDICT: all systems delivering =="
elif [ "$FAILS" -eq 0 ]; then
    echo "== VERDICT: functional with $WARNS warning(s) =="
else
    echo "== VERDICT: $FAILS system failure(s), $WARNS warning(s) — memory is degraded =="
fi
exit "$FAILS"
