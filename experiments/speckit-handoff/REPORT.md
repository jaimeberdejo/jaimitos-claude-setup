# Spec Kit handoff — findings and go/no-go

**Status: DRAFT.** The deterministic suite and the empirical (live-CLI) checks are complete. The one
thing still outstanding is the full end-to-end value comparison against `grill → to-spec` (R6) — the
question that ultimately decides PROMOTE vs REJECT. Everything below is measured, not estimated;
where a number came from the real pinned CLI it says so.

## Upstream

`github/spec-kit` — MIT — tag **v0.12.13**, SHA `a965413a24f127ba0bde027008b1ac6606237a41`.
Recorded in `integrations/upstreams.lock.json`. Nothing is vendored; the offline test tier needs no
network.

Two facts most documentation (including Spec Kit's own `docs/upgrade.md`) still gets wrong, both
confirmed against the running CLI: `--ai claude` was **removed in 0.10.0** (it is
`--integration claude`), and the Claude integration is **skills-mode** — it writes
`.claude/skills/speckit-<cmd>/SKILL.md`, not `.claude/commands/`.

## Capability adoption

| Spec Kit capability | Verdict | Why |
|---|---|---|
| `specify` / spec.md (FR-/SC- ids) | **ADOPT (format only)** | Stable requirement ids are the whole reason to do this. We adopt the id *convention*, not the text. |
| `clarify` ([NEEDS CLARIFICATION]) | **ADOPT (as a gate input)** | An unresolved clarification blocks the handoff. |
| `plan` / `tasks` / `checklist` | **ADOPT (as sources)** | Cited on the phase's `Sources:` line; read by the evaluator. |
| `analyze` | **REFERENCE** | Useful pre-handoff; not wired in. |
| `constitution` | **REFERENCE** | Overlaps Jaimitos `CLAUDE.md`; not adopted to avoid two policy homes. |
| `converge` (upstream) | **ADAPT → report-only** | Upstream appends tasks to `tasks.md`; ours reports and mutates nothing. |
| `implement` | **REJECT (guarded)** | Would be a second executor. Redirected by preset at `/phase`. |
| `taskstoissues` | **REJECT (out of scope)** | Not part of the integrated flow. |

## The go/no-go criteria, as they actually stand

| | Criterion | Status | Evidence |
|---|---|---|---|
| **R1** | Always-loaded context tax | **MEASURED — modest but real** | 10 `speckit-*` skills, `disable-model-invocation: false`, **1193 B / ~298 tokens every turn**, in the user's project, invisible to `test-skills.sh` check 6, with no supported way to exclude a core command. For scale: Jaimitos's *entire* model-invoked budget is 5035 B, so Spec Kit adds ~24% on top, permanently. Not a REJECT on its own; a standing cost to weigh against value. |
| **R2** | Preset treadmill | **WORKS, BUT FRAGILE — the finding stands** | The preset installs against the pinned CLI (`preset add --dev`) and genuinely replaces `speckit-implement`'s body with the `/phase` redirect (`source: preset:jaimitos-handoff`, no unresolved placeholders). BUT my inferred schema was wrong three ways (missing `schema_version`, wrong nesting, `path` vs `file`) and had to be corrected against the live CLI. It works *today, at v0.12.13*. It is the single most fragile artifact here, and upstream ships several releases a day. |
| **R3** | Two roadmaps of record | **PASS** | A fresh agent handed BOTH `tasks.md` and `docs/ROADMAP.md` correctly named the roadmap as the execution authority, recognised `tasks.md` as an upstream input (it is cited under `Sources:`), and refused the decoy tasks `tasks.md` listed but the roadmap did not import. The ownership model holds behaviourally, not just on paper. |
| **R4** | Evaluator section stays tool-agnostic | **PASS** | The shipped evaluator's requirement-traceability section fires only when a phase declares `Requirements:`, is written for any external requirements source, and names no tool. `test-docs-invariants.sh` asserts both the conditional wording and the absence of "speckit"/"spec kit". Verified inert in a default install (byte-identical evaluator, no shipped template carries `Requirements:`). |
| **R5** | Measurability heuristic is a nuisance | **MITIGATED, cost visible** | It warns and flags for human review; it never refuses. Its known false positive ("the endpoint is idempotent" — measurable, no digit) is surfaced in the handoff report by design, so the cost is not hidden. Whether it is a *net* nuisance is a judgement the dogfood should record. |
| **R6** | Beats `grill → to-spec`? | **NOT YET ASSESSED** | The deciding question. Needs a real feature run through both paths, compared on spec quality, phase quality, and total context cost. This is the remaining work. |
| **R7** | `specify init` footprint | **PASS (live CLI)** | `specify init --here --integration claude` touched nothing Jaimitos owns — `docs/ROADMAP.md`, `.claude/skills/*`, and the manifests all intact. The `.claude/skills/` co-location is safe: `--force` merges, and the integration writes only `speckit-*` subdirs. |

## Architecture

A deterministic gate (`speckit-gate.sh`, exit 0/1/2/3 mirroring `tick.sh`) validates a feature pack
and any proposed roadmap fragment; `speckit-propose.sh` renders the default fragment + a review
report; `speckit-converge.sh` reports drift read-only with meaningful exit codes;
`speckit-footprint.sh` cross-checks both toolkits' install manifests and measures the context tax.
The `import-speckit` maintainer skill drives the flow and carries every human-review item forward.
The gate reuses the *real* core scripts (`lint-roadmap.sh`, `_roadmap.sh`, `_high-stakes.sh`,
`tick.sh`) rather than re-implementing them — that reuse, tested against the unmodified scripts, is
the whole compatibility claim.

## What is proven vs asked (the honest split)

**Structural / deterministic (proven):** the experiment cannot ship (`install.sh` + install-smoke);
an import cannot rewrite an existing or completed phase (append-only fragment; byte-prefix); an
imported phase cannot reach "done" without an evaluator PASS + green evidence (the real `tick.sh`
refuses); generated text cannot forge an open task (v2.11.2 fix + poison gate); no Jaimitos file or
name is silently taken over (manifest cross-check); known high-stakes paths force `supervised`
(the real `_high-stakes.sh`).

**Prompt-level (asked, not enforced):** the preset asks `/speckit-implement` not to write code — it
cannot stop a model. The real protection is that nothing Spec Kit writes can tick a phase, and
`tasks.md` is not the roadmap.

**Model / human judgement (unprovable by a test, and labelled so):** phase sizing, `Done when:`
observability, whether an SC is genuinely measurable, high-stakes *intent* with no path, and scope
contradiction vs `docs/SPEC.md` (deliberately surfaced, never auto-judged — there is no
`detects_scope_contradiction` test because a green one would be a lie).

## Preliminary lean (NOT the verdict)

On the evidence so far the ownership boundaries hold and nothing is a hard REJECT — R3/R4/R7 pass,
R1/R2/R5 are real costs that are measured and contained rather than fatal. The verdict turns entirely
on **R6**: if Spec Kit's specification front-end produces materially better requirements than
`grill → to-spec` for a real feature, the ~298-token standing tax and the preset fragility are a
reasonable price, and this is **REVISE AND DOGFOOD AGAIN** heading toward PROMOTE. If it does not,
the tax and fragility buy nothing and it is **REJECT AS INSUFFICIENT VALUE**. That comparison has not
been run yet, so **no verdict is recorded here.**

```
[ ] PROMOTE TO OPTIONAL INTEGRATED PROFILE
[ ] REVISE AND DOGFOOD AGAIN
[ ] REJECT AS INSUFFICIENT VALUE
```
