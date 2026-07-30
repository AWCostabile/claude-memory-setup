"""Summarize captured hook payloads: keys, agent attribution, key fields per event."""
import json, glob, os

base = os.path.dirname(os.path.abspath(__file__))
for f in sorted(glob.glob(os.path.join(base, "captures", "*.jsonl"))):
    name = os.path.basename(f)
    lines = [l for l in open(f, encoding="utf-8", errors="replace") if l.strip()]
    print(f"== {name}: {len(lines)} events ==")
    for i, l in enumerate(lines):
        try:
            d = json.loads(l)
        except Exception as e:
            print(f"  [{i}] PARSE-ERR {e} :: {l[:140]}")
            continue
        keys = sorted(d.keys())
        tool = d.get("tool_name", "")
        extra = ""
        for k in ("agent_id", "agent_type", "source", "reason", "stop_reason", "effort", "permission_mode"):
            if k in d:
                extra += f" {k}={d[k]!r}"
        print(f"  [{i}] keys={keys}")
        print(f"       tool={tool}{extra}")
        tp = d.get("transcript_path")
        if tp:
            print(f"       transcript_path={tp}")
        lam = d.get("last_assistant_message")
        if lam is not None:
            print(f"       last_assistant_message[:120]={str(lam)[:120]!r}")
        sid = d.get("session_id")
        if sid:
            print(f"       session_id={sid}")
