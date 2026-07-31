"""compare-keys.py — validate committed templates against freshly captured events.

Usage: python compare-keys.py <captures-dir>

For each captured event type, compares the union of recursive key-paths against the
corresponding template in tests/fixtures/templates/. Values are ignored on purpose:
templates are allowed to differ in values (placeholders), but a key that appears or
disappears in real events means the CLI's shapes drifted and the templates (and the
continuity hook) need review. Exit code = number of event types with drift.
"""
import glob, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATES = os.path.join(HERE, "..", "fixtures", "templates")

TEMPLATE_FOR = {
    "SessionStart": ["session-start.startup.json.template"],
    "PreToolUse": ["pre-tool-use.agent-spawn-and-subagent-read.jsonl.template"],
    "SubagentStop": ["subagent-stop.json.template"],
    "Stop": ["stop.json.template"],
    "SessionEnd": ["session-end.json.template"],
}

# Keys observed to be legitimately present-or-absent across real captures
# (e.g. Stop carries `effort` in some sessions and not others). Ignored in both
# directions so per-session variance doesn't read as CLI drift.
OPTIONAL_KEYS = {
    "Stop": {"effort", "effort.level"},
}

def key_paths(obj, prefix=""):
    paths = set()
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = f"{prefix}.{k}" if prefix else k
            paths.add(p)
            paths |= key_paths(v, p)
    return paths

def union_paths(path):
    paths = set()
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            paths |= key_paths(json.loads(line))
        except Exception:
            pass
    return paths

def main(cap_dir):
    drift = 0
    for event, tpl_names in TEMPLATE_FOR.items():
        cap = os.path.join(cap_dir, f"{event}.jsonl")
        if not os.path.exists(cap):
            print(f"[skip] {event}: no capture file")
            continue
        captured = union_paths(cap)
        templated = set()
        for t in tpl_names:
            templated |= union_paths(os.path.join(TEMPLATES, t))
        # tool_input/tool_response contents vary per tool — compare top-level presence only
        captured = {p for p in captured if not p.startswith(("tool_input.", "tool_response."))}
        templated = {p for p in templated if not p.startswith(("tool_input.", "tool_response."))}
        optional = OPTIONAL_KEYS.get(event, set())
        new = captured - templated - optional
        gone = templated - captured - optional
        if new or gone:
            drift += 1
            print(f"[DRIFT] {event}: new keys {sorted(new) or '-'} | vanished keys {sorted(gone) or '-'}")
        else:
            print(f"[ ok ] {event}: shapes match templates")
    return drift

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    sys.exit(main(sys.argv[1]))
