# PLAN — v2.16.0: Consistency, Proportionality & Release Proof

> **Branch:** `release-6-consistency-proportionality` (from `master` @ `41677d4`, annotated tag `v2.15.0`,
> `VERSION=2.15.0`). **Target:** `VERSION=2.16.0`.
> **No push, no tag, no PR, no merge, no branch/worktree delete, no history rewrite, no destructive reset,
> no unattended autopilot.** Bumping VERSION / tagging is its own operator checkpoint.
> **Plan artifact (tracked):** this file — committed as commit 0.
>
> **Baseline recorded on `41677d4` (this branch's base):** clean tree; fully pushed (`origin/master == HEAD`);
> `run-guard-tests.sh` all green; `release-check --prepare` exit 0 (2 warnings — `v2.15.0` tag exists in
> prepare mode; grandfathered untagged historical releases — 0 errors); `CLAUDE.md` **3140 B**; model-invoked
> skill descriptions **5173 B / 6000 B**; agent descriptions **1215 B / 2000 B**; **total always-loaded 9528 B**;
> 107 tracked installable files (`jaimitos-os/` + `skills/`); 28 installed `test-*.sh`.
>
> **Baseline correction:** the release brief and prior maintainer memory both said the newest annotated tag
> was `v2.14.0` / that `v2.15.0` was "not tagged". Ground truth on the live repo: **`v2.15.0` is an annotated
> tag on `41677d4` == `origin/master` == HEAD.** Target `v2.16.0` is free; no tag is overwritten.

---

## Context

v2.16.0 is a **correction and simplification** release — not a framework expansion. v2.15.0 deleted the
enforcement + UAT ledgers (ADR-008: no producer, template, or caller) and deferred a release-audit layer.
This release finishes that cleanup and closes the preconditions v2.15.0 named, for a *smaller, more
internally consistent, better-proven* setup.

## Objectives
- **OBJ-1601** — remove deleted-ledger operational residue.
- **OBJ-1602** — align active documentation with actual implementation.
- **OBJ-1603** — make update and manual-install guidance safe and complete.
- **OBJ-1604** — validate workflow tier use; prevent silent under-classification.
- **OBJ-1605** — make STANDARD plan review proportionate.
- **OBJ-1606** — reduce unnecessary installed footprint where safe.
- **OBJ-1607** — reproduce complete runtime and portability evidence.
- **OBJ-1608** — prepare a clean, independently reviewed release candidate.

## Non-goals (deferred to v2.17 or rejected)
`RELEASE_AUDIT` mode · findings-severity file format · review-pack generator · external review adapters ·
expanded multi-action `/wrap` dashboard · wave entities · release-state DB · a new UAT/enforcement ledger ·
completion attestations · telemetry · model routing · ticket export · a new permanent agent · another
spec/roadmap/completion format or gate.

## Non-negotiable architecture (preserved)
Four permanent agents (Researcher, Planner, Executor, Evaluator). `scripts/tick.sh` is the sole writer that
flips `- [ ]` → `- [x]`. Human is the sole publication authority (no auto merge/push/PR/tag/release/
branch-delete/worktree-delete; no destructive reset). No external-framework runtime. No new canonical
artifact; one author per owned artifact.

---

## Affected files & change ownership (one owner per file; edits sequenced to avoid overlap)

| Milestone | Owns (writes) | Shared / read |
|---|---|---|
| M1 residue | `classify-work.sh`, `.claude/agents/evaluator.md`, `.claude/agents/planner.md`, `toolkit-docs/CONTROL-PLANE.md` (residue-only pass), `toolkit-docs/GUIDE.md` (residue-only line), `skills/mapme/SKILL.md`, `docs/SPEC.md` (wording), `scripts/test-docs-invariants.sh` | the removal-note lines in README/CHANGELOG/ADRs (read, not edited) |
| M2 docs | `toolkit-docs/CONTROL-PLANE.md` (authority/version refresh), `toolkit-docs/GUIDE.md` (dedup/link), `README.md`, `jaimitos-os/SCAFFOLD.md`, `scripts/test-sync.sh`, `.github/scripts/install-smoke.sh` | `skills/README.md` (count source, read) |
| M3 routing | **new** `scripts/plan-review-route.sh`, `.claude/commands/phase.md`, **new** `scripts/test-plan-review-route.sh`, `scripts/run-guard-tests.sh` (register test) | `.claude/lib/_high-stakes.sh`, `_test-cmd.sh`, `check-plan-freshness.sh` (read/compose) |
| M4 footprint | `install.sh`, `scripts/sync.sh`, `.github/scripts/install-smoke.sh`, `.github/workflows/ci.yml`, `jaimitos-os/.github/workflows/jaimitos-os-ci.yml`, `.claude/lib/_requirements.sh` + `_roadmap.sh` (mode only), `jaimitos-os/SCAFFOLD.md` | manifest/doctor (read; no edit needed) |
| M5 evidence | **new** `docs/dev/audits/RELEASE-CANDIDATE-v2.16.0.md` | all suites (run, not edited) |
| M6 release | `VERSION`, `CHANGELOG.md`, `README.md`, `SECURITY.md`, `SCAFFOLD.md`, `CONTROL-PLANE.md`, `GUIDE.md`, `skills/README.md`, `docs/dev/AUTHORING.md`, **new** `docs/decisions/ADR-009…`, `ADR-010…` | — |

`CONTROL-PLANE.md` and `install-smoke.sh` are touched by more than one milestone — handled in sequence
(M1 residue-only edits land before the M2 authority refresh; M4 install-smoke assertions land after M2's).

---

## Implementation sequence (small commits; each leaves its targeted tests green)
0. `docs(plan)` — this file. Run Evaluator **PLAN_CHECK** before implementation; resolve any `PLAN_FAIL`.
1. `fix(docs): remove deleted-ledger operational residue` — the 11 confirmed hits + "formal UAT" wording.
2. `test(docs): guard active surfaces against removed systems` — widen `test-docs-invariants.sh`.
3. `fix(docs): align control-plane and guide authorities` — CONTROL-PLANE version/authority refresh; GUIDE links.
4. `fix(install): correct safe update and manual skill guidance`.
5. `test(sync): extend upgrade and project-ownership fixtures`.
6. `feat(phase): make STANDARD plan review risk-proportionate` — `plan-review-route.sh` + `/phase` 4b.
7. `test(phase): cover tiny, clear-standard, risky-standard, deep, invalid-tier routing`.
8. `chore(install): gate full test suite behind --with-tests (--with-ci implies)`.
9. `test(ci): assert explicit Linux non-root behavior`.
10. `test(mutation): add focused non-vacuity checks`.
11. `docs(release): record guarantees, migration and evidence`.
12. `chore(release): version and changelog for v2.16.0`.

## Test strategy
Every fix carries a regression fixture; **every fixture asserts its own precondition** so it cannot pass
vacuously (the v2.15.0 discipline). New suites register in `run-guard-tests.sh` TESTS[] so the drift guard
enforces coverage. Install/sync behavior proven by `install-smoke.sh` + `test-sync.sh`. Routing proven by
`test-plan-review-route.sh` (TINY/clear-STANDARD/risky-STANDARD/DEEP/supervised/invalid-tier + high-stakes
override + reasonless-override visibility).

## Mutation-test strategy (focused, no framework)
Revert-the-fix / flip-the-boundary against: `record-grade.sh` (PASS / PLAN_* reject / NO_TESTS_OK token),
`tick.sh` (schema `1|2`), `check-plan-freshness.sh` (sha regex, 64KB boundary), the new route table +
`_high-stakes` rc handling, doc invariants (a reintroduced phrase fails), install skill-manifest checks,
`release-check` version/tag. Each mutation must make a *named* test fail; each fixture proves it is non-vacuous.

## Migration strategy
All changes are additive or corrective; legacy projects unaffected. The footprint change is an installer
gate (default install ships fewer files; `--with-tests`/`--with-ci` restore the full suite); existing
manifest-managed projects pull it via `sync.sh` normally. Lib-mode normalization is mode-only. Document the
default-vs-full test split and the `sync.sh` update path in the shipped `SCAFFOLD.md`.

## Documentation strategy
One responsibility per doc (README=purpose/arch/quickstart; SECURITY=trust/residual-risk; SCAFFOLD=what
installs; CONTROL-PLANE=authority + workflow; AUTHORING=guarantees; GUIDE=detailed usage). Reduce only
already-drifted duplication; GUIDE links to CONTROL-PLANE rather than restating. Guarantee table reclassifies
the now-enforced tier-validation + proportional-review rows honestly (deterministic where a script enforces;
model/human where judgement remains).

## Context-budget target
No new permanent agent; no new always-loaded workflow (`plan-review-route.sh` is a script, `/phase` a
command — both load on demand). Net always-loaded growth ≤ **250 B** (aim ≤ 0 by offsetting removals).
Measure `CLAUDE.md` + skill descriptions + agent descriptions before/after.

## Rollback strategy
Additive commits revert cleanly. The routing change is confined to `plan-review-route.sh` + `phase.md`
(+ its test). The footprint change is an installer gate (revert = ship all tests again). No destructive git.

## Release criteria
See the release gate in the working plan: Consistency · Proportionality · Architecture · Verification ·
Leanness — all must hold, on the final commit, with commit-bound evidence and at least one non-author
independent review.

## Rejected alternatives
- **Prose-only proportional review** (no script) — rejected: cannot deterministically prevent silent
  under-classification; hard to prove non-vacuous. Chose a deterministic route helper.
- **Extend `classify-work.sh` with a route line but keep the model-judgment gate** — rejected: the gate,
  not the classifier output, is where under-classification happens; the helper must run at the gate.
- **Keep all 28 test scripts installed** — rejected against release theme #5 (reduce footprint); chose
  gating the suite behind `--with-tests` (`--with-ci` implies it) while preserving local validation.
- **Wire a UAT/enforcement gate into `release-check.sh`** — rejected (ADR-008): a green gate over an
  artifact nothing produces is the exact fail-open this release removes.
- **Tie the test suite only to `--with-ci`** — rejected: a user wanting local validation without CI would
  be forced to also take the CI workflow; a dedicated `--with-tests` (implied by `--with-ci`) is cleaner.

---

## PLAN_CHECK (pre-implementation, independent) — PASS_WITH_WARNINGS
An independent Evaluator PLAN_CHECK verified the seams against the real code, confirmed all invariants
(four agents, `tick.sh` sole completion, human sole publication, no v2.17 non-goal, no new agent/gate/
artifact, baseline corrected against ground truth), found **no blocking failures**, and raised six
under-specifications to resolve while executing. Resolutions:

1. **`plan-review-route.sh` contract (M3).** Specify inputs/outputs/exit codes/route table *before* writing.
   (a) `_test-cmd.sh` must earn its place in a routing-*depth* decision or be dropped — it stays only as a
   "verification-strategy-exists" clear-STANDARD check, not a depth signal. (b) One author for "tier →
   workflow" (`classify-work.sh`, authoring-time); the route helper owns only *gate routing* at 4b and must
   **not** re-emit classify-work's "Required workflow" text. (c) Fail directions: unknown/invalid tier →
   `FULL_PLAN_CHECK` (fail-safe); `_high-stakes.sh` **rc 2 → fail-closed to FULL** — call it directly and
   read `$?` (never `x=$(high_stakes_match …)`, which command-substitution swallows the rc-2 distinction).
2. **Honest tier guarantee (M3/M6).** At 4b no code exists; the deterministic signal is the plan's
   **declared** `## Change ownership` paths (a path matcher), so a TINY that omits the high-stakes path is
   not caught. The AUTHORING row must read "deterministic over the *declared* tier + planned-file list",
   never over the implementation — or it repeats the overstated-enforcement pattern this release removes.
3. **Prove the ordinary path is not heavier (M3).** Add a test that a clear-TINY phase runs only the fast
   deterministic check and dispatches **no** evaluator subagent, and that the helper never upgrades
   clear-TINY absent a real risk signal. Preserve 4b's channel-separation paragraph — the route output
   must not feed `record-grade.sh` or emit a gradeable token.
4. **M4 must FIX install-smoke's existing assertions, not only add.** Gating the suite breaks the default
   positive assertions at `install-smoke.sh:54-66` (test-models/sync/tick/test-cmd present) and the
   installed-tree `test-hooks.sh` run — make those conditional on a `--with-tests` install, add a negative
   "test-*.sh absent by default" assertion + a `--with-tests` positive.
5. **Declare commit #10's file scope.** Mutation targets live in existing suites (`test-tick.sh` holds the
   grade tests — there is no `test-record-grade.sh`; `test-stale-plan.sh`, etc.). Prefer extending existing
   suites (no new registration); any new suite registers in `run-guard-tests.sh` (shared with M3).
6. **Sequence #5 sync fixtures against post-footprint reality.** Author M2's `test-sync.sh` upgrade fixtures
   so they do **not** hard-assert the pre-footprint installed test-file set; otherwise M4's footprint change
   forces a cross-boundary edit. (M4 gets shared-write on `test-sync.sh` with an integration note if needed.)
