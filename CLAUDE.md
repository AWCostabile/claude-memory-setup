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
| `scripts/memory-doctor.sh` | One-glance impact audit of all four memory systems |
| `scripts/sync-hooks.sh` | Drift-repair loop — re-applies hook patches after plugin updates |
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

## When Updating This Repo

- **AGENT.md change** — bump the phase it affects; verify cross-platform parity
- **Hook file change** — update `hooks/` and the inline code block in the corresponding phase
- **README change** — keep the Quick Setup prompt in sync if the AGENT.md fetch URL changes
- **Plugin update breaks something** — patch the new hook files, update `hooks/`, commit

## Current Status

Complete and ready for use. Pushed to GitHub at `AWCostabile/claude-memory-setup`.
Collaboratively built by Anthony + Claude, April 2026; under Claude's stewardship since
July 2026 (session-start ritual: run `bash scripts/memory-doctor.sh` before adding
features).

## AI Session Context
@.claude/AI_CONTEXT.md
