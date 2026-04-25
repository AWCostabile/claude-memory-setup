# claude-memory-setup

A four-system persistent memory architecture for Claude Code — so every new session picks
up where the last one left off.

## Quick Setup

Open any Claude Code session — in VS Code, the Claude desktop app, or anywhere else — and
paste the following prompt. Claude will fetch the setup guide and walk you through it.

```
Please run the following command and follow the instructions in the output:
curl -s https://raw.githubusercontent.com/AWCostabile/claude-memory-setup/master/AGENT.md

This is a system-wide setup, not tied to any specific project. Work through the phases in
order and pause at [ASK USER] prompts for my input.
```

> **Why `curl` instead of a URL fetch?** Claude's built-in web fetch tool summarises content
> before returning it — which would garble the setup guide. `curl` retrieves the raw text
> directly, so Claude reads the full instructions as written.

> This sets up memory for your entire Claude Code environment — preferences, identity, and
> hooks that travel with you across every project. Per-project configuration (Phase 7) can
> be run separately for each project you work in, any time after the global setup is done.

## The problem

Claude Code starts every conversation cold. No memory of what you built last week, what
decisions you made, what your conventions are, or where you left off. This guide fixes that
by wiring together four complementary systems that each cover a different part of the
persistence problem.\
_See [Author's Note](#authors-note) below for more background._

## The systems

| System                | What it is                                      | What it does                                                                                                             |
| --------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **CLAUDE.md**         | A markdown file in your project root            | Auto-loaded every session — project conventions, architecture, gotchas. Highest reliability: no plugins, no network.     |
| **Local file memory** | `.md` files in `~/.claude/projects/.../memory/` | Cross-session preferences and feedback, outside the repo. Populated when you say "please remember...".                   |
| **MemPalace**         | Python package (`pip install mempalace`)        | Semantic knowledge palace mined from your project files. Surfaces relevant context at session start via wake-up command. |
| **claude-mem**        | Bun HTTP worker on `localhost:37777`            | Captures what actually happened in each session — decisions, features, bugs. Auto-saves a baseline record every session. |

### How they connect

```
Session starts
  → CLAUDE.md loads automatically          (project conventions, always)
  → SessionStart hook fires
      → MemPalace wake-up injects summary  (project knowledge, semantic)
      → claude-mem injects recent history  (what we last did, chronological)

During session
  → "please remember X" triggers hook
      → stores to all four systems simultaneously

Session ends
  → Stop hook fires silently
      → writes baseline observation to claude-mem (automatic)
      → Claude writes richer diary entry at natural breakpoints (explicit)
```

## What you get

**Reliably:**

- Claude knows your project from the first message — no re-explaining the stack
- Your preferences travel with you across every project and conversation
- No session disappears silently — a baseline record is always written automatically
- "Remember this" routes everywhere without you thinking about where it goes

**Improved but not perfect:**

- Rich session summaries depend on Claude writing them at natural breakpoints — the hook
  guarantees a baseline, but the detailed "here's what we decided and why" needs Claude
  to do it explicitly
- Cross-session recall is strong for decisions and preferences, weaker for conversational
  texture

**Keep in mind:**

- Claude still starts each session fresh in working memory — context is loaded in, not
  natively remembered
- The more you put in, the more you get out — saying "please remember" when something
  matters compounds over time

## How to run the setup

See [Quick Setup](#quick-setup) above for the copy-paste prompt. It works in any Claude
interface — VS Code chat panel, Claude desktop app, claude.ai, or the CLI.

Claude fetches `AGENT.md` directly from this repo and follows it, pausing at **[ASK USER]**
prompts for your input. The setup takes roughly 15–30 minutes end-to-end, mostly waiting on
installs and Claude writing config files.

Once the global setup is done, per-project configuration (Phase 7) can be run any time by
opening Claude Code inside a project and saying:

> "Please run the per-project memory setup for this project — global setup is already complete."

## Prerequisites

- macOS, Linux, or Windows — mobile platforms are not supported due to OS restrictions
- Python 3.9+
- [Bun](https://bun.sh) — required by the claude-mem worker
- [Claude Code](https://claude.ai/code) installed and authenticated

## What's in this repo

```
claude-memory-setup/
├── README.md       ← you are here (human overview)
├── AGENT.md        ← the executable setup plan (Claude reads and follows this)
└── hooks/
    ├── mempal-stop-hook.sh        ← patched Stop hook (Phase 10)
    └── mempal-precompact-hook.sh  ← patched PreCompact hook (Phase 9)
```

The `hooks/` directory exists because two of the MemPalace plugin hooks ship broken and
must be patched after installation. The patched versions are here so Claude can copy them
directly rather than reconstructing them from code blocks.

## Re-running for a new project

The setup has a global phase (Phases 0–8, run once per machine) and a per-project phase
(Phase 7, run for each new project). Once the global setup is done, you can introduce any
new project to Claude with:

> "Please run the per-project memory setup for this project — global setup is already complete."

Claude will skip straight to Phase 7.

## Keeping the setup current

The hook files in `hooks/` are the canonical patched versions. If the MemPalace plugin
updates and overwrites them, re-apply from here. The setup guide includes a patch
verification command that Claude can run at the start of any session to catch this
automatically.

---

## Author's Note

This repository came out of a real working relationship between a developer and Claude Code
— built up gradually over many sessions, a lot of trial and error, and some genuinely
frustrating dead ends (ask us about the Stop hook sometime).

The core frustration was simple: every new conversation started cold. No memory of what we
were building, what decisions we'd made, what conventions we'd agreed on, or where we'd
left off. That friction compounds fast when you're deep in a project. We wanted sessions
that felt like continuing, not restarting.

What's in this repo is what we actually built — not a theoretical architecture, but a
working setup that's been debugged, patched, and refined through use. The hook patches in
particular (`hooks/`) exist because we hit the walls that ship with the default plugin
and had to find our way around them.

We're sharing it because the problem isn't unique to us. If you're using Claude Code
seriously, you're hitting the same friction. We found a way to wire the right tools
together and worked out the rough edges; this is that configuration, written up so you
don't have to retrace it from scratch.

A few things to know going in:

- **This is a living document.** If something breaks, changes, or gets better, we'll update
  it. If you find an improvement, contributions are welcome.
- **It's collaborative by design.** The setup is written as instructions Claude follows —
  not a shell script you run. Claude walks you through it, pauses at decision points, and
  adapts to your environment. That's intentional: the setup itself is a demonstration of
  the working relationship the system enables.
- **It's honest about its limits.** The "Before We Begin" section in `AGENT.md` spells out
  what works reliably, what's improved-but-not-perfect, and what to keep in mind. We'd
  rather set accurate expectations than oversell.

If it works well for you, or if you find a better approach to any of it — we'd genuinely
like to know!

---

## Credits

This setup is built on the shoulders of two excellent plugins — none of this works without
them, and the real engineering is theirs:

- **[MemPalace](https://github.com/milla-jovovich/mempalace)** by
  [@milla-jovovich](https://github.com/milla-jovovich) — the semantic knowledge palace that
  mines your project files and surfaces relevant context at session start. The wing/room/drawer
  taxonomy, the wake-up command, the AAAK diary format — all MemPalace.

- **[claude-mem](https://github.com/thedotmack/claude-mem)** by
  [@thedotmack](https://github.com/thedotmack) — the Bun HTTP worker that maintains
  cross-session observation history. The `/api/memory/save` endpoint our Stop hook writes to,
  the session timeline, the knowledge agent — all claude-mem.

What this repo contributes is the glue: the hook configuration that wires them together, the
patches for two hooks to ensure a seamless experience, the `AGENT.md` that lets Claude walk you through
the setup, and the documentation of what we learned the hard way. If either plugin improves
its defaults in a future release, parts of this guide may become unnecessary — and that would
be a good thing.

If you find this useful, consider starring the upstream repos too.

---

_See [AGENT.md](AGENT.md) for the full executable setup guide._
