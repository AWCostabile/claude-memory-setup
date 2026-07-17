#!/bin/bash
# recap-nudge.sh — SessionStart half of the session-gap recap: compute the gap, stash
# the facts for the first-prompt classifier (scripts/recap-classify.sh).
#
# Finds when the last session in this project ended — claude-mem's newest observation
# first, newest transcript file as fallback — and, when the gap exceeds RECAP_HOURS
# (default 4), writes the facts to a per-session state file. It prints NOTHING itself:
# the recap decision belongs to recap-classify.sh, which sees the user's actual first
# prompt and can therefore inject an imperative directive only when a recap would help.
# Weak models are bad at judging but fine at obeying — so the judgment lives in the
# classifier's regexes, not in the model.
#
# Test knob: RECAP_FAKE_GAP_H=<hours> simulates a gap (source labeled 'simulated').

RECAP_HOURS="${RECAP_HOURS:-4}"
HOOK_INPUT=$(cat)      # heredoc below replaces python's stdin — pass hook JSON via env
export HOOK_INPUT

PY=""
for c in python3 python py; do
    if "$c" -c "pass" >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -z "$PY" ] && exit 0

"$PY" - "$RECAP_HOURS" <<'PYEOF' 2>/dev/null
import glob
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

threshold_h = float(sys.argv[1])
project = os.path.basename(os.getcwd())
now = time.time()
last = None          # epoch seconds of last session activity
source = None

# Session id from the hook's input JSON (via HOOK_INPUT env; the heredoc owns stdin).
try:
    session_id = json.loads(os.environ.get('HOOK_INPUT') or '{}').get('session_id', '')
except Exception:
    session_id = ''
session_id = re.sub(r'[^A-Za-z0-9-]', '', session_id) or 'unknown'

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

# Test knob: RECAP_FAKE_GAP_H=<hours> simulates a gap so the feature can be verified
# end-to-end without waiting for a real one (source is labeled 'simulated').
fake = os.environ.get('RECAP_FAKE_GAP_H')
if fake:
    last = now - float(fake) * 3600
    source = 'simulated'

if last is None:
    sys.exit(0)          # no prior session known — nothing to recap

gap_h = (now - last) / 3600
if gap_h < threshold_h:
    sys.exit(0)

when = time.strftime('%A %Y-%m-%d %H:%M', time.localtime(last))
gap_txt = f'{gap_h:.0f} hours' if gap_h < 72 else f'{gap_h / 24:.0f} days'
lean = ''
if time.localtime(now).tm_wday == 0 and gap_h >= 12:
    lean = ' This is the first session after the weekend.'
elif gap_h >= 48:
    lean = ' The gap is long.'

state = {'when': when, 'gap': gap_txt, 'source': source, 'lean': lean}
tmp = os.environ.get('TMPDIR') or os.environ.get('TEMP') or '/tmp'
with open(os.path.join(tmp, f'.recap-gap-{session_id}'), 'w', encoding='utf-8') as f:
    json.dump(state, f)
PYEOF
exit 0
