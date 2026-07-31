#!/bin/bash
# lifecycle-test.sh — end-to-end test of hooks/session-journal.sh against REAL
# captured hook payloads (tests/fixtures/, captured live on Claude Code 2.1.150,
# 2026-07-31). Synthetic payloads lie — this project learned that twice — so when
# the CLI's event shapes change, regenerate fixtures with tests/event-shape-probe/
# rather than hand-editing these.
#
# Exercises: dead-session lifecycle (header -> breadcrumbs -> turn stamp -> dirty
# tail), orchestration spawn + subagent harvest, clean close, dirty-session
# recovery injection, and manifest re-injection on compact. Self-contained: runs
# in a temp journal root, needs no worker (the harvest POST is fire-and-forget).
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/.." && pwd)
HOOK="$REPO_ROOT/hooks/session-journal.sh"
CLAUDE_JOURNAL_ROOT=$(mktemp -d)
export CLAUDE_JOURNAL_ROOT
trap 'rm -rf "$CLAUDE_JOURNAL_ROOT"' EXIT

# Fixtures are rendered fresh for this machine from the committed templates —
# nothing machine-specific is committed; see tests/README.md.
bash "$HERE/make-fixtures.sh" >/dev/null || { echo "FAIL fixture render"; exit 1; }
FIX="$REPO_ROOT/.claude/test-fixtures"

T1SID="fixture-session-t1"   # rendered sid: subagent-probe-derived templates
T2SID="fixture-session-t2"   # rendered sid: stop/session-end-derived templates
DEADSID="dead-session-0000"
ORCHSID="orch-session-0000"

# Machine-specific values come from .claude/test-machine.env via machine-env.sh —
# the single place to fix detection on a new machine (see tests/README.md).
. "$HERE/machine-env.sh" || exit 1
PY="$TEST_PY"

FIXVER=$(FIXPROV="$HERE/fixtures/provenance.json" "$PY" -c "import json,os; print(json.load(open(os.environ['FIXPROV']))['cli_version'])" 2>/dev/null)
if [ -n "$FIXVER" ] && [ "$TEST_CLI_VERSION" != "unknown" ] && [ "$FIXVER" != "$TEST_CLI_VERSION" ]; then
    echo "[warn] fixtures captured on CLI $FIXVER, this machine runs $TEST_CLI_VERSION — shapes may have drifted; re-capture with tests/event-shape-probe/ if failures look shape-related"
fi

# A pid that is guaranteed dead on THIS machine right now: spawn-and-reap.
DEADPID=$("$PY" -c "import subprocess,sys; p=subprocess.Popen([sys.executable,'-c','pass']); p.wait(); print(p.pid)")

FAILS=0
assert_contains() { # name pattern data
    if printf '%s' "$3" | grep -q "$2"; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi
}
assert_true() { # name condition-command...
    local name="$1"; shift
    if "$@"; then echo "PASS $name"; else echo "FAIL $name"; FAILS=$((FAILS+1)); fi
}

# 1. dead session: header (dead pid) -> tools -> turn stamp -> tools = dirty tail
sed "s/$T1SID/$DEADSID/g" "$FIX/session-start.startup.json" \
    | CLAUDE_PID=$DEADPID CLAUDE_CODE_SESSION_ID=$DEADSID bash "$HOOK" session-start >/dev/null
sed "s/$T1SID/$DEADSID/g" "$FIX/pre-tool-use.agent-spawn-and-subagent-read.jsonl" \
    | while read -r l; do printf '%s' "$l" | bash "$HOOK" post-tool; done
sed "s/$T2SID/$DEADSID/g" "$FIX/stop.json" | bash "$HOOK" stop
tail -1 "$FIX/pre-tool-use.agent-spawn-and-subagent-read.jsonl" \
    | sed "s/$T1SID/$DEADSID/g" | bash "$HOOK" post-tool

# 2. orchestration session: spawn registered, report harvested, then stamped
#    (stamped so it classifies suspended — only the DEAD session should be dirty)
head -1 "$FIX/pre-tool-use.agent-spawn-and-subagent-read.jsonl" \
    | sed "s/$T1SID/$ORCHSID/g" | bash "$HOOK" pre-agent
sed "s/$T1SID/$ORCHSID/g" "$FIX/subagent-stop.json" | bash "$HOOK" subagent-stop
sed "s/$T2SID/$ORCHSID/g" "$FIX/stop.json" | bash "$HOOK" stop

# 3. clean close for the t2-style session
bash "$HOOK" session-end < "$FIX/session-end.json"

# 4. a new session starts -> dirty-session recovery injection
OUT=$(sed "s/$T1SID/lifecycle-scanner/g" "$FIX/session-start.startup.json" | bash "$HOOK" session-start)
assert_contains "dirty session detected"       "UNFINISHED SESSION DETECTED" "$OUT"
assert_contains "resume hint names dead sid"   "claude --resume $DEADSID"    "$OUT"
assert_contains "last-turn summary present"    "FIRST-TURN"                  "$OUT"
assert_contains "assess-first directive"       "ASSESS FIRST"                "$OUT"

# 5. compact re-entry of the orchestration session -> manifest re-injection
OUT2=$(sed "s/$T1SID/$ORCHSID/g; s/\"source\": *\"startup\"/\"source\":\"compact\"/; s/\"source\":\"startup\"/\"source\":\"compact\"/" \
    "$FIX/session-start.startup.json" | bash "$HOOK" session-start)
assert_contains "manifest survives compact"    "ORCHESTRATION MANIFEST"      "$OUT2"
assert_contains "harvested report in manifest" "PROBE-LINE-ALPHA"            "$OUT2"

# 6. hygiene
assert_true "salvage marker written" grep -q salvage-offered "$CLAUDE_JOURNAL_ROOT"/*/"$DEADSID".jsonl
assert_true "no hook errors logged"  test ! -s "$CLAUDE_JOURNAL_ROOT/.errors.log"

echo
if [ "$FAILS" -eq 0 ]; then echo "== lifecycle-test: all passed =="; else echo "== lifecycle-test: $FAILS FAILURE(S) =="; fi
exit "$FAILS"
