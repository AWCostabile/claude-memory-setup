# claude-memory-setup — Claude Context

## What This Project Is

A setup guide and patched hook files for wiring together a four-system persistent memory
architecture in Claude Code. It is not a plugin or library — it's documentation and
configuration that Claude reads and follows.

Published at: `https://github.com/AWCostabile/claude-memory-setup`

## Structure

| File / Dir | Purpose |
|---|---|
| `README.md` | Human-readable overview, author's note, credits, quick setup prompt |
| `AGENT.md` | Self-executing setup guide — Claude fetches and follows this |
| `hooks/mempal-stop-hook.sh` | Hardened MemPalace Stop hook (upstream 3.6.0 + py-fallback-v3) |
| `hooks/mempal-precompact-hook.sh` | Hardened MemPalace PreCompact hook (upstream 3.6.0 + py-fallback-v3) |
| `hooks/session-journal.sh` | Continuity layer: crash-surviving session journal (WAL), dirty-session recovery, subagent harvest, orchestration manifest |
| `agents/` | Routed subagent stable: implementer-deep (opus/high), implementer (opus/medium), mechanic (sonnet/low) — each with the memory protocol |
| `docs/orchestration-rubric.md` | Standing subagent routing policy, installed as a marked block in `~/.claude/CLAUDE.md` |
| `tests/` | Continuity-layer regression suite — real-payload fixtures (provenance recorded), machine data in `.claude/test-machine.env`, fixture re-capture rig |
| `scripts/memory-doctor.sh` | One-glance impact audit of the four memory systems + continuity layer |
| `scripts/sync-hooks.sh` | Drift-repair loop — re-applies hook patches after plugin updates |
| `scripts/install-continuity.sh` | Idempotent installer/repairer for the journal layer (user-level; `--check` for report-only) |
| `scripts/install-orchestration.sh` | Idempotent installer/repairer for the agent stable + rubric (`--check` for report-only) |
| `.gitattributes` | Enforces LF line endings on all files |

## The Two Upstream Plugins

This repo wires together two plugins it does not own:
- **MemPalace** — `github.com/milla-jovovich/mempalace`
- **claude-mem** — `github.com/thedotmack/claude-mem`

Hook patches are applied to MemPalace's hooks after installation. They will be overwritten
by plugin updates — the `hooks/` directory here is the canonical patched source, and
`scripts/sync-hooks.sh` re-applies it (wired as a SessionStart hook in this repo, so drift
heals at session start). Since MemPalace 3.6.0 the patches only harden interpreter
resolution (functional `python3` → `python` → `py` probe); the original behavioral fixes
were adopted upstream.

## Key Conventions

- `AGENT.md` phases are numbered 0–11; Phase 7 is subdivided 7a–7f (per-project steps)
- `[ASK USER]` gates in `AGENT.md` are hard stops — Claude must not skip or assume defaults
- All shell commands are bash-compatible and cross-platform (macOS, Linux, Windows via Git Bash)
- Interpreters are resolved **functionally** (`python3` → `python` → `py`, each probed with
  a real execution) — never by PATH lookup alone; Windows Store stubs exist on PATH but fail
- Hook patches touch **all** install locations: marketplace + every cache version dir
- Hook commands embedded in settings JSON must be pipe-tested as the **full saved command**,
  not a fragment — fragments miss bash-level quoting breaks
- Continuity-layer canon lives in this repo (`hooks/session-journal.sh`, `agents/`,
  `docs/orchestration-rubric.md`) but installs **user-level** so every project is protected;
  installers are idempotent and drift-checked at session start
- `CLAUDE_PID` is the HOST process (one VS Code host serves many sessions; children
  inherit their spawner's value). PID-dead proves context is gone → inject recovery;
  PID-alive means context is likely still open in a live window → stay conservative.
  `CLAUDE_CODE_CHILD_SESSION` is NOT a child discriminator (set in top-level VS Code too)
- Journal retention keys off the turn-end stamp (= content committed to claude-mem):
  closed 7d → delete; suspended 30d or transcript-gone → delete; dirty 30d → `attic/`,
  attic 90d → prune. Dirty tails are the only copy of mid-turn work — never silently deleted

## When Updating This Repo

- **AGENT.md change** — bump the phase it affects; verify cross-platform parity
- **Hook file change** — update `hooks/` and the inline code block in the corresponding phase
- **README change** — keep the Quick Setup prompt in sync if the AGENT.md fetch URL changes
- **Plugin update breaks something** — patch the new hook files, update `hooks/`, commit

## Current Status

Complete and ready for use. Pushed to GitHub at `AWCostabile/claude-memory-setup`.
Collaboratively built by Anthony + Claude, April 2026; under Claude's stewardship since
July 2026 (session-start ritual: run `bash scripts/memory-doctor.sh` before adding
features). Stewardship session #2 (2026-07-31) added the continuity layer — session
journal (WAL), dirty-session recovery, subagent harvest, orchestration manifest, and the
routed agent stable — machine-verified end-to-end; AGENT.md phase canonization is queued
until it has proven itself in organic use.

## AI Session Context
@.claude/AI_CONTEXT.md
