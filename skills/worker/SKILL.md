---
name: worker
description: Route batchable coding tasks to a subagent worker on the most cost-efficient model. Use when delegating implementation work (features, bug fixes, refactors, test scaffolding) and model cost matters. OpenCode: live pricing via the models tool. Claude Code: provider tier aliases via the Task tool.
---

# Worker

Delegate batchable implementation work to a subagent (worker) on the cheapest model that can do it well. The orchestrator keeps the spec, the verification, and the escalation.

## When to use

- Batchable, verifiable implementation tasks: features, bug fixes, refactors, test scaffolding, boilerplate, lint fixes.
- Not for exploratory or interactive work — that stays on the current model.

## 1. Tier the task

| Tier | Criteria | Examples |
|------|----------|----------|
| T1 | Mechanical, unambiguous spec, verifiable by tests or lint | Renames, formatting, boilerplate, straightforward test additions, dependency bumps, lint fixes |
| T2 | Localized change, clear spec, known test command | Single-file bug fix, small feature with a defined scope |
| T3 | Cross-cutting, architectural, ambiguous spec, or security-relevant | Multi-module refactor, API design, anything touching auth or data |

When in doubt, go one tier up.

## 2. Resolve the model

**OpenCode** (dynamic, live pricing):

1. Call the `opencode.models` tool once per session. Drop non-active models.
2. Effective cost: `0.7 × input + 0.3 × output` (USD per 1M tokens; typical agentic read/write ratio).
3. Map tiers:
   - T3 → the current session model.
   - T1 → the cheapest active model.
   - T2 → the priciest active model with effective cost ≤ 60% of the current model's; if none, the current model.
4. Pass the full `providerID/modelID` to the subagent's `model` parameter.

**Claude Code** (tier aliases):

- T3 → `inherit` (current model).
- T2 → the provider's mid tier (e.g. Anthropic: `sonnet`).
- T1 → the provider's low tier (e.g. Anthropic: `haiku`).
- If the tier mapping is unclear for the active provider, use `inherit`.
- Pass via the Task tool's `model` parameter.

## 3. Dispatch

The worker prompt must contain:

- The task spec: what to build or fix.
- The areas/files to touch, and the areas not to touch.
- Acceptance criteria: the observable definition of done.
- The test command(s) to run.
- "Run the tests until green, then report the changes made and the test results."

## 4. Verify and escalate

- The worker's report is a claim, not a fact: review the diff yourself and re-run the tests yourself.
- On failure (review or tests): re-dispatch one tier up, once, with the failure context in the new prompt.
- Two escalations → stop and report to the user what was tried.
- Never re-dispatch to a cheaper model after a failure.

## Guardrails

- T1 never touches security, auth, credentials, payments, or migrations.
- One worker per logical change; never parallelize workers on the same area.
- When no cheaper model qualifies, `inherit` is the right answer — savings are optional, correctness is not.
