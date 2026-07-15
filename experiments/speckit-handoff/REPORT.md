# Spec Kit handoff — findings and go/no-go

**Status: COMPLETE.** Deterministic suite, live-CLI checks, and a full end-to-end dogfood on a real
feature are all done. Everything below is measured, not estimated; live-CLI numbers say so.

**Verdict: REJECT AS INSUFFICIENT VALUE** — as a promoted/installed profile. The one genuinely
valuable thing the dogfood proved (independent requirement-id traceability) is **separable from Spec
Kit** and cheaper to get natively; Spec Kit's costs are permanent and not opt-out-able. The adapter
stays exactly where it is — experimental, unshipped — as an opt-in bridge for a team already invested
in Spec Kit, not promoted. The separable win should be extracted to core on its own merits (below).

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
| **R6** | Beats `grill → to-spec`? | **NO — the value is separable** | Dogfooded end-to-end on a real feature (below). Spec Kit's one out-of-the-box advantage — stable FR/SC ids that an independent evaluator traced to code+tests — is delivered by the *tool-agnostic* evaluator section, which works with any `Requirements:` block. `grill/to-spec/roadmap` could emit stable ids and get the identical benefit at **zero** extra always-loaded cost. Spec Kit's costs (below) are permanent and buy nothing native can't. |
| **R7** | `specify init` footprint | **PASS (live CLI)** | On the real dogfood project: 31 paths changed, all 31 claimed by Spec Kit's manifests; `docs/ROADMAP.md`, `.claude/skills/*` (the 18 Jaimitos skills), and the Jaimitos manifest all intact. The `.claude/skills/` co-location is safe: `--force` merges, the integration writes only `speckit-*` subdirs. |

## The dogfood (R6, end to end on a real feature)

Feature: **account data export & deletion** — chosen for a guaranteed high-stakes slice (deletion)
and genuine FR/SC structure. Disposable project, Jaimitos installed, real pinned Spec Kit CLI + the
preset. Full flow, every step run for real:

1. **Authored** via the real Spec Kit workflow (`create-new-feature.sh` + the real templates): a
   `spec.md` with `FR-001..006`, `SC-001..003`, clarifications resolved.
2. **Handoff.** The mechanical proposer produced **one supervised phase** (exit 3 — `delete.py` makes
   the whole pack high-stakes). The `import-speckit` skill then applied judgement the gate cannot:
   **split** into an export phase (loopable, `FR-001/002/003` + `SC-001`) and a deletion phase
   (supervised, `FR-004/005/006` + `SC-002/003`), attributing ids honestly. The split fragment passed
   the real `lint-roadmap.sh --strict`.
3. **Built** the export phase via TDD — real `src/accounts/export.py` + `tests/test_export.py`, red
   then green, wider suite clean.
4. **Graded independently.** A fresh evaluator subagent running the *shipped* `evaluator.md` traced
   **all four** claimed ids to specific code lines and passing tests, graded only the ids the phase
   claimed, even caught that `FR-003`'s `events` case was untested — and returned **PASS**. This is
   the load-bearing result: a requirement id written in the spec survived the handoff and was
   independently verified against the implementation.
5. **Ticked** by the real `scripts/tick.sh`. Instructive friction: the `src/accounts/` path is
   high-stakes (`accounts` is an auth-adjacent token), so even the read-only export phase required the
   pre-phase allowlist + `start-phase.sh` anchor ceremony — the adapter's "loopable" judgement could
   **not** weaken the gate. The ownership model held exactly as designed.
6. **Deletion phase** stayed supervised and unbuilt.
7. **Convergence** reported `covered=9 missing=0 drift=0 frozen=0`, exit 0, mutating nothing — after
   the dogfood surfaced and fixed a real false-positive in the frozen check (it compared paraphrased
   labels instead of the spec's import hash; now it stamps `spec.md@<hash>` and compares that).

### The decision, with the measured numbers

| | Spec Kit path | `grill → to-spec` (native) |
|---|---|---|
| Stable requirement ids, evaluator-traced | **yes** (proved end-to-end) | not out of the box — *but the tool-agnostic evaluator section gives it to any `Requirements:` source* |
| Always-loaded context | **~268 tokens every turn**, 10 skills, **no opt-out** | **0 additional** (grill/to-spec/roadmap already in the 5035 B budget) |
| On-disk footprint | **+140 KB `.specify/` tree, 22 files** | none |
| Artifact homes for "the plan" | **4** (`spec.md` + `plan.md` + `tasks.md` + `ROADMAP.md`) | **2** (`docs/SPEC.md` + `docs/ROADMAP.md`) |
| Override mechanism | a preset whose schema I got wrong **3 ways** (R2) | native, no override needed |
| Ceremony to complete a phase | init → preset → author → import → gate → append → allowlist → anchor → build → grade → tick | grill → roadmap → /phase |

**The separability point is the whole verdict.** The valuable capability — a stable id, written once,
traced independently to code — is delivered by the ~10-line evaluator section, which names no tool
and fires on any `Requirements:` block. Teaching `grill`/`to-spec`/`roadmap` to emit `FR-`/`SC-` ids
into that block would reproduce the entire benefit at zero standing context cost, with two artifact
homes instead of four, and no preset to chase across Spec Kit's daily releases.

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

## Verdict

```
[ ] PROMOTE TO OPTIONAL INTEGRATED PROFILE
[ ] REVISE AND DOGFOOD AGAIN
[x] REJECT AS INSUFFICIENT VALUE   — as a promoted/installed profile
```

The experiment succeeded: it held its ownership boundaries under real load (R3/R4/R7 pass, the tick
monopoly never broke, completed history was never rewritten), and it produced a genuinely useful
capability. But the useful capability is **not Spec Kit**. It is the tool-agnostic
requirement-traceability in the evaluator, and it is separable, cheaper, and native-friendly.

Promoting the adapter to an installed profile would make every user pay ~268 tokens every turn, a
140 KB tree, four artifact homes, and a preset that must be chased across Spec Kit's multiple-daily
releases — to obtain a benefit that grill/to-spec/roadmap could deliver for nothing by emitting
stable ids. That trade is not worth it for the common case. **Do not promote.**

### What to do with the pieces

1. **Extract the win to core, on its own merits.** The evaluator's requirement-traceability section
   is worth keeping as a *core* feature — but justified as core, with its own version bump, CHANGELOG
   entry, and independent review, NOT smuggled in as experiment fallout. Pair it with a small change
   to `grill`/`to-spec`/`roadmap` so they emit `FR-`/`SC-` ids into a `Requirements:` block. That
   gives Jaimitos the traceability payoff with none of Spec Kit's cost. (This is the "alternative"
   the plan named. Until then, the section stays on this branch and does not merge.)
2. **Keep the adapter experimental and opt-in.** For a team already invested in Spec Kit, this is a
   working bridge that lets them keep their specs and still get Jaimitos orchestration. It should stay
   in `experiments/`, unshipped, available to those who explicitly want it — never installed by
   default.
3. **If Release 3 revisits this,** the two things to re-check first are R1 (has upstream added a way
   to exclude a core command / opt a skill out of always-loaded context?) and R2 (has the preset
   schema stabilised?). Both are upstream-dependent and both counted against promotion here.

### Residual risks, unchanged by the dogfood
- **R1** and **R2** are the reasons above; both are upstream's to fix, not Jaimitos's.
- **R5** (the measurability heuristic) behaved acceptably — it surfaced `SC-003` as a false positive
  exactly as designed, visibly, without blocking. Not a factor in the verdict.
- The `accounts/`-path friction (step 5) is Jaimitos core behaving correctly, not an adapter defect —
  but it does mean the adapter's per-phase mode judgement is advisory: `tick.sh` has the final say.
