# Event-shape probe

Capture rig for regenerating `tests/fixtures/` with **real** hook payloads on the
current machine and CLI version. Manual by design — it spawns real (billed) `claude -p`
sessions. Use it when a CLI update changes event shapes (the lifecycle suite warns when
`claude --version` no longer matches `fixtures/provenance.json`).

## Steps

1. Generate a rig directory (capture hooks + helper files):

   ```bash
   bash tests/event-shape-probe/make-rig.sh /tmp/proberig
   cd /tmp/proberig
   ```

2. Capture a session that spawns one subagent (produces SessionStart, PreToolUse ×2
   with and without `agent_id`, SubagentStop, Stop, SessionEnd):

   ```bash
   printf "Spawn exactly one subagent using your subagent tool (subagent_type: general-purpose) with this exact prompt: 'Use the Read tool to read the file probe.txt in the current working directory, then reply with exactly its first line.' After the subagent returns, reply with exactly: MAIN-DONE\n" \
     | claude -p --settings ./rig-settings.json --model sonnet --allowedTools "Task,Agent,Read"
   python inspect.py   # summarize captured shapes
   ```

3. Copy the relevant lines from `captures/*.jsonl` into `tests/fixtures/` (see the
   existing fixture filenames for which event goes where), update
   `tests/fixtures/provenance.json`, and run `bash tests/run-all.sh`.

## Gotchas (all learned the hard way)

- **Pipe prompts via stdin.** `--allowedTools` is variadic and will EAT a trailing
  prompt argument ("Input must be provided either through stdin or as a prompt
  argument"). PowerShell `Start-Process -ArgumentList` mangles spaced prompts too.
- **Test with real shapes only.** Synthetic payloads have twice passed tests while
  production silently failed in this project (a `prompt` vs `message` field; `Agent`
  vs `Task` tool name).
- `pidprobe.sh` output lands in `captures/pidprobe.txt` — check which `CLAUDE_*` env
  vars the CLI sets fresh per session before trusting any of them.
- Hook stdout ordering: SessionStart hooks are synchronous; tool-event hooks here are
  fire-and-forget appends.
