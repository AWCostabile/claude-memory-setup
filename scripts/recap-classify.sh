#!/bin/bash
# recap-classify.sh — UserPromptSubmit half of the session-gap recap.
#
# Consumes the state file stashed by recap-nudge.sh (so it acts on the FIRST prompt
# only), classifies that prompt with regexes, and injects the matching directive:
#
#   continuation/investigatory prompt  -> imperative RECAP REQUIRED directive
#   self-contained/direct prompt       -> nothing
#   ambiguous                          -> assess-first directive (model's judgment)
#
# Classifying here instead of asking the model to assess makes the behavior reliable
# on small models: regexes decide, the model executes. Silent whenever there is no
# pending gap state, so it costs nothing on later prompts or gapless sessions.

HOOK_INPUT=$(cat)      # heredoc below replaces python's stdin — pass hook JSON via env
export HOOK_INPUT

PY=""
for c in python3 python py; do
    if "$c" -c "pass" >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -z "$PY" ] && exit 0

"$PY" - <<'PYEOF' 2>/dev/null
import json
import os
import re
import sys

try:
    data = json.loads(os.environ.get('HOOK_INPUT') or '{}')
except Exception:
    sys.exit(0)

prompt = data.get('prompt', '') or (data.get('tool_input') or {}).get('message', '') or data.get('message', '') or ''
session_id = re.sub(r'[^A-Za-z0-9-]', '', data.get('session_id', '')) or 'unknown'

tmp = os.environ.get('TMPDIR') or os.environ.get('TEMP') or '/tmp'
path = os.path.join(tmp, f'.recap-gap-{session_id}')
if not os.path.exists(path):
    sys.exit(0)
try:
    state = json.load(open(path, encoding='utf-8'))
finally:
    try:
        os.remove(path)      # first prompt consumes the state — fire at most once
    except OSError:
        pass

if not prompt:
    sys.exit(0)

CONT_RX = re.compile(
    r"pick(ing)?\s+up|left\s+off|where\s+were\s+we|what\s+(were|was)\s+(we|i)\s|"
    r"continu(e|ing)|resum(e|ing)|get\s+back\s+to|catch\s+(me\s+)?up|"
    r"trying\s+to\s+(figure|work)\s+out|figure\s+out\s+why|recap|"
    r"where\s+(are|do|did)\s+we|status\s+of", re.IGNORECASE)
SKIP_RX = re.compile(
    r"^\s*/|\b(just|only|simply)\b|\bexecute\b|\brun\s+(the|this|it)\b|"
    r"^\s*(please\s+)?(list|show|print|cat|open|read)\b|\bnothing\s+else\b",
    re.IGNORECASE)

facts = (f"The last session in this project ended around {state['when']} "
         f"({state['gap']} ago, per {state['source']}).{state['lean']}")

if CONT_RX.search(prompt):
    msg = (
        'RECAP REQUIRED. ' + facts + ' The user is resuming or investigating prior '
        'work, so before addressing their request you MUST: '
        '1. Review the session context injected at session start (claude-mem recent '
        'observations, MemPalace wake-up). '
        '2. Open your reply with a short recap: what was in flight, what was '
        'completed, and the likely next step. '
        '3. Ask the user to confirm the recap before relying on stale details. '
        'Do not skip the recap.')
elif SKIP_RX.search(prompt):
    sys.exit(0)
else:
    msg = (
        'SESSION GAP: ' + facts + ' Assess whether a recap would help before '
        'answering: RECAP when the message is investigatory or resumes prior work; '
        'SKIP or compress to one line when it is self-contained or unrelated to '
        'previous work. If recapping, pull recent claude-mem observations and the '
        'MemPalace diary, state what was in flight and the likely next step, and '
        'verify with the user before relying on stale details.')

print(json.dumps({'hookSpecificOutput': {
    'hookEventName': 'UserPromptSubmit', 'additionalContext': msg}}))
PYEOF
exit 0
