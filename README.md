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

## Health check: the memory doctor

Memory infrastructure fails **silently** — a hook dies and sessions just quietly start
cold again. The memory doctor is the antidote: one read-only script that reports what each
system is actually *doing* — loaded? injecting at session start? capturing? when was the
last observation? — not what the config claims. It even live-fires your saved hook
commands with trigger and non-trigger inputs, the only test that catches quoting and
interpreter breaks.

```bash
curl -s https://raw.githubusercontent.com/AWCostabile/claude-memory-setup/master/scripts/memory-doctor.sh | bash
```

Run it from any project root whenever a session feels like it started cold. Expected
output is a checklist of `[ OK ]` lines ending in `== VERDICT: all systems delivering ==`;
any failure line names the fix. (Fun fact: v1 of this script found three independent
silent failures on the machine it was written on.)

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
| **Local file memory** | `.md` files in `~/.claude/projects/.../memory/` | Cross-session preferences and feedback, outside the repo. Recent Claude Code versions maintain this **natively** — the guide verifies and builds on it. |
| **MemPalace**         | Python package (`pip install mempalace`)        | Semantic knowledge palace mined from your project files. Surfaces relevant context at session start via wake-up command. |
| **claude-mem**        | Bun HTTP worker on `localhost:37777`            | Watches each session through its own hooks and generates narrative observations of what actually happened — decisions, features, bugs. Use v13+ (see AGENT.md Phase 6). |

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
  (on Windows, hooks run through Git Bash, which Claude Code uses natively — no separate
  PowerShell variants needed)
- Python 3.9+ that actually runs — on Windows, the Microsoft Store ships stub
  `python`/`python3` executables that exist on PATH but only print an error; everything in
  this guide probes interpreters functionally and falls back to the `py` launcher, so a
  broken stub won't silently kill your memory
- [Bun](https://bun.sh) — required by the claude-mem worker
- [Claude Code](https://claude.ai/code) installed and authenticated

## What's in this repo

```
claude-memory-setup/
├── README.md       ← you are here (human overview)
├── AGENT.md        ← the executable setup plan (Claude reads and follows this)
├── hooks/
│   ├── mempal-stop-hook.sh        ← hardened Stop hook (Phases 9–10)
│   ├── mempal-precompact-hook.sh  ← hardened PreCompact hook (Phase 9)
│   └── session-journal.sh         ← continuity layer: crash-surviving session journal (WAL)
├── agents/
│   ├── implementer-deep.md        ← routed subagent tier: opus/high — design-sensitive work
│   ├── implementer.md             ← routed subagent tier: opus/medium — standard features
│   └── mechanic.md                ← routed subagent tier: sonnet/low — mechanical edits
├── docs/
│   └── orchestration-rubric.md    ← standing routing policy (installs into ~/.claude/CLAUDE.md)
└── scripts/
    ├── memory-doctor.sh           ← one-glance impact audit: four systems + continuity layer
    ├── sync-hooks.sh              ← drift-repair: re-applies hook patches after plugin updates
    ├── install-continuity.sh      ← installs/repairs the session-journal layer (user-level)
    ├── install-orchestration.sh   ← installs/repairs the agent stable + routing rubric
    ├── tuneup-nudge.sh            ← fortnightly "tune-up due" reminder at session start
    ├── recap-nudge.sh             ← session-gap detection (stashes facts at session start)
    ├── recap-classify.sh          ← first-prompt classifier: injects a recap directive only when it helps
    └── compliance-test.sh         ← per-model directive-compliance harness (verified on sonnet + haiku)
```

The `hooks/` directory holds the canonical hardened versions of two MemPalace plugin
hooks. Historically they replaced broken stock behavior (a PreCompact hook that blocked
`/compact` unconditionally, a Stop hook that spammed the chat); MemPalace 3.6.0 fixed
both upstream — which is exactly what we hoped for — so today's patches only harden
interpreter resolution (the stock `python3`/`python` lookup dies on Windows machines where
the Microsoft Store stubs shadow real Python; the patched chain probes functionally and
falls back to `py`).

## Re-running for a new project

The setup guide runs Phases 0–11: global phases (run once per machine), one per-project
phase (Phase 7, run for each new project), hook hardening (Phases 9–10), and verification
(Phase 11, the memory doctor). Once the global setup is done, you can introduce any new
project to Claude with:

> "Please run the per-project memory setup for this project — global setup is already complete."

Claude will skip straight to Phase 7.

## Keeping the setup current

The hook files in `hooks/` are canonical. Plugin updates overwrite the installed copies —
that's not hypothetical; it's the designed failure mode of this architecture, and it
happened on the authors' own machine. Two tools keep it healed:

- **`scripts/sync-hooks.sh`** compares the canonical hooks against every installed copy
  (marketplace + all cache version dirs) and re-applies on mismatch. Run with `--check`
  for a report-only pass. Wire it as a SessionStart hook in a project you open daily
  (AGENT.md Phase 9 shows how) and drift heals itself at session start.
- **`scripts/memory-doctor.sh`** is the detection layer: it flags missing patches, dead
  injection, stale capture, and broken hook commands — anything sync-hooks can't fix
  it names the phase that can.
- **`scripts/tuneup-nudge.sh`** keeps the cadence: wired as a SessionStart hook, it has
  Claude remind you when the doctor hasn't run in 14+ days, and stays silent otherwise.
- **`scripts/install-continuity.sh`** and **`scripts/install-orchestration.sh`** are the
  continuity layer's own drift repair: idempotent installers with a `--check` report mode,
  wired as SessionStart hooks in this repo so the user-level copies heal at session start.

## The continuity layer

All four memory systems write their valuable artifacts at session *boundaries* — the Stop
hook summarizes a completed turn, PreCompact saves before compaction. A long autonomous
run is one giant turn, and a session killed mid-turn (usage limit, crash, power loss)
never reaches a boundary. We verified the consequence directly: a controlled mid-turn
kill streamed 14 tool events to claude-mem and produced **zero observations** — the
worker's queue is transient and distillation is turn-gated. Whole orchestration runs can
vanish from memory this way.

The continuity layer is the shell-level answer — it spends zero model tokens, so it works
at the exact moment token-spending saves cannot:

- **Session journal (WAL)** — `hooks/session-journal.sh`, wired user-level on six hook
  events, appends one breadcrumb per tool call to `~/.claude/session-journals/`. Stop
  stamps mark turn boundaries, so the journal always knows what a crash left unrecorded.
- **Dirty-session recovery** — at session start, journals whose owner process is gone and
  whose tail is post-stamp breadcrumbs trigger an assess-first context injection: what the
  dead session was doing, what its subagents reported, and the `claude --resume` command
  that brings it back. Parallel and suspended sessions are never false-flagged (owner PID
  identity is checked; inherited PIDs in child sessions are distrusted).
- **Subagent harvest** — SubagentStop delivers each subagent's final report; the hook
  journals it, closes the orchestration manifest entry, and POSTs it to claude-mem's
  ingestion route with agent attribution. Background agents' reports — which claude-mem
  never captures on its own — survive their orchestrator.
- **Orchestration manifest + agent stable** — spawns and reports are tracked per session
  and re-injected after compaction (no more re-discovering subagent state), and
  `agents/` ships three routed tiers (implementer-deep / implementer / mechanic) whose
  model + reasoning effort + memory posture ride the agent definition, governed by the
  standing rubric in `docs/orchestration-rubric.md`.

Install both with:

```bash
bash scripts/install-continuity.sh
bash scripts/install-orchestration.sh
```

Status: machine-verified end-to-end (kill → recovery injection → resumable id; mechanic
tier confirmed running at `effort: low`; harvested reports confirmed distilled into
claude-mem observations) on Claude Code 2.1.150/2.1.220. It has not yet been folded into
AGENT.md's numbered phases — that happens after a proving period of organic use, per this
repo's rule that the guide only teaches what has actually worked.

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
