#!/bin/bash
# retention-test.sh — retention rules of hooks/session-journal.sh, tested against
# fabricated journals with faked mtimes. Self-contained: temp journal root, no
# worker, no fixtures. The rules under test (see hooks/session-journal.sh):
#   closed  : delete after CLOSED_KEEP_D (7d)
#   suspended: delete after SUSPENDED_KEEP_D (30d) OR as soon as transcript is gone
#   dirty   : move to attic/ after DIRTY_ATTIC_D (30d); attic pruned after ATTIC_KEEP_D (90d)
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/../hooks/session-journal.sh"
CLAUDE_JOURNAL_ROOT=$(mktemp -d)
export CLAUDE_JOURNAL_ROOT
trap 'rm -rf "$CLAUDE_JOURNAL_ROOT"' EXIT

# Machine-specific values come from .claude/test-machine.env via machine-env.sh —
# the single place to fix detection on a new machine (see tests/README.md).
. "$HERE/machine-env.sh" || exit 1
PY="$TEST_PY"

"$PY" - <<'PYEOF'
import hashlib, json, os, re, time
root = os.environ["CLAUDE_JOURNAL_ROOT"]
cwd = "C:\\rtestproj"   # literal string; slugged identically at fabrication and scan time
base = re.sub(r"[^A-Za-z0-9_-]+", "-", os.path.basename(cwd.rstrip("/\\")) or "root")
slug = f"{base}-{hashlib.sha1(cwd.replace(chr(92), '/').lower().encode()).hexdigest()[:8]}"
d = os.path.join(root, slug)
os.makedirs(os.path.join(d, "attic"), exist_ok=True)
day, now = 86400, time.time()

def mk(name, events, age_days, manifest=False):
    p = os.path.join(d, name)
    with open(p, "w", encoding="utf-8") as f:
        for e in events:
            f.write(json.dumps(e) + "\n")
    os.utime(p, (now - age_days * day, now - age_days * day))
    if manifest:
        m = p.replace(".jsonl", ".manifest.jsonl")
        open(m, "w").write(json.dumps({"ev": "agent-spawn", "desc": "x", "type": "mechanic"}) + "\n")
        os.utime(m, (now - age_days * day, now - age_days * day))

ss = lambda tr=None, pid=None: {"ev": "session-start", "source": "startup", "pid": pid,
                                "pid_name": None, "pid_created": None, "cwd": cwd, "transcript": tr}
EXISTING = os.path.join(d, "existing-transcript.txt")
open(EXISTING, "w").write("x")

mk("closed-old.jsonl",   [ss(), {"ev": "turn-end", "last": "a"}, {"ev": "session-end"}], 8)
mk("closed-fresh.jsonl", [ss(), {"ev": "turn-end", "last": "a"}, {"ev": "session-end"}], 0.1)
mk("susp-old.jsonl",     [ss(EXISTING), {"ev": "turn-end", "last": "b"}], 31)
mk("susp-trgone.jsonl",  [ss("C:\\nonexistent-transcript.jsonl"), {"ev": "turn-end", "last": "c"}], 1)
mk("susp-fresh.jsonl",   [ss(EXISTING), {"ev": "turn-end", "last": "d"}], 1)
mk("dirty-old.jsonl",    [ss(pid="999999983"), {"ev": "turn-end", "last": "e"}, {"ev": "tool", "tool": "Read", "arg": "x"}], 31, manifest=True)
mk("dirty-fresh.jsonl",  [ss(pid="999999983"), {"ev": "turn-end", "last": "f"}, {"ev": "tool", "tool": "Edit", "arg": "y"}], 0.2)
ancient = os.path.join(d, "attic", "ancient.jsonl")
open(ancient, "w").write("{}\n")
os.utime(ancient, (now - 95 * day, now - 95 * day))
PYEOF

# one scan pass (a new session starting in the same project)
printf '{"session_id":"rtest-runner","cwd":"C:\\\\rtestproj","source":"startup"}' \
    | bash "$HOOK" session-start >/dev/null

"$PY" - <<'PYEOF'
import os, sys
root = os.environ["CLAUDE_JOURNAL_ROOT"]
slug = [s for s in os.listdir(root) if s.startswith("rtestproj")][0]
d = os.path.join(root, slug)
has = lambda n: os.path.exists(os.path.join(d, n))
attic = lambda n: os.path.exists(os.path.join(d, "attic", n))
checks = [
    ("closed-old deleted",           not has("closed-old.jsonl")),
    ("closed-fresh kept",            has("closed-fresh.jsonl")),
    ("suspended-old deleted",        not has("susp-old.jsonl")),
    ("suspended-transcript-gone deleted", not has("susp-trgone.jsonl")),
    ("suspended-fresh kept",         has("susp-fresh.jsonl")),
    ("dirty-old moved to attic",     not has("dirty-old.jsonl") and attic("dirty-old.jsonl")),
    ("dirty-old manifest to attic",  attic("dirty-old.manifest.jsonl")),
    ("dirty-fresh kept",             has("dirty-fresh.jsonl")),
    ("ancient attic entry pruned",   not attic("ancient.jsonl")),
]
fails = 0
for name, ok in checks:
    print(("PASS " if ok else "FAIL ") + name)
    fails += 0 if ok else 1
print()
print("== retention-test: all passed ==" if fails == 0 else f"== retention-test: {fails} FAILURE(S) ==")
sys.exit(fails)
PYEOF
