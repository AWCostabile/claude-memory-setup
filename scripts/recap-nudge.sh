#!/bin/bash
# recap-nudge.sh — SessionStart hook: hand Claude the session-gap facts so it can
# decide whether a recap would help.
#
# Finds when the last session in this project ended — claude-mem's newest observation
# first, newest transcript file as fallback — and, when the gap exceeds RECAP_HOURS
# (default 4), injects the gap plus an assessment directive. The directive tells Claude
# to recap only when the user's first message suggests it would help (investigatory or
# "pick up where we left off" prompts), and to skip or compress it when the prompt is
# self-contained (e.g. "execute plan.md"). Prints nothing below the threshold.
#
# Deliberately NOT a mid-conversation re-orient: scroll-back covers resumed
# conversations; recap there only when the user asks.

RECAP_HOURS="${RECAP_HOURS:-4}"

PY=""
for c in python3 python py; do
    if "$c" -c "pass" >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -z "$PY" ] && exit 0

"$PY" - "$RECAP_HOURS" <<'PYEOF' 2>/dev/null
import glob
import json
import os
import sys
import time
import urllib.parse
import urllib.request

threshold_h = float(sys.argv[1])
project = os.path.basename(os.getcwd())
now = time.time()
last = None          # epoch seconds of last session activity
source = None

# Primary: claude-mem's newest observation for this project
try:
    port = '37777'
    try:
        cfg = json.load(open(os.path.expanduser('~/.claude-mem/settings.json')))
        port = cfg.get('CLAUDE_MEM_WORKER_PORT', '37777')
    except Exception:
        pass
    q = urllib.parse.quote(project)
    r = urllib.request.urlopen(
        f'http://127.0.0.1:{port}/api/observations?project={q}&limit=1&orderBy=date_desc',
        timeout=3)
    items = json.loads(r.read().decode()).get('items', [])
    if items:
        epoch_ms = items[0].get('created_at_epoch')
        if epoch_ms:
            last = epoch_ms / 1000
            source = 'claude-mem'
except Exception:
    pass

# Fallback: newest transcript file in this project's ~/.claude/projects key dir,
# ignoring anything touched in the last 5 minutes (that's the current session).
if last is None:
    key = ''.join(ch if ch.isalnum() else '-' for ch in project.lower())
    candidates = []
    for d in glob.glob(os.path.expanduser('~/.claude/projects/*/')):
        if key in os.path.basename(d.rstrip('/\\')).lower().replace('_', '-'):
            candidates += glob.glob(os.path.join(d, '*.jsonl'))
    mtimes = [os.path.getmtime(f) for f in candidates]
    mtimes = [m for m in mtimes if now - m > 300]
    if mtimes:
        last = max(mtimes)
        source = 'transcripts'

if last is None:
    sys.exit(0)          # no prior session known — nothing to recap

gap_h = (now - last) / 3600
if gap_h < threshold_h:
    sys.exit(0)

when = time.strftime('%A %Y-%m-%d %H:%M', time.localtime(last))
gap_txt = f'{gap_h:.0f} hours' if gap_h < 72 else f'{gap_h / 24:.0f} days'
weekend = ''
if time.localtime(now).tm_wday == 0 and gap_h >= 12:
    weekend = ' This is the first session after the weekend — lean toward a brief recap.'
elif gap_h >= 48:
    weekend = ' The gap is long — lean toward a brief recap.'

print(
    f'SESSION GAP: the last session in this project ended around {when} '
    f'({gap_txt} ago, per {source}).{weekend} When the user\'s first message arrives, '
    f'assess whether a recap would help before answering: RECAP when the prompt is '
    f'investigatory ("trying to figure out why...") or resumes prior work ("let\'s pick '
    f'up..."); SKIP or compress to one line when the prompt is self-contained (e.g. '
    f'"execute plan.md") or unrelated to previous work. If recapping: pull recent '
    f'claude-mem observations and the MemPalace diary, state what was in flight and the '
    f'likely next step, and verify with the user before relying on stale details.'
)
PYEOF
exit 0
