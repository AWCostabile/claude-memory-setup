# Continuity-layer tests

Regression tests for `hooks/session-journal.sh`. Run everything with:

```bash
bash tests/run-all.sh
```

| Suite | Covers |
|---|---|
| `lifecycle-test.sh` | Dead-session lifecycle, dirty-session recovery injection (resume hint, assess-first directive), orchestration spawn + subagent harvest, manifest re-injection on compact, salvage bookkeeping |
| `retention-test.sh` | Retention rules: closed/suspended/dirty/attic transitions against fabricated journals with faked mtimes |

## Machine-specific data

Anything that varies per machine lives in **`.claude/test-machine.env`** — auto-generated
by `tests/machine-env.sh` on first run (interpreter, CLI version, worker port, platform),
gitignored because `.claude/` is machine-local by repo convention. Edit that file to
override a wrong guess; delete it to re-derive. Tests must source `machine-env.sh`
rather than probing inline, so a new machine has exactly one place to fix.

## Fixtures: committed templates, locally rendered

Nothing machine-specific is committed. `fixtures/templates/` holds **capture-derived
templates**: field names, structure, and value formats verbatim from real hook events,
with machine/session values as `{{PLACEHOLDERS}}`. `make-fixtures.sh` renders them for
the local machine into **`.claude/test-fixtures/`** (gitignored) — the lifecycle suite
re-renders on every run, so there is nothing to keep fresh by hand.

Templates being partly synthetic is a known hazard here — this project has twice been
burned by synthetic payloads that passed while production silently failed (wrong field
name; wrong tool name). Two guards keep the templates honest:

1. They are only ever *derived from real captures* (values replaced, structure never
   hand-written), with provenance in `fixtures/provenance.json`; the lifecycle suite
   warns when the machine's CLI version no longer matches it.
2. `event-shape-probe/compare-keys.py` diffs template key-sets against freshly captured
   events, so shape drift is detected mechanically rather than noticed in production.

To refresh after a CLI update changes event shapes: capture with the rig in
`tests/event-shape-probe/` (manual — it spawns real billed sessions), run
`compare-keys.py` against the captures, update the templates accordingly, and bump
`provenance.json`.
