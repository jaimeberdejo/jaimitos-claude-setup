# Experiment — Spec Kit → Jaimitos roadmap handoff

**Status: EXPERIMENTAL. Nothing here ships.** This directory is not a Jaimitos install source root
(`install.sh` reads exactly `jaimitos-os/` and `skills/`), so no file below can reach a user project.
A REJECT verdict is one `git rm -r`.

## The question

Jaimitos already turns an idea into a roadmap: `grill` → `to-spec` → `roadmap`. GitHub's
[Spec Kit](https://github.com/github/spec-kit) has a richer *specification* front-end — stable
`FR-`/`SC-` requirement IDs, `/clarify`, `/analyze`, checklists.

**Is bolting Spec Kit's front-end onto Jaimitos's execution spine worth what it costs?**

That is the only question. This experiment exists to answer it with evidence and then to say
**PROMOTE**, **REVISE**, or **REJECT**. "It works" is not the bar — `grill → to-spec` also works.

## The flow under test

```
Spec Kit feature pack → speckit-gate.sh → proposed roadmap phases (FR/SC IDs preserved)
→ a human appends them → /phase builds one → evaluator grades criteria AND requirement IDs
→ scripts/tick.sh ticks → speckit-converge.sh reports drift, and cannot tick anything
```

Jaimitos stays sole orchestrator. Spec Kit may **specify** and **report**. It may not execute, tick,
own state, or become a second queue.

## Ownership — the line that must not move

| Concern | Owner |
|---|---|
| Feature requirements, scenarios, clarification | Spec Kit feature pack |
| Feature-level design and contracts | Spec Kit `plan.md` / `contracts/` |
| Project operating policy | Jaimitos `CLAUDE.md` |
| Milestone scope | Jaimitos `docs/SPEC.md` |
| **Execution queue** | Jaimitos `docs/ROADMAP.md` |
| Current state | Jaimitos `docs/STATE.md` |
| Per-phase plan | Jaimitos `planner` |
| Implementation | Jaimitos `executor` (via `/phase`) |
| Evaluation | Jaimitos `evaluator` |
| **Completion** | `scripts/tick.sh` — and nothing else |

`specs/<NNN>/tasks.md` is **not** the roadmap. It is an input. Nothing in Spec Kit — including its own
`/speckit-implement` and `/speckit-converge` — can move Jaimitos's queue or mark work done.

## Guarantee | Enforcement

The house rule (`docs/dev/AUTHORING.md`): never claim a guarantee a test does not prove. This table
is the contract. If a row's enforcement is weaker than you hoped, that is the finding, not a bug.

| Guarantee | Enforcement |
|---|---|
| The experiment cannot ship into a user project | **Structural** — `install.sh` reads only two source roots (`test-skills.sh` check 4), plus a negative assertion in `install-smoke.sh` |
| `import-speckit` costs zero always-loaded context | **Structural + linted** — not a source root; `disable-model-invocation: true`, asserted by `test-skills.sh` check 4 |
| An import cannot mutate an existing or completed phase | **Structural** — the gate's only output shape is an *append fragment*. It has no roadmap-replacement output to emit. Byte-prefix assertion. |
| An imported phase cannot be marked done without an evaluator PASS and green evidence bound to HEAD | **Structural** — `scripts/tick.sh` is unchanged and remains the sole writer of `- [x]`. Proved against the **real** `tick.sh`. |
| An imported phase is roadmap-schema-valid | **Deterministic** — the merged roadmap is run through the **unmodified** `lint-roadmap.sh --strict` |
| An unresolved `[NEEDS CLARIFICATION]` blocks the import | **Deterministic** — grep gate, exit 1 |
| Generated text cannot forge an open task | **Deterministic** — poison-line gate (defense in depth; the underlying core defect was fixed in **v2.11.2**, not worked around here) |
| No Jaimitos file or name is silently taken over | **Deterministic** — cross-check of *both* install manifests (Spec Kit's `speckit.manifest.json` × Jaimitos's `.jaimitos-manifest`) |
| **Known** high-stakes **paths** force `Mode: supervised` | **Deterministic** — reuses the real `_high-stakes.sh`; exit 3 |
| The gate and the reports never write outside `--out` | **Deterministic code path + negative tests** — path checks, `cmp -s`, `git status --porcelain`, and no legitimate way to forge grade/evidence. **This is not a sandbox:** a shell script can write wherever its process can. |
| SC structure (present, non-empty, unique IDs) | **Deterministic** |
| **SC measurability** | **Heuristic warning + mandatory human review.** A numeric/comparator token proves a criterion *looks* measurable. It proves nothing about whether it *is*. Waivers are recorded so false positives surface. |
| High-stakes **intent** with no concrete path yet | **Model + human classification.** `_high-stakes.sh` matches paths, not intentions. |
| Phase sizing is proportionate | **Model-dependent** |
| A feature contradicts `docs/SPEC.md` | **Model-dependent + mandatory human review.** The gate *surfaces the inputs*; it does not judge. There is deliberately **no** `detects_scope_contradiction` test — a green one would be a lie. |
| The evaluator traces `Requirements:` IDs | **Model-dependent.** This *is* the go/no-go question. |
| `/speckit-implement` does not write code; upstream `/speckit-converge` does not append tasks | **Documented (prompt-level).** A preset *asks*. It cannot structurally stop a model from writing code. **The real protection is that nothing Spec Kit writes can tick a phase, and `tasks.md` is not the roadmap.** |
| Always-loaded cost of Spec Kit's 10 `speckit-*` skills in the project | **Unmeasured by any Jaimitos test.** `test-skills.sh`'s 6000 B budget iterates only *this repo's* `skills/`. Hand-measured in the dogfood. |

## What would make this a REJECT

Decided **now**, before the code exists, so the bar cannot drift to fit the outcome.

| | REJECT if |
|---|---|
| **R1** | **Context tax.** Spec Kit installs 10 skills with `disable-model-invocation: false` — every description is always-loaded in the user's project, invisible to Jaimitos's budget check, and there is **no supported way to exclude a core command**. REJECT if the *measured* end-to-end cost is disproportionate to what the handoff buys. |
| **R2** | **Preset treadmill.** Upstream ships multiple releases a day. A preset is the only sanctioned way to neuter `/speckit-implement`, and it is the most fragile artifact here. REJECT if it breaks on the next release — Jaimitos cannot own a moving target it does not control. |
| **R3** | **Two roadmaps of record.** REJECT if the two-roadmap misuse test (below) shows an agent driving work from `tasks.md`. At that point Jaimitos is sole orchestrator on paper only. |
| **R4** | **The evaluator section cannot be written Spec-Kit-agnostically.** Then it does not belong in core, the dogfood never graded the shipped evaluator, and the go/no-go is unanswerable. |
| **R5** | **The measurability gate is a nuisance.** A gate people learn to route around is worse than no gate. Measured by its false-positive rate in the dogfood. |
| **R6** | **Spec Kit adds nothing over `grill → to-spec`.** The null result. It is a perfectly good outcome and this report must be willing to state it. |
| **R7** | **`specify init` touches anything Jaimitos owns.** Checked first, before any other work. |

## The two-roadmap misuse test

R3 is the risk that documentation cannot mitigate, so it is tested behaviorally rather than asserted:

> Give a fresh agent access to **both** `specs/<NNN>/tasks.md` and `docs/ROADMAP.md` and ask:
> *"What is the next implementation task?"*
> The correct answer identifies **`docs/ROADMAP.md`** as the execution authority.

If it reaches for `tasks.md`, the ownership model is prose, not architecture.

## Layout

```
bin/speckit-gate.sh        the deterministic fail-closed gate      exit 0 / 1 / 2 / 3
bin/speckit-propose.sh     renders the default fragment + report   never edits the roadmap
bin/speckit-converge.sh    report-only drift report                exit 0 / 1 / 2 / 3
bin/speckit-footprint.sh   ownership-aware install-footprint check
footprint/                 the expected output set of the PINNED Spec Kit
fixtures/                  six feature packs (A–F) + a minimal Jaimitos project
tests/                     offline tier (always) + live/ tier (pinned CLI, network)
preset/jaimitos-handoff/   the preset that redirects /speckit-implement at /phase
```

Exit codes mirror `scripts/tick.sh` on purpose — **0** proceed · **1** refused · **2** usage ·
**3** high-stakes/supervised, caller must not auto-apply.

## Upstream, pinned

`github/spec-kit` — MIT — tag **v0.12.13**, SHA `a965413a24f127ba0bde027008b1ac6606237a41`.
Recorded in `integrations/upstreams.lock.json`. Nothing is fetched at runtime; the offline test tier
requires no network.

Two facts that most documentation (including Spec Kit's own `docs/upgrade.md`) still gets wrong:
`--ai claude` was **removed in 0.10.0** (it is `--integration claude`), and the Claude integration is
**skills-mode** — it writes `.claude/skills/speckit-<cmd>/SKILL.md`, *not* `.claude/commands/`.

## Verdict

Written to `REPORT.md` at the end, as exactly one of:

```
PROMOTE TO OPTIONAL INTEGRATED PROFILE
REVISE AND DOGFOOD AGAIN
REJECT AS INSUFFICIENT VALUE
```

Not promoted automatically. Not merged into `master` unless the verdict is PROMOTE.
