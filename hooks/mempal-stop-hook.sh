#!/bin/bash
# MemPalace Stop Hook — patched: silent baseline save to claude-mem
# MEMPALACE-PATCH:stop-suppress-v1
# Fires after EVERY Claude response. Sentinel limits claude-mem write to once per session.
# The mempalace hook run is intentionally skipped — its UI output cannot be suppressed.
# Baseline auto-save ensures no session disappears silently even without an explicit diary write.

INPUT=$(cat)

# ── Extract session ID ───────────────────────────────────────────────────────
SESSION_ID=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('session_id', 'unknown'))
except:
    print('unknown')
" 2>/dev/null)

SENTINEL="/tmp/.claudemem-session-${SESSION_ID}"

# ── Baseline claude-mem write (once per session) ─────────────────────────────
if [ "$SESSION_ID" != "unknown" ] && [ ! -f "$SENTINEL" ]; then
    touch "$SENTINEL"
    PROJECT=$(basename "$PWD")
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    PROJECT="$PROJECT" TIMESTAMP="$TIMESTAMP" python3 -c "
import urllib.request, json, os
project = os.environ['PROJECT']
timestamp = os.environ['TIMESTAMP']
try:
    payload = json.dumps({
        'project': project,
        'type': 'change',
        'title': f'Session active {timestamp}',
        'text': (
            f'Claude Code session was active in project [{project}] at {timestamp}. '
            f'Auto-captured baseline — richer diary entry should follow from mempalace_diary_write. '
            f'If absent, Claude did not explicitly save this session.'
        )
    }).encode()
    req = urllib.request.Request(
        'http://127.0.0.1:37777/api/memory/save',
        data=payload,
        headers={'Content-Type': 'application/json'}
    )
    urllib.request.urlopen(req, timeout=2)
except:
    pass
" 2>/dev/null &
fi

# ── Output nothing — suppresses all UI noise ─────────────────────────────────
# suppressOutput field is insufficient for Stop hooks; emitting no output is the only fix.
