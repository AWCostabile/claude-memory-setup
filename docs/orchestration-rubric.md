<!-- ORCHESTRATION-RUBRIC:v1 (managed by claude-memory-setup/scripts/install-orchestration.sh — edit the canon in that repo, not this block) -->
## Subagent routing (standing policy)

When delegating implementation work to subagents, pick the agent type by task
complexity and say which you chose in one line — don't ask:

| Type | Model/effort | Use for |
|---|---|---|
| implementer-deep | opus/high | design-sensitive builds, unfamiliar territory, cross-cutting changes |
| implementer | opus/medium | standard well-scoped feature work |
| mechanic | sonnet/low | mechanical edits: renames, scaffolds, doc sync, config churn |

Memory posture is the third routing axis — reads are routed, writes are always-on
(every agent ends with a harvested `## Insights` block):

- **paste** (default; always for mechanic): inject the 2–3 relevant facts you already
  hold into the spawn prompt. No `MEMORY CHECK:` line means the agent will not search.
- **targeted**: add one `MEMORY CHECK: <topic>` line when a specific unknown is worth
  one search on the subagent's disposable context window.
- **full**: for implementer-deep in territory with real recorded history — tell it to
  sweep the project wing and recent observations before designing.

Model may be overridden per-call on the Agent tool; effort rides the agent type
(there is no per-call effort knob — use the Workflow tool if a one-off tier is needed).
<!-- /ORCHESTRATION-RUBRIC:v1 -->
