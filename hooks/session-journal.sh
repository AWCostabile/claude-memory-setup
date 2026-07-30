#!/bin/bash
# session-journal.sh — token-free write-ahead journal for Claude Code sessions.
# CONTINUITY-LAYER:journal-v1
#
# The four-system memory architecture writes its valuable artifacts at session
# boundaries (Stop summarize, PreCompact save). A session killed mid-turn — usage
# limit, crash, power loss — never reaches a boundary, and the kill-test proved
# claude-mem's queued events are unrecoverable in that case (pending_messages is
# transient; distillation is turn-gated). This journal is the shell-level record
# that survives, because it spends zero model tokens: at the moment of usage-limit
# death, any model-mediated save is impossible by definition.
#
# Wired as user-level hooks (all projects benefit). Subcommands map to hook events:
#   session-start   SessionStart (sync)  — init journal header, reclaim on resume,
#                                          re-inject manifest on compact/resume,
#                                          scan sibling journals for dirty sessions
#   post-tool       PostToolUse * (async) — append one compact breadcrumb per call
#   pre-agent       PreToolUse Agent|Task (async) — register subagent spawn in manifest
#   stop            Stop (async)         — turn-boundary stamp (turn completed =
#                                          claude-mem summarized it = nothing lost)
#   subagent-stop   SubagentStop (async) — harvest subagent final report to journal +
#                                          manifest + claude-mem worker (attributed)
#   session-end     SessionEnd           — clean-close marker
#
# Journal state model (read by the recovery scan):
#   closed    : session-end present at tail            -> archivable
#   suspended : tail is a turn-end stamp               -> resumable, nothing lost
#   live      : recorded PID alive with matching name+start-time (or PID unknown
#               while other claude processes are running) -> untouched
#   dirty     : tail is post-stamp breadcrumbs, owner gone -> salvage candidate
#
# Design constraints honored here:
#   - Interpreters resolved FUNCTIONALLY (python3 -> python -> py, real execution
#     probe); Windows Store stubs exist on PATH but fail. Probe result cached.
#   - Every failure path is silent-but-logged (.errors.log); a journal bug must
#     never break a session start or a tool call.
#   - The hot path (post-tool) is one cached-interpreter spawn, async, no network.
#   - Recovery injection is assess-first (mirrors recap-classify): facts + a
#     directive to judge relevance against the first prompt, never an auto-recap.

set -u

JROOT="${CLAUDE_JOURNAL_ROOT:-$HOME/.claude/session-journals}"
PYCACHE="$JROOT/.pycmd"
SUB="${1:-}"

resolve_py() {
    # Functional probe: a real execution, never a PATH lookup alone.
    for c in python3 python py; do
        if "$c" -c "pass" >/dev/null 2>&1; then echo "$c"; return 0; fi
    done
    return 1
}

mkdir -p "$JROOT" 2>/dev/null || exit 0

PY=""
if [ -f "$PYCACHE" ]; then
    PY=$(cat "$PYCACHE" 2>/dev/null)
    "$PY" -c "pass" >/dev/null 2>&1 || PY=""
fi
if [ -z "$PY" ]; then
    PY=$(resolve_py) || { echo "$(date '+%F %T') no-python sub=$SUB" >> "$JROOT/.errors.log"; exit 0; }
    printf '%s' "$PY" > "$PYCACHE" 2>/dev/null
fi

PYSRC=$(cat <<'PYEOF'
import json, os, re, subprocess, sys, time

SUB = sys.argv[1] if len(sys.argv) > 1 else ""
JROOT = os.environ.get("CLAUDE_JOURNAL_ROOT") or os.path.join(os.path.expanduser("~"), ".claude", "session-journals")
MAX_JOURNAL_BYTES = 2 * 1024 * 1024
INJECT_CHAR_BUDGET = 4800  # ~1200 tokens
STAMP_KEEP = 400
REPORT_KEEP = 2000

def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")

def log_err(msg):
    try:
        with open(os.path.join(JROOT, ".errors.log"), "a", encoding="utf-8") as f:
            f.write(f"{now_iso()} [{SUB}] {msg}\n")
    except Exception:
        pass

def read_payload():
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}

def slug_for(cwd):
    import hashlib
    base = re.sub(r"[^A-Za-z0-9_-]+", "-", os.path.basename(cwd.rstrip("/\\")) or "root")
    h = hashlib.sha1(cwd.replace("\\", "/").lower().encode()).hexdigest()[:8]
    return f"{base}-{h}"

def paths(payload):
    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    sid = payload.get("session_id") or os.environ.get("CLAUDE_CODE_SESSION_ID") or "unknown-session"
    d = os.path.join(JROOT, slug_for(cwd))
    os.makedirs(d, exist_ok=True)
    return d, os.path.join(d, sid + ".jsonl"), os.path.join(d, sid + ".manifest.jsonl"), sid, cwd

def append(path, obj, cap=True):
    try:
        if cap and os.path.exists(path) and os.path.getsize(path) > MAX_JOURNAL_BYTES:
            obj = {"t": obj.get("t"), "ev": obj.get("ev"), "capped": True}
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except Exception as e:
        log_err(f"append {path}: {e}")

def brief_arg(tool, ti):
    if not isinstance(ti, dict):
        return str(ti)[:80]
    for k in ("file_path", "path", "pattern", "command", "description", "url", "query", "skill"):
        if k in ti and ti[k]:
            return str(ti[k])[:120]
    if "prompt" in ti:
        return str(ti["prompt"])[:120]
    return ",".join(sorted(ti.keys()))[:80]

def load_events(path):
    evs = []
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    evs.append(json.loads(line))
                except Exception:
                    evs.append({"ev": "unparseable"})
    except Exception:
        pass
    return evs

def tail_state(evs):
    # salvage-offered lines are bookkeeping, not session activity
    real = [e for e in evs if e.get("ev") not in ("salvage-offered",)]
    if not real:
        return "empty"
    last = real[-1].get("ev")
    if last == "session-end":
        return "closed"
    if last in ("turn-end", "session-start", "resumed"):
        return "suspended"
    return "dirty"

def pid_identity(pid):
    """Return (name, created) for a Windows/posix PID, or (None, None) if gone."""
    try:
        if os.name == "nt" or sys.platform in ("win32", "cygwin", "msys"):
            out = subprocess.run(
                ["powershell.exe", "-NoProfile", "-Command",
                 f"$p=Get-CimInstance Win32_Process -Filter 'ProcessId={int(pid)}' -ErrorAction SilentlyContinue; if($p){{$p.Name+'|'+$p.CreationDate}}"],
                capture_output=True, text=True, timeout=8).stdout.strip()
            if "|" in out:
                n, c = out.split("|", 1)
                return n.strip(), c.strip()
            return None, None
        else:
            os.kill(int(pid), 0)
            out = subprocess.run(["ps", "-p", str(int(pid)), "-o", "comm=,lstart="],
                                 capture_output=True, text=True, timeout=8).stdout.strip()
            if out:
                parts = out.split(None, 1)
                return parts[0], (parts[1] if len(parts) > 1 else "")
            return "unknown", ""
    except Exception:
        return None, None

def other_claude_running():
    """Conservative check when a journal has no recorded PID."""
    try:
        if os.name == "nt" or sys.platform in ("win32", "cygwin", "msys"):
            out = subprocess.run(
                ["powershell.exe", "-NoProfile", "-Command",
                 "(Get-CimInstance Win32_Process -Filter \"Name='claude.exe' or Name='node.exe'\" -ErrorAction SilentlyContinue | Measure-Object).Count"],
                capture_output=True, text=True, timeout=8).stdout.strip()
            return int(out or "0") > 1  # >1: something besides the CLI running this scan
        out = subprocess.run(["pgrep", "-c", "-f", "claude"], capture_output=True, text=True, timeout=8).stdout.strip()
        return int(out or "0") > 1
    except Exception:
        return True  # unknown -> assume live -> never false-flag

# ---------------------------------------------------------------- subcommands

def do_post_tool():
    p = read_payload()
    d, jf, mf, sid, cwd = paths(p)
    ev = {"t": now_iso(), "ev": "tool", "tool": p.get("tool_name", "?"),
          "arg": brief_arg(p.get("tool_name", ""), p.get("tool_input"))}
    if p.get("agent_id"):
        ev["agent"] = f"{p.get('agent_type','?')}/{p.get('agent_id')}"
    append(jf, ev)

def do_pre_agent():
    p = read_payload()
    if p.get("tool_name") not in ("Agent", "Task"):
        return
    d, jf, mf, sid, cwd = paths(p)
    ti = p.get("tool_input") or {}
    ev = {"t": now_iso(), "ev": "agent-spawn",
          "desc": str(ti.get("description", ""))[:120],
          "type": ti.get("subagent_type", "?"),
          "model": ti.get("model"),
          "prompt_head": str(ti.get("prompt", ""))[:200]}
    append(jf, ev)
    append(mf, ev, cap=False)

def do_stop():
    p = read_payload()
    d, jf, mf, sid, cwd = paths(p)
    append(jf, {"t": now_iso(), "ev": "turn-end",
                "last": str(p.get("last_assistant_message", ""))[:STAMP_KEEP]})

def do_subagent_stop():
    p = read_payload()
    d, jf, mf, sid, cwd = paths(p)
    report = str(p.get("last_assistant_message", ""))[:REPORT_KEEP]
    ev = {"t": now_iso(), "ev": "subagent-report",
          "type": p.get("agent_type", "?"), "id": p.get("agent_id", "?"),
          "report": report}
    append(jf, {**ev, "report": report[:300]})
    append(mf, ev, cap=False)
    # Attributed harvest to the claude-mem worker, in its native ingestion shape.
    # Fills a real gap: claude-mem registers no SubagentStop hook, so background
    # agents' final reports are otherwise never captured. Fire-and-forget.
    try:
        body = json.dumps({
            "contentSessionId": p.get("session_id"),
            "platformSource": "claude",
            "tool_name": "SubagentReport",
            "tool_input": {"agent_type": p.get("agent_type"), "agent_id": p.get("agent_id")},
            "tool_response": {"report": report},
            "cwd": cwd,
            "agentId": p.get("agent_id"),
            "agentType": p.get("agent_type"),
        })
        subprocess.run(["curl", "-s", "--max-time", "3",
                        "-X", "POST", "http://127.0.0.1:37777/api/sessions/observations",
                        "-H", "Content-Type: application/json", "-d", body],
                       capture_output=True, timeout=6)
    except Exception as e:
        log_err(f"worker-post: {e}")

def do_session_end():
    p = read_payload()
    d, jf, mf, sid, cwd = paths(p)
    append(jf, {"t": now_iso(), "ev": "session-end", "reason": p.get("reason", "?")})

def fmt_age(seconds):
    if seconds < 3600: return f"{int(seconds/60)}m"
    if seconds < 172800: return f"{seconds/3600:.1f}h"
    return f"{seconds/86400:.1f}d"

def do_session_start():
    p = read_payload()
    d, jf, mf, sid, cwd = paths(p)
    source = p.get("source", "startup")

    # CLAUDE_PID is only trustworthy for top-level sessions. A session spawned from
    # inside another claude session (claude -p children, test rigs, automations)
    # inherits the PARENT's CLAUDE_PID through the environment — recording that
    # would make the dead child's journal look owned by a live process forever.
    # CLAUDE_CODE_CHILD_SESSION=1 marks exactly that case; such journals take the
    # conservative unknown-owner path and surface via the doctor instead.
    pid = os.environ.get("CLAUDE_PID")
    inherited = os.environ.get("CLAUDE_CODE_CHILD_SESSION") == "1"
    if inherited:
        pid = None
    pname = pcreated = None
    if pid:
        pname, pcreated = pid_identity(pid)
    header = {"t": now_iso(), "ev": "resumed" if source == "resume" else "session-start",
              "source": source, "pid": pid, "pid_name": pname, "pid_created": pcreated,
              "pid_inherited": inherited or None,
              "cwd": cwd, "transcript": p.get("transcript_path")}
    append(jf, header)

    ctx_parts = []

    # -- own-manifest re-injection: the anti-"burned turns on state rediscovery" fix
    if source in ("compact", "resume") and os.path.exists(mf):
        mevs = load_events(mf)
        spawns = [e for e in mevs if e.get("ev") == "agent-spawn"]
        reports = [e for e in mevs if e.get("ev") == "subagent-report"]
        if spawns or reports:
            lines = [f"ORCHESTRATION MANIFEST (this session, surviving {source}):"]
            for s in spawns[-8:]:
                lines.append(f"  spawned: [{s.get('type')}] {s.get('desc')} (model={s.get('model') or 'inherit'})")
            for r in reports[-8:]:
                lines.append(f"  completed: [{r.get('type')}] report: {str(r.get('report',''))[:200]}")
            if len(spawns) > len(reports):
                lines.append(f"  NOTE: {len(spawns) - len(reports)} spawn(s) without a recorded report — possibly still running or lost.")
            ctx_parts.append("\n".join(lines))

    # -- sibling scan for dirty sessions (skip on resume; the resumed context speaks for itself)
    if source != "resume":
        try:
            cands = []
            for fn in sorted(os.listdir(d)):
                if not fn.endswith(".jsonl") or fn.endswith(".manifest.jsonl"):
                    continue
                if fn == sid + ".jsonl":
                    continue
                path = os.path.join(d, fn)
                evs = load_events(path)
                state = tail_state(evs)
                if state == "closed":
                    if time.time() - os.path.getmtime(path) > 7 * 86400:
                        for extra in (path, path.replace(".jsonl", ".manifest.jsonl")):
                            try: os.remove(extra)
                            except OSError: pass
                    continue
                if state != "dirty":
                    continue
                head = next((e for e in evs if e.get("ev") in ("session-start",)), {})
                hpid = head.get("pid")
                if hpid:
                    name, created = pid_identity(hpid)
                    if name and (head.get("pid_name") in (None, name)) and (head.get("pid_created") in (None, created)):
                        continue  # owner still alive -> live, untouched
                elif other_claude_running():
                    continue      # unknown owner + other claude processes -> assume live
                offered = sum(1 for e in evs if e.get("ev") == "salvage-offered")
                if offered >= 2:
                    continue      # twice is enough; the doctor surfaces the backlog
                cands.append((os.path.getmtime(path), path, evs))

            cands.sort(reverse=True)
            if cands:
                mtime, path, evs = cands[0]
                age = fmt_age(time.time() - mtime)
                dead_sid = os.path.basename(path)[:-6]
                stamps = [e for e in evs if e.get("ev") == "turn-end"]
                post = []
                for e in reversed(evs):
                    if e.get("ev") in ("turn-end", "session-start", "resumed"):
                        break
                    post.append(e)
                post.reverse()
                tools = [e for e in post if e.get("ev") == "tool"]
                reports = [e for e in post if e.get("ev") == "subagent-report"]
                spawns = [e for e in post if e.get("ev") == "agent-spawn"]
                lines = [f"UNFINISHED SESSION DETECTED in this project (died mid-turn, {age} ago, {len(tools)} tool calls unrecorded by memory):"]
                if stamps:
                    lines.append(f"  last completed turn said: {str(stamps[-1].get('last',''))[:300]}")
                for s in spawns[-4:]:
                    lines.append(f"  spawned subagent: [{s.get('type')}] {s.get('desc')}")
                for r in reports[-4:]:
                    lines.append(f"  subagent reported: [{r.get('type')}] {str(r.get('report',''))[:200]}")
                for e in tools[-10:]:
                    lines.append(f"  then: {e.get('tool')} {e.get('arg','')}")
                lines.append(f"  resumable via: claude --resume {dead_sid}")
                if len(cands) > 1:
                    lines.append(f"  (+{len(cands)-1} more dirty journal(s) — run the memory doctor for the backlog)")
                lines.append("ASSESS FIRST: if the user's first prompt continues that work, summarize the breadcrumbs and offer recovery (or the resume command). If unrelated, mention the unfinished session in one line and move on. Do not recap unprompted beyond that.")
                ctx_parts.append("\n".join(lines))
                append(path, {"t": now_iso(), "ev": "salvage-offered", "by": sid})
        except Exception as e:
            log_err(f"scan: {e}")

    if ctx_parts:
        ctx = "\n\n".join(ctx_parts)[:INJECT_CHAR_BUDGET]
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                                 "additionalContext": ctx}}))

try:
    {"post-tool": do_post_tool,
     "pre-agent": do_pre_agent,
     "stop": do_stop,
     "subagent-stop": do_subagent_stop,
     "session-end": do_session_end,
     "session-start": do_session_start}.get(SUB, lambda: None)()
except Exception as e:
    log_err(f"fatal: {e}")
sys.exit(0)
PYEOF
)

exec "$PY" -c "$PYSRC" "$SUB"
