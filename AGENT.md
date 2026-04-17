# Four-System Memory Architecture — Agent Setup Guide

> **How to use this file:** You are Claude Code, and a user has asked you to read and follow
> this guide. Work through the phases in order. Sections marked **[ASK USER]** mean you must
> pause and wait for the user's answer before continuing — do not skip them or substitute
> defaults without asking. Everything else can be executed autonomously.
>
> **Re-running this guide on an existing setup is safe.** Every phase is designed to be
> idempotent: check first, skip or merge if already present, never overwrite blindly. If
> something is already configured correctly, confirm it and move on — don't replace it
> unless the user explicitly asks.
>
> **Platform note:** This guide targets macOS, Linux, and Windows. Shell commands use bash
> syntax (Claude Code runs hooks via bash on all platforms, including Windows via Git Bash).
> Platform differences are called out inline where they exist.
>
> **Before starting**, introduce yourself briefly:
> "I'm going to set up a four-system persistent memory architecture for your Claude Code
> environment — system-wide, so future sessions across all your projects start with full
> context rather than cold. I'll walk you through it step by step and pause at key
> decisions. Let's begin with a preflight check."

---

## Before We Begin

By the time you finish this setup, working with Claude will feel meaningfully different.
Right now, every new conversation starts cold — Claude has no idea who you are, what you're
building, or where you left off. That friction adds up. This guide fixes it.

Here's an honest picture of what changes, what improves, and what to keep in mind.

### What you'll reliably get

- **Claude knows your project from the first message.** Architecture, conventions, gotchas,
  autoloads — all loaded automatically before you type anything. No more re-explaining the
  stack or pasting context from the README.
- **Your preferences travel with you.** Code style, working habits, how you like information
  presented — stored once, applied everywhere, across every project.
- **No session disappears silently.** A baseline record of every session is written
  automatically. The days of "what were we doing last time?" with no answer are over.
- **"Remember this" just works.** Say it naturally mid-conversation and it routes to all
  four memory systems without you thinking about where it goes.

### What's improved but not perfect

- **Session momentum** depends on Claude writing a proper summary at natural breakpoints —
  end of a feature, before compaction, when wrapping up. The hook guarantees a baseline,
  but the rich "here's what we decided and why" record needs Claude to do it explicitly.
  Think of it like a colleague who takes good notes most of the time, not always.
- **Cross-session recall** is strong for decisions and preferences, weaker for the texture
  of a conversation — the back-and-forth, the reasoning that didn't make it into a summary.
  What was decided is durable. How you got there is not always.

### What to keep in mind

- **Claude still starts each session fresh** in terms of working memory — the memory systems
  load context in, but it's not the same as Claude having been there. Expect it to ask a
  clarifying question occasionally even on familiar ground.
- **The more you put in, the more you get out.** Saying "please remember" when something
  matters, nudging Claude to save at the end of a productive session, keeping CLAUDE.md
  current — these compound over time into a genuinely useful working relationship.
- **Some things need to be said.** If a project changes direction significantly, mention it.
  If a preference shifts, update it. Claude will pick up on signals and offer to update
  things proactively, but it's not reading your mind.

With that framing in place — let's get it set up.

---

## The Tooling

Four systems work together here. Each solves a different part of the persistence problem —
none of them alone is sufficient, which is why this guide wires all four.

### CLAUDE.md
A plain markdown file in the project root that Claude Code loads automatically at the start
of every session. Think of it as the project brief that's always on the desk — architecture,
conventions, gotchas, entry points. It's the highest-reliability layer because it requires
no plugins, no hooks, and no network calls. The tradeoff: it's static. It only knows what
you've written into it, and it's committed to the repo, so it stays focused on project
conventions rather than personal AI tooling config.

### Local file memory (`~/.claude/projects/<project>/memory/`)
A directory of typed `.md` files living in Claude Code's user data folder — outside the
repo, so never committed. This is where cross-session preferences live: code style rules,
working habits, feedback Claude has received. An index file (`MEMORY.md`) is loaded
automatically; individual files are read on demand. Populated by Claude when you say
"please remember ..." — a hook intercepts that phrase and routes the content here.

### MemPalace
A Python package (`pip install mempalace`) that runs a local semantic knowledge palace.
It works by *mining* your project files — source code, docs, changelogs — and storing
extracted knowledge in a structured, searchable store organised into wings (projects) and
rooms (topics). At the start of each session, a `wake-up` command injects a curated summary
of the most relevant knowledge into Claude's context. More durable than a summary file
because it's semantically indexed rather than linearly read — useful for larger codebases
where you want Claude to surface relevant past decisions without reading everything.

### claude-mem
A background HTTP worker (runs on `localhost:37777`) that maintains a cross-session
observation log. It stores timestamped records of what happened in each session — decisions
made, features built, bugs fixed — and surfaces them at session start via a hook. Unlike
MemPalace (which is mined from files), claude-mem captures *conversation history*: what
Claude and you actually did together. It also auto-saves a baseline record every session
via the Stop hook, so there's always a minimum trail even if no explicit save is made.
Powered by Bun; needs to be running when Claude Code is open.

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

---

## Overview

| System                | Purpose                                       | How populated                                        |
| --------------------- | --------------------------------------------- | ---------------------------------------------------- |
| **CLAUDE.md**         | Project conventions auto-loaded every session | Written by Claude and/or by you manually             |
| **Local file memory** | Typed `.md` preference/project/feedback files | Written when you say "remember X"                    |
| **MemPalace**         | Searchable semantic knowledge palace          | Mined from project files + written on request        |
| **claude-mem**        | Cross-session observation history             | Auto-captured via Stop hook + direct HTTP write      |

---

## Phase 0 — Preflight Checks

Run each of the following and report the output before proceeding.

```bash
# 1. Python version (3.9+ required)
#    macOS/Linux: python3 --version
#    Windows: python --version  (if python3 is not found)
python3 --version 2>/dev/null || python --version

# 2. pip available?
python3 -m pip --version 2>/dev/null || python -m pip --version

# 3. Bun (required by claude-mem worker)
bun --version || echo "NOT FOUND"

# 4. Claude Code CLI
claude --version

# 5. Check if mempalace is already installed
python3 -m pip show mempalace 2>/dev/null || python -m pip show mempalace 2>/dev/null || echo "NOT INSTALLED"

# 6. Check global Claude settings file
cat ~/.claude/settings.json 2>/dev/null || echo "FILE NOT FOUND"

# 7. Check if claude-mem worker data dir exists
ls ~/.claude-mem/ 2>/dev/null || echo "NOT FOUND"
```

> **Windows note:** If `python3` is not found, use `python` throughout this guide.
> Claude Code runs hooks via Git Bash on Windows, so bash syntax works — but the Python
> command name may differ. Use whichever resolves correctly from the check above.

**[ASK USER]** If Bun is not installed: "Bun is required by the claude-mem worker. Shall I
install it now?"
- macOS/Linux: `curl -fsSL https://bun.sh/install | bash`
- Windows: `powershell -c "irm bun.sh/install.ps1 | iex"` (run in PowerShell, not bash)

**[ASK USER]** If Python < 3.9: stop and ask the user to install a newer Python before
continuing.

If `settings.json` already exists with content, note its existing keys — all changes in
this guide must be **merged**, never replacing the file wholesale.

---

## Phase 1 — Install MemPalace

If already installed (shown in Phase 0 preflight), skip this phase.

```bash
pip3 install mempalace 2>/dev/null || pip install mempalace
python3 -m mempalace --version 2>/dev/null || python -m mempalace --version
```

If the install fails due to missing build tools, the fix depends on platform:

- **macOS:** `xcode-select --install`, then retry
- **Linux (Debian/Ubuntu):** `sudo apt install python3-dev build-essential`, then retry
- **Linux (Fedora/RHEL):** `sudo dnf install python3-devel gcc`, then retry
- **Windows:** `pip install --upgrade pip setuptools wheel`, then retry; if still failing,
  ensure Visual C++ Build Tools are installed via the
  [Visual Studio installer](https://visualstudio.microsoft.com/visual-cpp-build-tools/)

---

## Phase 2 — Configure Global Plugins (~/.claude/settings.json)

**[ASK USER]** "These plugins install from GitHub (`thedotmack/claude-mem` and
`milla-jovovich/mempalace`). Do you want to proceed with these sources, or use alternatives?"

Read `~/.claude/settings.json` first. If it doesn't exist, create it. Then **merge** (do not
replace) the following into it:

```json
{
  "enabledPlugins": {
    "claude-mem@thedotmack": true,
    "mempalace@mempalace": true
  },
  "extraKnownMarketplaces": {
    "thedotmack": {
      "source": {
        "source": "github",
        "repo": "thedotmack/claude-mem"
      }
    },
    "mempalace": {
      "source": {
        "source": "github",
        "repo": "milla-jovovich/mempalace"
      }
    }
  }
}
```

After writing, **restart Claude Code** before continuing to Phase 3 so the plugins are
active and their MCP tools are available.

---

## Phase 3 — Allow MemPalace Write Permissions (~/.claude/settings.json)

MemPalace write tools prompt for confirmation by default. Add them to the global allow list
so they fire silently during Stop hooks and memory saves.

Merge into `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__plugin_mempalace_mempalace__mempalace_add_drawer",
      "mcp__plugin_mempalace_mempalace__mempalace_diary_write",
      "mcp__plugin_mempalace_mempalace__mempalace_kg_add",
      "mcp__plugin_mempalace_mempalace__mempalace_kg_invalidate",
      "mcp__plugin_mempalace_mempalace__mempalace_update_drawer",
      "mcp__plugin_mempalace_mempalace__mempalace_delete_drawer"
    ]
  }
}
```

---

## Phase 4 — Global UserPromptSubmit Hook (~/.claude/settings.json)

This hook intercepts messages containing memory-trigger phrases ("remember this", "keep in
mind", "don't forget", etc.) and instructs Claude to store the memory across all four systems.

Merge the following `hooks` block into `~/.claude/settings.json` (preserve any existing keys):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"\nimport json, sys, re\ndata = json.load(sys.stdin)\nprompt = (data.get('tool_input') or {}).get('message', '') or data.get('message', '') or ''\npatterns = [r\\\"i(?:'d)?(?:\\\\s+would|\\\\s+want)?\\\\s+(?:like\\\\s+)?(?:you\\\\s+)?to\\\\s+remember\\\",r\\\"please\\\\s+remember\\\",r\\\"remember\\\\s+(?:that|this)\\\",r\\\"can\\\\s+you\\\\s+remember\\\",r\\\"make\\\\s+a\\\\s+(?:note|mental\\\\s+note)\\\",r\\\"keep\\\\s+(?:this\\\\s+)?in\\\\s+mind\\\",r\\\"don'?t\\\\s+forget\\\",r\\\"note\\\\s+(?:that|this|for\\\\s+future)\\\",r\\\"store\\\\s+(?:this|that)\\\\s+(?:away|in\\\\s+memory)\\\"]\nif prompt and any(re.search(p, prompt, re.IGNORECASE) for p in patterns):\n    msg = ('MEMORY REQUEST DETECTED. Analyse what the user wants remembered, classify its scope, then store it in ALL applicable systems:\\\\n'\n        '1. MEMPALACE (mcp__plugin_mempalace_mempalace__mempalace_add_drawer): Always use for any durable knowledge. Pick the right wing (project name) and room (general/decisions/src/maps/etc). For cross-project preferences use wing=user-preferences, room=feedback.\\\\n'\n        '2. LOCAL FILE MEMORY (~/.claude/projects/<project>/memory/): Write a typed .md file (feedback_*.md, project_*.md, user_*.md, reference_*.md) and add an entry to MEMORY.md. For cross-project preferences also write to ~/.claude/projects/global/memory/ (create dir if needed).\\\\n'\n        '3. CLAUDE.md: Update the project CLAUDE.md only if this is a session-critical project convention that every future session must know immediately (code style, architectural rules, critical gotchas).\\\\n'\n        '4. CLAUDE-MEM (direct write): call POST http://127.0.0.1:37777/api/memory/save with JSON body {\\\\\"project\\\\\": \\\\\"<current project>\\\\\", \\\\\"type\\\\\": \\\\\"decision\\\\\", \\\\\"text\\\\\": \\\\\"<the memory>\\\\\", \\\\\"title\\\\\": \\\\\"<short title>\\\\\"}. Use type=decision for preferences/rules, type=discovery for project-specific findings. Derive project name from the current working directory basename. If the worker is unreachable, fall back to narrating the memory clearly in your response so the Stop hook captures it from the transcript.\\\\n'\n        'After storing, confirm to the user: what was saved, which of the 4 systems it went into, and why each was chosen or skipped.')\n    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'additionalContext': msg}}))\n\" 2>/dev/null || true",
            "statusMessage": "Checking for memory requests..."
          }
        ]
      }
    ]
  }
}
```

**Pipe-test before saving** (verify the hook fires correctly):

```bash
echo '{"message": "I would like you to remember I prefer tabs over spaces"}' | python3 -c "
import json, sys, re
data = json.load(sys.stdin)
prompt = (data.get('tool_input') or {}).get('message', '') or data.get('message', '') or ''
patterns = [r\"i(?:'d)?(?:\s+would|\s+want)?\s+(?:like\s+)?(?:you\s+)?to\s+remember\"]
if prompt and any(re.search(p, prompt, re.IGNORECASE) for p in patterns):
    print('HOOK FIRES: OK')
else:
    print('HOOK SILENT: check pattern')
"
```

Expected output: `HOOK FIRES: OK`

---

## Phase 5 — Initialize MemPalace

Check current status:

```bash
python3 -m mempalace status
```

**If the palace is already initialized** — skip to the identity file step below. No
re-initialization needed.

**If not yet initialized:**

**[ASK USER]** "MemPalace stores its palace data in a directory on disk. Default locations
by platform:
- **macOS/Linux:** `~/.local/share/mempalace/palace`
- **Windows:** `%APPDATA%\mempalace\palace`

Press Enter to accept the default for your platform, or provide a custom path."

Then initialize using the chosen path (substitute `<PATH>` with the user's answer, or
omit for the default):

```bash
python3 -m mempalace init <PATH>
```

Confirm the MCP server is registered with Claude Code:

```bash
claude mcp add mempalace -- python3 -m mempalace.mcp_server
```

### Identity file

Create your identity file — shown at the top of every MemPalace wake-up, and used to
personalise how Claude understands who it's working with.

Before prompting, do a short investigation to build a suggestion:

**Step 1 — establish a name:**
Check `git config --global user.name` first. Fall back to `whoami`, capitalised.

**Step 2 — read the room:**
Look at the current directory. Don't assume a tech stack — instead, identify what *kind*
of project this appears to be (if any), then look for the files natural to that kind of
project. Examples:

- Directory has `.gd` files or a `project.godot` → Godot game project → check
  `project.godot` for the project name
- Directory looks like a web frontend → check for whichever package manifest exists
  (`package.json`, `Gemfile`, `pubspec.yaml`, etc.) and read name + key dependencies
- Directory has Python files → check `pyproject.toml`, `setup.py`, or `requirements.txt`
- Directory has a `README.md` → skim the first 20–30 lines for project name and description
- No repo, no recognisable structure → note that and skip to Step 3

**Step 3 — build the suggestion:**

Format: `<Name> — <Role>, working on '<Project>' (<Key tech>)`

- **Role**: infer from what you found — be specific (`Godot game programmer`, `React developer`,
  `Python data engineer`) rather than generic
- **Project name**: use the value from the spec file or README; omit entirely if nothing found
- **Key tech in parentheses**: only include if it adds meaningful detail beyond the role.
  Omit entirely if nothing useful to add.

**Step 4 — present and confirm:**

If a reasonable suggestion was assembled:

**[ASK USER]** "Based on what I can see, I'd suggest: `<suggestion>` — does that look
right, or would you like to adjust it?"

If there wasn't enough to go on:

**[ASK USER]** "I couldn't find enough project context to suggest an identity automatically.
This file is shown at the start of every session, so it's worth getting right — please
provide one sentence describing who you are and what you work on. Format suggestion:
`<Your name> — <your role>, working on '<project name>' (<key tech if relevant>)`"

Once confirmed, write it:

```bash
echo "<confirmed identity string>" > ~/.mempalace/identity.txt
```

### Keeping identity current

The identity file should stay accurate as projects evolve. Two ways it can be updated:

**Explicitly** — the user can say "update my identity" or "my identity needs updating" at
any point in any conversation. Claude should read the current `~/.mempalace/identity.txt`,
briefly re-investigate the current project state (same process as above), propose a revised
string, confirm, then overwrite the file.

**Proactively** — if the user mentions a significant project change during conversation
(a major dependency migration, a role change, a project pivot), Claude should read
`~/.mempalace/identity.txt`, infer what the updated identity should be, then offer it inline:
> "That sounds like a meaningful shift — want me to update your MemPalace identity? It
> currently reads `<current>`. I'd suggest changing it to `<proposed>`."

In both cases: suggest first, confirm before writing. Never silently overwrite.

---

## Phase 6 — Initialize claude-mem Worker

The claude-mem worker is a background HTTP server (port 37777) that stores and retrieves
cross-session observations.

Check if it's already running:

```bash
curl -s http://127.0.0.1:37777/api/health | python3 -m json.tool
```

If the health check returns `{"status":"ok",...}` — the worker is running. No action needed.

If it fails to respond, the worker starts automatically when Claude Code loads the plugin.
If it still fails after a restart:

**[ASK USER]** "The claude-mem worker requires Bun. Check `~/.claude-mem/settings.json` —
does it exist, and does it have a `CLAUDE_MEM_PROVIDER` key? Tell me what provider you're
using (claude.ai subscription, AWS Bedrock, GCP Vertex) and I'll configure it."

Provider settings to add to `~/.claude-mem/settings.json`:

```json
{
  "CLAUDE_MEM_PROVIDER": "claude",
  "CLAUDE_MEM_MODEL": "claude-sonnet-4-6"
}
```

> The worker's health response includes an `authMethod` field — verify it matches your
> expected auth method after startup.

---

## Phase 7 — Per-Project Setup

For **each project** you work on, run through these steps when you first open it in
Claude Code.

### 7a. Add AI tooling files to .gitignore

Ensure the project's `.gitignore` contains:

```
.claude/
mempalace.yaml
entities.json
```

### 7b. Initialize MemPalace for the project

```bash
cd /path/to/project
python3 -m mempalace init .
python3 -m mempalace mine .
```

**[ASK USER]** During `mempalace init`, it will detect entities (people, projects, etc.).
Review the detected list and confirm or correct it before proceeding.

### 7c. Hide MemPalace files from view

`mempalace init` creates `mempalace.yaml` and `entities.json` in the project root. These
are gitignored but still visible in the filesystem and editor. Hide them:

**VS Code** — add to `.vscode/settings.json` (merge, don't replace):
```json
{
  "files.exclude": {
    "entities.json": true,
    "mempalace.yaml": true
  }
}
```

**macOS / Linux** — neither platform has a simple hidden-file attribute for arbitrary
filenames. The VS Code exclude above is the primary solution on both. Prefix-renaming
the files to `.mempalace.yaml` etc. would hide them from the terminal but breaks MemPalace
(it expects the exact filenames), so VS Code exclusion is the practical limit.

**Windows** — in addition to the VS Code exclude, you can set the hidden attribute so
the files don't appear in Explorer:
```bash
attrib +h mempalace.yaml entities.json
```

### 7d. Create local file memory directory

```bash
# macOS/Linux:
mkdir -p ~/.claude/projects/$(python3 -c "import os; print(os.getcwd().replace('/', '--').lstrip('-'))")/memory

# Windows (if python3 is not found, use python):
mkdir -p ~/.claude/projects/$(python -c "import os; print(os.getcwd().replace('/', '--').replace('\\\\', '--').lstrip('-'))")/memory
```

Then create `MEMORY.md` in that directory:

```markdown
# <ProjectName> — Memory Index

<!-- Max 200 lines. One entry per memory file: [Title](file.md) — one-line hook -->
```

### 7e. Create CLAUDE.md and .claude/AI_CONTEXT.md

**CLAUDE.md** lives in the project root and is auto-loaded by Claude Code every session.
Keep it focused on project conventions — nothing AI-tooling-specific. End the file with:

```markdown
## AI Session Context
@.claude/AI_CONTEXT.md
```

This imports `.claude/AI_CONTEXT.md` when it exists. Other project contributors won't have
`.claude/` (it's gitignored), so Claude Code will silently skip the import for them.

**[ASK USER]** "I'm about to create a `CLAUDE.md` in the project root. Should I scan the
project first to generate it automatically, or do you want to provide the conventions now?"

CLAUDE.md should cover at minimum:
- What the project is and its current status
- Technology stack and key constraints
- Entry point and application flow
- Key autoloads / singletons / services
- Code style conventions
- Critical gotchas (things that caused bugs or confusion before)

**`.claude/AI_CONTEXT.md`** holds everything memory-strategy-related — invisible to other
contributors since `.claude/` is gitignored. Create it with:

```markdown
# AI Session Context — <ProjectName>

## Four-System Memory Architecture
| System | Location | Purpose |
|--------|----------|---------|
| CLAUDE.md + this file | Project root / `.claude/` | Auto-loaded project + AI context |
| Local memory files | `~/.claude/projects/<key>/memory/` | Cross-session preferences |
| MemPalace | Global palace | Deep searchable knowledge palace |
| claude-mem | HTTP worker port 37777 | Cross-session observation history |

## Active Preferences
[paste confirmed preferences from Phase 8 here]

## Hook Patches Required
Verify after any MemPalace plugin update:
grep -r "MEMPALACE-PATCH:" ~/.claude/plugins/cache/mempalace/ ~/.claude/plugins/marketplaces/mempalace/

## MemPalace Wing
Wing name for this project: <wing-name>
```

### 7f. Add SessionStart hooks to .claude/settings.local.json

Create or update `.claude/settings.local.json` in the project root:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "PYTHONIOENCODING=utf-8 python3 -m mempalace wake-up --wing <WING_NAME> 2>/dev/null || true",
            "statusMessage": "Recalling <ProjectName> palace context..."
          },
          {
            "type": "command",
            "command": "python3 -c \"\nimport urllib.request, json, os\nproject = os.path.basename(os.getcwd())\ntry:\n    r = urllib.request.urlopen(f'http://127.0.0.1:37777/api/context/recent?project={project}&limit=8', timeout=3)\n    data = json.loads(r.read().decode())\n    text = ' '.join(c.get('text','') for c in data.get('content',[]) if c.get('type')=='text').strip()\n    if text and 'No previous sessions' not in text:\n        ctx = f'CLAUDE-MEM recent observations for {project}:\\n{text}'\n        print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': ctx}}))\nexcept:\n    pass\n\" 2>/dev/null || true",
            "statusMessage": "Loading claude-mem session history..."
          }
        ]
      }
    ]
  }
}
```

Replace `<WING_NAME>` with the lowercase project name and `<ProjectName>` with the display
name.

**[ASK USER]** "What is the MemPalace wing name for this project? Suggested:
`<lowercased directory name>`. Confirm or provide your preferred name."

Pipe-test the SessionStart claude-mem hook:

```bash
echo '{}' | python3 -c "
import urllib.request, json, os
project = os.path.basename(os.getcwd())
try:
    r = urllib.request.urlopen(f'http://127.0.0.1:37777/api/context/recent?project={project}&limit=8', timeout=3)
    data = json.loads(r.read().decode())
    print('Worker reachable. Project:', project)
    print('Response keys:', list(data.keys()))
except Exception as e:
    print('Worker unreachable:', e)
"
```

---

## Phase 8 — Register Personal Preferences

These are cross-project behavioural preferences — things Claude will carry into every
project and conversation, not just this one. They're a starting point, not a fixed list:
skip any that don't fit, modify any wording that doesn't feel right, and add new ones
any time by saying "please remember: ..." in any future conversation.

**[ASK USER]** Work through each preference below one at a time. For each one, ask:
> "Would you like to adopt this preference? (yes / no / modify)"

If the user says **yes**, store it as-is using:
> "Please remember: [preference text]"

If the user says **modify**, discuss and agree on the adjusted wording before storing.
If the user says **no**, skip it — no explanation needed.

The UserPromptSubmit hook will detect the "please remember" trigger and route each confirmed
preference to all four memory systems automatically.

---

### Preference 1: Auto-initialize memory strategies for new projects

> When a new project is introduced, initialize all four memory systems (MemPalace mine,
> local memory dir + MEMORY.md, CLAUDE.md, claude-mem worker check) before doing any
> other work.

---

### Preference 2: Re-orient after long gaps + post-weekend recap

This preference has configurable thresholds. Before storing, ask:

**[ASK USER]**
> "This preference has a few configurable values — I'll suggest defaults, you can adjust
> any of them:
>
> 1. **New session gap** — how many hours since the last conversation before I should
>    proactively recap? *(suggested: 4 hours)*
> 2. **Resumed conversation gap** — how many hours of inactivity in an existing conversation
>    before I should re-orient? *(suggested: 6 hours)*
> 3. **Post-weekend recap** — on Mondays (or the first session after a weekend), would you
>    like a brief recap of what we were working on the previous week? *(suggested: yes)*
>
> Confirm or adjust each value."

Once confirmed, substitute the user's values into the preference text and store it:

> If more than **[GAP_1] hours** have passed since the last conversation, OR an existing
> conversation is resumed after **[GAP_2] hours** of inactivity, proactively recap what we
> were working on, where we left off, and what the next step was. Gently verify the user's
> recollection before acting on details they provide — they may be less accurate on specifics
> after a long gap. Goal: preserve momentum without the user needing to re-brief from scratch.
>
> Additionally, on Mondays or the first session following a weekend break, open with a brief
> recap of what was being worked on the previous week, even if the gap was less than [GAP_1]
> hours — weekends interrupt working memory differently than shorter gaps.

---

### Preference 3: Alphabetize static declarations (not runtime data)

> Alphabetize keys in static source code declarations — object literals, interfaces, types,
> structs, enums, and similar constructs — for readability and consistency.
> This applies to anything authored as a static declaration for a human reader.
> Do NOT apply to runtime data structures where order may be meaningful (ordered maps,
> serialized payloads, API response shapes, queues, lookup tables with meaningful insertion
> order, etc.).
> Exception within sorted blocks: identifier/primary-key fields (`id`, `userId`, `playerId`,
> etc.) may be placed first regardless of alphabetical position.

---

## Phase 9 — Patch the PreCompact Hook (Required)

The MemPalace plugin ships with a PreCompact hook that **unconditionally blocks `/compact`**,
making context compaction impossible without this fix. Apply it immediately after plugin
installation, and re-apply after any MemPalace plugin update.

### Why this happens

The hook always outputs `{"decision":"block"}` with no mechanism to signal that a save has
already occurred, so `/compact` loops forever.

### The fix — sentinel file pattern

The patched file is in this repository at [`hooks/mempal-precompact-hook.sh`](hooks/mempal-precompact-hook.sh).
Copy it to **both** of the following locations:

1. `~/.claude/plugins/cache/mempalace/mempalace/<version>/hooks/mempal-precompact-hook.sh`
2. `~/.claude/plugins/marketplaces/mempalace/.claude-plugin/hooks/mempal-precompact-hook.sh`

Find the version directory, then copy:

```bash
HOOK_SRC="<path-to-this-repo>/hooks/mempal-precompact-hook.sh"
VERSION=$(ls ~/.claude/plugins/cache/mempalace/mempalace/ | head -1)
cp "$HOOK_SRC" ~/.claude/plugins/cache/mempalace/mempalace/$VERSION/hooks/mempal-precompact-hook.sh
cp "$HOOK_SRC" ~/.claude/plugins/marketplaces/mempalace/.claude-plugin/hooks/mempal-precompact-hook.sh
chmod +x ~/.claude/plugins/cache/mempalace/mempalace/$VERSION/hooks/mempal-precompact-hook.sh
chmod +x ~/.claude/plugins/marketplaces/mempalace/.claude-plugin/hooks/mempal-precompact-hook.sh
```

After patching, prime the sentinel so the very first `/compact` succeeds without triggering
a forced save cycle (one-time only):

```bash
touch ~/.mempalace-precompact-ready
```

### What the patch does

The patched hook blocks **once** to prompt a save, then allows compaction on the retry.
A sentinel file in the home directory tracks whether the save prompt has already fired.
The Stop hook already writes a baseline record every session, so the prompt is a safety net
rather than the only save mechanism.

### Compacting after an explicit save

If you write a diary entry *before* running `/compact` (the recommended workflow), the hook
will still block on the first attempt — because the sentinel was never set by a prior blocked
run. This is expected. Just touch the sentinel manually and run `/compact` again:

```bash
touch ~/.mempalace-precompact-ready
# then run /compact
```

Claude can do this for you automatically — if you've just saved a diary entry and are about
to compact, say "please compact now" and Claude should touch the sentinel before triggering
`/compact`.

---

## Phase 10 — Patch the Stop Hook (Required)

### What the Stop hook actually does

The Stop hook fires after **every single Claude response** — not just when you close the
window or end a session. It runs constantly in the background throughout normal conversation.

The default hook outputs its save-prompt as raw visible text in the chat after every reply,
which is noisy. More critically, the default hook only *asks* Claude to save — if Claude
doesn't explicitly call `mempalace_diary_write` and `mempalace_add_drawer` in response,
nothing gets recorded. Sessions can silently disappear with no memory trace at all.

### The fix — two goals in one patch

1. **Suppresses UI noise** — emits nothing to the chat window (the only reliable method;
   `suppressOutput` is insufficient for Stop hooks — Claude Code displays Stop hook output
   regardless, as a transparency feature that cannot be overridden via JSON)
2. **Auto-saves a baseline to claude-mem** — writes a timestamped record automatically,
   using the session ID as a sentinel so it fires only once per session

Claude's richer `mempalace_diary_write` saves layer on top of this baseline.

### Applying the patch

The patched file is in this repository at [`hooks/mempal-stop-hook.sh`](hooks/mempal-stop-hook.sh).
Copy it to **both** locations:

```bash
HOOK_SRC="<path-to-this-repo>/hooks/mempal-stop-hook.sh"
VERSION=$(ls ~/.claude/plugins/cache/mempalace/mempalace/ | head -1)
cp "$HOOK_SRC" ~/.claude/plugins/cache/mempalace/mempalace/$VERSION/hooks/mempal-stop-hook.sh
cp "$HOOK_SRC" ~/.claude/plugins/marketplaces/mempalace/.claude-plugin/hooks/mempal-stop-hook.sh
chmod +x ~/.claude/plugins/cache/mempalace/mempalace/$VERSION/hooks/mempal-stop-hook.sh
chmod +x ~/.claude/plugins/marketplaces/mempalace/.claude-plugin/hooks/mempal-stop-hook.sh
```

> **Note:** Both patches will be overwritten if the MemPalace plugin auto-updates.
> Re-apply them if the behaviours regress. The patch check in Phase 11 catches this
> automatically.

---

## Phase 11 — Verification Checklist

Run through this checklist before closing the setup session.

### Hook patch check

Run at setup completion, and again at the start of any session after a plugin update.
Each command should print the patch marker — if either prints nothing, re-apply from
Phase 9 or 10.

```bash
grep -r "MEMPALACE-PATCH:precompact-sentinel-v1" ~/.claude/plugins/cache/mempalace/ ~/.claude/plugins/marketplaces/mempalace/ 2>/dev/null \
  && echo "PreCompact patch: OK" || echo "PreCompact patch: MISSING — re-apply Phase 9"

grep -r "MEMPALACE-PATCH:stop-suppress-v1" ~/.claude/plugins/cache/mempalace/ ~/.claude/plugins/marketplaces/mempalace/ 2>/dev/null \
  && echo "Stop patch: OK" || echo "Stop patch: MISSING — re-apply Phase 10"
```

### Full setup checklist

- [ ] Patch check above passes for both hooks
- [ ] `python3 -m mempalace status` shows a palace with at least one wing
- [ ] `curl -s http://127.0.0.1:37777/api/health` returns `{"status":"ok",...}`
- [ ] `~/.claude/settings.json` contains `enabledPlugins`, `extraKnownMarketplaces`, `permissions.allow`, and `hooks.UserPromptSubmit`
- [ ] `.claude/settings.local.json` in the project root contains `hooks.SessionStart` with 2 hooks
- [ ] `CLAUDE.md` exists in project root, ends with `@.claude/AI_CONTEXT.md` import
- [ ] `.claude/AI_CONTEXT.md` exists and preferences section is filled in (not placeholder text)
- [ ] `~/.claude/projects/<project-key>/memory/MEMORY.md` exists
- [ ] `.gitignore` includes `.claude/`, `mempalace.yaml`, `entities.json`
- [ ] `mempalace.yaml` and `entities.json` are excluded in `.vscode/settings.json`
- [ ] `~/.mempalace/identity.txt` exists and contains a real description (not placeholder text)
- [ ] Memory trigger test: say "please remember I prefer tabs over spaces as a test" then confirm all 4 systems respond — **test only**, not a preference to keep; delete the stored entry afterwards
- [ ] SessionStart test: close and reopen Claude Code in the project — confirm palace context and claude-mem history load automatically

### Post-verification — fill in AI_CONTEXT.md

After Phase 8 preferences are confirmed and stored, update the **Active Preferences** section
of `.claude/AI_CONTEXT.md` with the actual confirmed wording. Placeholder text here means
weaker session starts.

### Post-verification — this plan file

**[ASK USER]** "Setup is complete. This plan was fetched from a URL and doesn't need to be
kept locally. If you'd like a reference copy somewhere, I can save it — otherwise we're done."

---

## Going Forward

With setup complete, here is what a normal working session looks like:

- **Session opens** — MemPalace wake-up and claude-mem history load automatically. Claude
  arrives with context: who you are, what you were working on, what decisions were made,
  and any preferences you've stored. No re-briefing needed for established projects.

- **During work** — just work. Claude remembers your preferences without being told. If
  something important comes up that should survive beyond this session, say "please
  remember: ..." and it routes to all four systems.

- **Project changes** — if the tech stack shifts, a major decision is made, or scope
  changes significantly, Claude will proactively offer to update your identity and log
  the change. You can also ask explicitly at any time.

- **New projects** — introduce a project and Claude will initialize the full memory stack
  before starting work. Each project gets its own MemPalace wing, CLAUDE.md, and memory
  directory. Your cross-project preferences travel with you automatically.

- **Session ends** — the Stop hook writes a baseline record silently. Claude should also
  write a richer diary entry at natural breakpoints (end of a feature, before compaction).
  If you then run `/compact`, the PreCompact hook may block once asking for a save — if
  you've already saved, just say "please compact now" and Claude will prime the sentinel
  and proceed. The next session picks up with full context.

The goal is that over time, the gap between sessions stops feeling like starting over and
starts feeling like continuing.

---

## Reference

### claude-mem HTTP API (port 37777)

| Endpoint              | Method | Purpose                                           |
| --------------------- | ------ | ------------------------------------------------- |
| `/api/health`         | GET    | Check worker status + auth method                 |
| `/api/memory/save`    | POST   | Write observation: `{project, type, title, text}` |
| `/api/context/recent` | GET    | Read recent sessions: `?project=X&limit=N`        |
| `/api/projects`       | GET    | List known projects                               |
| `/api/observations`   | GET    | List observations: `?limit=N&orderBy=date_desc`   |

**Observation types:** `decision`, `bugfix`, `feature`, `refactor`, `discovery`, `change`

### Memory trigger phrases (UserPromptSubmit hook)

Fires on: _"I would like you to remember"_, _"please remember"_, _"remember that/this"_,
_"can you remember"_, _"keep (this) in mind"_, _"don't forget"_, _"note that/this"_,
_"make a (mental) note"_, _"store this/that away/in memory"_

### Four-system routing logic

| System            | When to use                                                                               |
| ----------------- | ----------------------------------------------------------------------------------------- |
| MemPalace         | Always — `mempalace_add_drawer` to the correct wing/room                                  |
| Local file memory | Always — typed `.md` file + `MEMORY.md` index entry                                       |
| CLAUDE.md         | Only for session-critical project conventions (code style, architecture, gotchas)         |
| claude-mem        | Always — `POST /api/memory/save`; fall back to transcript narration if worker unreachable |

---

_Four-system memory architecture — Claude Code_
_Source: https://github.com/AWCostabile/claude-memory-setup_
