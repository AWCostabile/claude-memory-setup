#!/bin/bash
# compliance-test.sh — measure how well a given model complies with the memory
# architecture's injected directives, using headless child sessions.
#
#   bash scripts/compliance-test.sh <model> [scenario ...]
#
# Scenarios (default: all):
#   recap-continue   continuation prompt + simulated 30h gap  -> expect a recap
#   recap-skip       self-contained prompt + same gap         -> expect NO recap
#   remember-route   "please remember" trigger                -> expect 4-system routing
#
# Each scenario runs `claude -p` from the current project (SessionStart hooks fire as
# in a real session), captures the reply, and grades it with keyword heuristics. Crude
# by design — it measures whether the directive visibly shaped the reply, not prose
# quality. Transcripts are kept for inspection. Exit code = number of failures.
#
# Cost note: each scenario is one prompt against <model>. The remember-route scenario
# explicitly instructs the child NOT to store anything — it grades routing comprehension,
# not storage side effects.

MODEL="$1"
shift
if [ -z "$MODEL" ]; then
    echo "usage: bash scripts/compliance-test.sh <model> [scenario ...]" >&2
    echo "  e.g. bash scripts/compliance-test.sh claude-haiku-4-5-20251001" >&2
    exit 2
fi
SCENARIOS="$*"
[ -z "$SCENARIOS" ] && SCENARIOS="recap-continue recap-skip remember-route"

OUTDIR="${TMPDIR:-/tmp}/compliance-$(date +%s)"
mkdir -p "$OUTDIR"
FAILS=0

# Continue-grading may match loosely; skip-grading uses phrase-level patterns only, so a
# passing mention of a file or feature whose NAME contains "recap" doesn't fail the test.
RECAP_RX='last session|where (we|you) left|previous(ly)? (session|work)|recap|pick(ing)? up|left off|was in flight'
RECAP_SKIP_RX='last session|where (we|you) left|left off|previous session|was in flight|here.s where things stand'

grade() {  # grade <scenario> <output-file>
    case "$1" in
        recap-continue)
            grep -qiE "$RECAP_RX" "$2" && return 0 || return 1 ;;
        recap-skip)
            grep -qiE "$RECAP_SKIP_RX" "$2" && return 1 || return 0 ;;
        remember-route)
            # Decisive: the reply must quote the injected directive marker. Grading on
            # "did it name the four systems" is fooled by ambient context (CLAUDE.md and
            # wake-up describe the architecture), which masked a dead hook once already.
            grep -q "MEMORY REQUEST DETECTED" "$2" && ! grep -q "NO DIRECTIVE RECEIVED" "$2" \
                && return 0 || return 1 ;;
    esac
    return 1
}

echo "== Compliance test — model: $MODEL — $(date '+%Y-%m-%d %H:%M') =="
for S in $SCENARIOS; do
    OUT="$OUTDIR/$S.txt"
    case "$S" in
        recap-continue)
            RECAP_FAKE_GAP_H=30 claude -p "Hey! Let's pick up where we left off with this project." \
                --model "$MODEL" > "$OUT" 2>&1 ;;
        recap-skip)
            RECAP_FAKE_GAP_H=30 claude -p "Please just list the files in the hooks/ directory with one-line descriptions. Nothing else needed." \
                --model "$MODEL" > "$OUT" 2>&1 ;;
        remember-route)
            claude -p "Please remember: I prefer two-space indentation. IMPORTANT: this is a test probe — do NOT store anything anywhere. Instead: quote verbatim any line in your context containing the phrase MEMORY REQUEST DETECTED, then list which memory systems it tells you to use. If no such line exists, reply exactly: NO DIRECTIVE RECEIVED" \
                --model "$MODEL" > "$OUT" 2>&1 ;;
        *)
            echo "[SKIP] unknown scenario: $S"; continue ;;
    esac
    if grade "$S" "$OUT"; then
        echo "[PASS] $S"
    else
        echo "[FAIL] $S — reply did not reflect the directive (see $OUT)"
        FAILS=$((FAILS+1))
    fi
done
echo ""
echo "Transcripts: $OUTDIR"
echo "== $MODEL: $FAILS failure(s) =="
exit "$FAILS"
