#!/bin/bash
# make-rig.sh — generate a hook-payload capture rig into <target-dir>.
# The rig's settings file wires capture hooks for every event the continuity layer
# consumes; run claude -p sessions with `--settings <target>/rig-settings.json` and
# read the results from <target>/captures/. See README.md in this directory.
set -u

TARGET="${1:?usage: make-rig.sh <target-dir>}"
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../machine-env.sh" || exit 1

mkdir -p "$TARGET/captures"
ABS=$(cd "$TARGET" && pwd)

RIG_ABS="$ABS" "$TEST_PY" - <<'PYEOF'
import json, os, re

abs_dir = os.environ["RIG_ABS"]
# Git Bash /c/... -> C:/... so the generated JSON works from any shell
m = re.match(r"^/([a-z])/(.*)$", abs_dir)
if m:
    abs_dir = f"{m.group(1).upper()}:/{m.group(2)}"
cap = f"{abs_dir}/captures"

def capture(event):
    f = f"{cap}/{event}.jsonl"
    return {"type": "command", "command": f"bash -c 'cat >> \"{f}\"; echo >> \"{f}\"'"}

hooks = {
    "PreToolUse":       [{"matcher": "*", "hooks": [capture("PreToolUse")]}],
    "PostToolUse":      [{"matcher": "*", "hooks": [capture("PostToolUse")]}],
    "SubagentStop":     [{"hooks": [capture("SubagentStop")]}],
    "Stop":             [{"hooks": [capture("Stop")]}],
    "SessionStart":     [{"hooks": [capture("SessionStart"),
                          {"type": "command",
                           "command": f"bash \"{abs_dir}/pidprobe.sh\" >> \"{cap}/pidprobe.txt\" 2>&1"}]}],
    "SessionEnd":       [{"hooks": [capture("SessionEnd")]}],
    "UserPromptSubmit": [{"hooks": [capture("UserPromptSubmit")]}],
}
with open(os.path.join(os.environ["RIG_ABS"], "rig-settings.json"), "w", encoding="utf-8") as f:
    json.dump({"hooks": hooks}, f, indent=2)
    f.write("\n")
print(f"rig-settings.json written (captures -> {cap})")
PYEOF

cat > "$TARGET/pidprobe.sh" <<'EOF'
#!/bin/bash
# pidprobe.sh — what CLAUDE_* env vars do hooks see, and is CLAUDE_PID fresh?
echo "=== pidprobe run at $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "bash pid=$$ ppid=$PPID"
echo "-- CLAUDE env vars visible to hook --"
env | grep -i '^CLAUDE' | sort
echo "=== end pidprobe ==="
EOF

printf 'PROBE-LINE-ALPHA\nsecond line for padding\n' > "$TARGET/probe.txt"
cp "$HERE/inspect.py" "$TARGET/inspect.py"

echo "rig ready in: $TARGET"
echo "next: cd \"$TARGET\" && pipe a prompt via stdin into: claude -p --settings ./rig-settings.json --model sonnet --allowedTools \"Task,Agent,Read\""
