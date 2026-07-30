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

## Fixtures

`fixtures/` holds **real captured hook payloads** — not synthetic ones. This project has
twice been burned by synthetic payloads that passed while production silently failed
(wrong field name; wrong tool name), so fixtures are only ever produced by capturing
real events. Provenance (CLI version, platform, capture date) is recorded in
`fixtures/provenance.json`; the lifecycle suite warns when the machine's CLI version no
longer matches it.

To regenerate fixtures after a CLI update changes event shapes, use the capture rig in
`tests/event-shape-probe/` (manual — it spawns real billed sessions), then update
`provenance.json`.
