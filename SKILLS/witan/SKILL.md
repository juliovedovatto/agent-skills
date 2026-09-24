---
name: witan
description: convene a council of N oracle subagents to advise on a single subject, each running on a distinct model — the oracle agent's primary model plus its additional council models. Use when you want several independent model perspectives on a decision, question, or direction instead of one. Trigger phrasings include ask the council, convene the witan, ask the wise men, get multiple oracle opinions, what do the oracles think.
---

# Witan

The witan (Old English: *wītan*, "wise men") was the king's council in Anglo-Saxon England from before the 7th century until the 11th century. This skill convenes a council of N `oracle` subagents — one per distinct model available to the oracle agent — so a subject is weighed by multiple independent model perspectives in parallel.

**N is dynamic:** the pool is the oracle agent's primary model (from its agent config) plus the additional models declared in step 1. If either changes, N adjusts.

## Before you run — confirm intent

Spawning the witan runs N oracles in parallel (N× the cost and time of a single oracle). Before convening the council, **confirm with the user that they really want it** unless the invocation was explicit (e.g. `/skill:witan ...`, "use the witan skill", "convene the witan on ..."). A brief one-line check is enough: "Convene the witan (N oracles: <primary> + <additional models>) on this?" Proceed only after a yes.

## How to run

### 1. Discover the model pool

pi-subagents no longer carries per-agent fallback model config, so the pool comes from two sources:

1. **Primary model** — read the oracle agent's config and take its `Model:` field:

```typescript
subagent({ action: "get", agent: "oracle" })
```

2. **Additional models** — the `oracle` agent's fallback list, in order.

Pool = primary plus additional models, deduped. Its length is **N**.

### 2. Convene the council

Spawn N `oracle` subagents in parallel — one task per distinct model — each pinned to its model via the per-task `model:` override, all given the exact same subject.

**Each oracle task MUST be marked advisory** or the harness mislabels a clean verdict as "failed": the oracle is read-only by contract, but its tool list includes `bash` (a mutation-capable tool), and the completion guard treats any implementation-flavored task that produces no edits as a failure. Two controls, both required and both dispatch-side:

1. **`acceptance: { level: "none", reason: "advisory oracle council review; no file edits expected" }`** on every task — disables acceptance evaluation (correct for a read-only verdict with nothing to verify). Acceptance and the completion guard are independent; setting `acceptance: none` alone does NOT stop the guard.
2. **Prepend a read-only preamble** containing the phrase `review only` (and a blanket `do not edit any files` as backup) so the task-intent classifier resolves to `read-only` instead of `implementation` and the completion guard does not fire.

> *Rationale: the oracle's tool list includes `bash` (a mutation-capable tool), and the completion guard treats any implementation-flavored task that produces no edits as a failure. The ideal fix would be `completionGuard: false` on the oracle agent config (via eject), but that requires modifying the builtin. This dispatch-side workaround covers the witan use case without agent config changes. If `REVIEW_ONLY_PATTERNS` changes in a future pi-subagents version, the preamble wording may need updating.*

```typescript
const advisoryPreamble = "Review only — do not edit any files. Return your verdict as findings only.\n\n";
subagent({
  tasks: [
    // participant 1: no model override — runs on the agent's configured primary
    { agent: "oracle", task: advisoryPreamble + "<the subject>", acceptance: { level: "none", reason: "advisory oracle council review; no file edits expected" }, context: "fresh" },
    { agent: "oracle", model: "<additional-1>", task: advisoryPreamble + "<the subject>", acceptance: { level: "none", reason: "advisory oracle council review; no file edits expected" }, context: "fresh" },
    { agent: "oracle", model: "<additional-2>", task: advisoryPreamble + "<the subject>", acceptance: { level: "none", reason: "advisory oracle council review; no file edits expected" }, context: "fresh" }
    // ...one task per distinct model in the pool
  ],
  concurrency: N
})
```

Use the exact subject the user provided, prepended with the identical advisory preamble, as every task. Keep every task identical so differences in output reflect model reasoning, not prompt variation. The preamble is constant across all council members, so it introduces no cross-model variance.

### 3. Synthesize the verdict

Gather all N oracle verdicts. Use the **diversity of independent perspectives to decide the best path** — the value is the disagreement between models, not a vote. Concretely:

- Extract where the models **agree** (consensus = high-confidence signal).
- Extract where they **diverge** (the interesting zone — the best answer often combines parts from different models).
- Synthesize a single recommended course, **freely combining parts** from different oracles when a model is stronger on one dimension than another. You are the decider; the council advises.
- Surface irreducible disagreements and your reasoning for the path you chose.

**If the synthesis is still inconclusive** (models fundamentally split and no defensible best path emerges), spawn the witan again — re-run step 2 with the prior findings and the specific unresolved question as the subject — to get a second-opinion pass, then synthesize again. Stop after the second pass and present the best defensible path with the remaining uncertainty called out plainly.

## Notes

- Each oracle runs with **fresh** context, never forked — every council member starts clean, seeing only the subject and preamble in its task; only the model differs. Forked context has failed in practice: a member echoed parent-session state back instead of answering the subject.
- `model:` ids are lenient: case, separator variants (`-` vs `.`), and trailing date stamps all resolve to the same registry model.
- If a model fails (provider, quota, or billing error), retry only that single task before reporting. Only surface a missing voice if that model has no working alternative.
