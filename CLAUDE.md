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
| `hooks/mempal-stop-hook.sh` | Patched MemPalace Stop hook (sentinel + silent baseline save) |
| `hooks/mempal-precompact-hook.sh` | Patched MemPalace PreCompact hook (blocks once, then allows) |
| `.gitattributes` | Enforces LF line endings on all files |

## The Two Upstream Plugins

This repo wires together two plugins it does not own:
- **MemPalace** — `github.com/milla-jovovich/mempalace`
- **claude-mem** — `github.com/thedotmack/claude-mem`

Hook patches are applied to MemPalace's hooks after installation. They will be overwritten
by plugin updates — the `hooks/` directory here is the canonical patched source.

## Key Conventions

- `AGENT.md` phases are numbered 0–11; Phase 7 is subdivided 7a–7f (per-project steps)
- `[ASK USER]` gates in `AGENT.md` are hard stops — Claude must not skip or assume defaults
- All shell commands are bash-compatible and cross-platform (macOS, Linux, Windows via Git Bash)
- `python3` with `python` fallback throughout (Windows may only have `python`)
- Phase 9 and 10 touch **both** hook locations: cache and marketplace

## When Updating This Repo

- **AGENT.md change** — bump the phase it affects; verify cross-platform parity
- **Hook file change** — update `hooks/` and the inline code block in the corresponding phase
- **README change** — keep the Quick Setup prompt in sync if the AGENT.md fetch URL changes
- **Plugin update breaks something** — patch the new hook files, update `hooks/`, commit

## Current Status

Complete and ready for use. Pushed to GitHub at `AWCostabile/claude-memory-setup`.
Collaboratively built by Anthony + Claude Sonnet 4.6, April 2026.

## AI Session Context
@.claude/AI_CONTEXT.md
