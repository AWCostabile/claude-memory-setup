#!/bin/bash
# make-fixtures.sh — render tests/fixtures/templates/ into machine-local fixtures.
#
# Committed templates are capture-derived: structure and field names verbatim from
# real hook events, machine/session values replaced with {{PLACEHOLDERS}}. This
# script fills the placeholders with values for THIS machine and writes the result
# to .claude/test-fixtures/ (gitignored — .claude/ is machine-local by repo
# convention). Tests re-render on every run; nothing here is committed.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/machine-env.sh" || exit 1

OUT_DIR="$REPO_ROOT/.claude/test-fixtures"
mkdir -p "$OUT_DIR"

FIXTURE_OUT="$OUT_DIR" TEMPLATES="$HERE/fixtures/templates" "$TEST_PY" - <<'PYEOF'
import glob, os

out_dir = os.environ["FIXTURE_OUT"]
templates = os.environ["TEMPLATES"]
home = os.path.expanduser("~")

# Deterministic sids: files captured from the subagent-probe session render as t1,
# files from the stop/session-end session as t2. Tests sed these to their own ids.
SID_BY_FILE = {
    "session-start.startup.json": "fixture-session-t1",
    "pre-tool-use.agent-spawn-and-subagent-read.jsonl": "fixture-session-t1",
    "subagent-stop.json": "fixture-session-t1",
    "stop.json": "fixture-session-t2",
    "session-end.json": "fixture-session-t2",
}

for tpl in sorted(glob.glob(os.path.join(templates, "*.template"))):
    name = os.path.basename(tpl)[: -len(".template")]
    sid = SID_BY_FILE.get(name, "fixture-session-x")
    values = {
        "{{SESSION_ID}}": sid,
        "{{CWD}}": os.getcwd(),
        "{{TRANSCRIPT_PATH}}": os.path.join(home, ".claude", "projects", "fixture-project", sid + ".jsonl"),
        "{{AGENT_TRANSCRIPT_PATH}}": os.path.join(home, ".claude", "projects", "fixture-project", sid, "subagents", "agent-fixtureagent0001.jsonl"),
        "{{AGENT_ID}}": "fixtureagent0001",
        "{{TOOL_USE_ID}}": "toolu_fixture0001",
        "{{FILE_PATH}}": os.path.join(out_dir, "probe.txt"),
        "{{PATH}}": os.path.join(out_dir, "probe.txt"),
    }
    text = open(tpl, encoding="utf-8").read()
    for k, v in values.items():
        text = text.replace(k, v.replace("\\", "\\\\"))  # JSON-escape rendered paths
    with open(os.path.join(out_dir, name), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

leftover = [os.path.basename(p) for p in glob.glob(os.path.join(out_dir, "*"))
            if "{{" in open(p, encoding="utf-8").read()]
if leftover:
    raise SystemExit(f"unrendered placeholders remain in: {leftover}")
print(f"fixtures rendered to {out_dir}")
PYEOF
