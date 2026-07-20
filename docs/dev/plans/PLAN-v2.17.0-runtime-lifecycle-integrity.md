# PLAN — v2.17.0: Runtime & Lifecycle Integrity

Baseline: `v2.16.0` (`e2861ae31bf2f5132258ea89a57e0bf91ca96f9c`, annotated+published tag `v2.16.0`,
`origin/master == e2861ae`). Guard suite green at baseline. Target: `v2.17.0`.

## Context

A correction and hardening release — **not** a framework expansion, and **not** the release-audit
experiment (`RELEASE_AUDIT` is deferred to v2.18). A three-cluster audit reproduced this prompt's
hypotheses against live source and confirmed a chain of completion-lifecycle defects. The release makes
one invariant hold end to end:

> The exact phase range independently reviewed = evidenced = scanned = ticked, and the completion
> transition is durably committed before any success or publication is possible.

## Objectives
- **OBJ-1701** — fail closed on evaluator process errors (nonzero exit cannot pass).
- **OBJ-1702** — completion success requires a durable completion commit.
- **OBJ-1703** — unify evaluator, evidence, scan and tick phase identity/range.
- **OBJ-1704** — reconcile retired toolkit files safely during sync.
- **OBJ-1705** — restore native SPEC→ROADMAP requirement handoff guidance (linter already supports it).
- **OBJ-1706** — make milestone closure transactional and fail closed.
- **OBJ-1707** — correct installation, global-copy and symlink error propagation.
- **OBJ-1708** — harden the macOS watchdog backend probe (locale premise contradicted — see below).
- **OBJ-1709** — harden shared high-stakes camelCase tokenization.
- **OBJ-1710** — bind grade/evidence to phase identity; scan publication commit-by-commit.
- **OBJ-1711** — add non-vacuous regression, migration and live-scenario evidence.
- **OBJ-1712** — preserve leanness, portability and human release control.

## Finding disposition (reproduced against current source)

| Obj | Verdict | Evidence |
|---|---|---|
| 1701 | CONFIRMED (exits 1–123; ≥124 already caught) | `autopilot.sh:606-613` only checks `EVAL_RC -ge 124`; no `-ne 0` (contrast builder `:547-549`) |
| 1702 | CONFIRMED | `autopilot.sh:696-699` `git commit … \|\| true` + unconditional `RUN_RESULT="success"`; `tick.sh:473-476` never commits |
| 1703 | CONFIRMED | manual evaluator diffs `.phase-base` (`evaluator.md:65,93,109`); manual tick prefers `.phase-anchor` (`tick.sh:238-256`); no shared resolver |
| 1704 (grade) | CONFIRMED | `.phase-grade`=`run_id,verdict,no_tests_ok` (`record-grade.sh:73-78`); evidence has no heading/base (`test-evidence.sh:105-128`); tick accepts any `run_id==HEAD` |
| 1704 (sync) | CONFIRMED | `sync.sh:230-258` iterates current toolkit only; no retired bucket; never deletes |
| 1705 | PARTIALLY — linter already native (contradicted); only guidance external-only | `_requirements.sh:84-95,146`; `roadmap/SKILL.md:81-105` |
| 1706 | CONFIRMED | `close-milestone.sh:128-158` in-place, no rollback; `--name` unvalidated (`:21-31`), missing-value infinite loop |
| 1707 | CONFIRMED | global-skills `install.sh:193-202` discards `cp` rc; symlink discovery `:35`; chmod `:266 \|\| true`; README Option C `:123-136` flattens on BSD |
| 1708 | CONTRADICTED premise + minor finding | `autopilot.sh:418-432` Perl `setpgrp/exec` locale-insensitive; real gap = presence-only probe |
| 1709 | CONFIRMED | `_high-stakes.sh` / `test-high-stakes.sh` (fix landed this release) |
| 1710 (secret) | CONFIRMED for default regex (matches `SECURITY.md:57-65`) | net `BASE..HEAD` at `autopilot.sh:756`, `tick.sh:265,336`; `_secret-scan.sh:56-61,162-166` |

## Non-goals (deferred to v2.18 or rejected)
`RELEASE_AUDIT` mode · fifth agent · findings schema/DB/YAML/JSON · review-pack generation · external-model
routing · automatic dual review · ticket export · automatic PR/merge/tag/publication · UAT/enforcement
ledger · formal waves · another planning/roadmap/spec/completion format · telemetry · MCP orchestration ·
a broad `/wrap` Git dashboard.

## Non-negotiable architecture (preserved)
Four permanent agents (Researcher, Planner, Executor, Evaluator). `scripts/tick.sh` is the sole
programmatic writer that flips `- [ ]` → `- [x]`. Human is the sole publication authority (no auto
push/PR/merge/tag/release/branch-delete/worktree-delete; no destructive reset/history-rewrite). No new
canonical artifact; one author per owned artifact.

## Locked decisions
- **OBJ-1710 secret scan:** the default regex push-gate scans **commit-by-commit**
  (`git rev-list START_REF..HEAD` → each `commit^!`); no new dependency; gitleaks/trufflehog stay the
  stronger opt-in; documented as "obvious secrets caught in every commit, still not a full scanner."
- **OBJ-1708 watchdog:** locale-break premise recorded CONTRADICTED; add a Perl **usability** probe
  (broken-but-present Perl → `setsid` fallback) + a `C.UTF-8` CI fixture proving the watchdog runs.

## Affected files & change ownership (one owner per file; edits sequenced to avoid overlap)

| Obj | Owns (writes) | Shared / read |
|---|---|---|
| M0 | `docs/dev/plans/PLAN-v2.17.0-runtime-lifecycle-integrity.md` (this) | — |
| 1701/1702 | `scripts/autopilot.sh`, `scripts/test-autopilot-gates.sh` | builder path `:547-549` |
| 1703 | **new** `.claude/lib/_phase-range.sh`, **new** `scripts/phase-range.sh`, **new** `scripts/test-phase-range.sh`, `scripts/tick.sh` (base block), `.claude/agents/evaluator.md`, `.claude/commands/wrap.md` | `start-phase.sh` anchor format |
| 1710/1704(grade) | `scripts/record-grade.sh`, `scripts/test-evidence.sh`, `scripts/tick.sh` (validation), `scripts/test-tick.sh`, `scripts/test-evidence-schema.sh` | `_phase-range.sh` |
| 1705 | `skills/roadmap/SKILL.md`, `.claude/agents/evaluator.md`, `.claude/agents/planner.md`, `scripts/test-requirements.sh` | `_requirements.sh`, `to-spec/SKILL.md` |
| 1704(sync) | `scripts/sync.sh`, `scripts/test-sync.sh` | `install.sh` manifest format |
| 1706 | `scripts/close-milestone.sh`, `scripts/test-close-milestone.sh` | `trace-requirements.sh:14-16` |
| 1707/1708 | `install.sh`, `scripts/autopilot.sh` (watchdog), `README.md`, `.github/workflows/*`, `.github/scripts/install-smoke.sh` | — |
| 1709 | `scripts/test-plan-review-route.sh` | `_high-stakes.sh` (done) |
| 1710(secret) | `.claude/lib/_secret-scan.sh`, `scripts/autopilot.sh` (push gate), `scripts/tick.sh` (scan), `scripts/test-secret-scan.sh`, `SECURITY.md` | — |
| register | `scripts/run-guard-tests.sh` (`TESTS[]`), `install-smoke.sh`, `install.sh`/`sync.sh` | manifest → doctor |
| release | `VERSION`, `CHANGELOG.md`, README/SECURITY/SCAFFOLD/CONTROL-PLANE/GUIDE/AUTHORING, **new** ADR(s), **new** `docs/dev/audits/RELEASE-CANDIDATE-v2.17.0.md` | skill catalog |

`autopilot.sh` and `tick.sh` are multi-milestone: sequence runtime (1701→1702) → identity/binding
(1703→1710/1704) → scans (1710) so edits layer cleanly.

## Implementation sequence (small commits; each leaves its targeted tests green)
0. `docs(plan)` — this file. Run Evaluator **PLAN_CHECK**; resolve any `PLAN_FAIL`.
1. `fix(autopilot): reject every nonzero evaluator exit` (+ gate tests).
2. `fix(autopilot): require a durable completion commit` (+ tests).
3. `refactor(phase): shared trusted phase-range resolver` (+ lib/CLI/tests; wire tick/evaluator/wrap).
4. `feat(evidence): bind grade and evidence to heading+base` (schema v3; tick validation; + tests).
5. `fix(traceability): native SPEC requirement source guidance` (+ native end-to-end fixture).
6. `feat(sync): reconcile retired managed files safely` (+ migration matrix).
7. `fix(milestone): transactional closure + --name validation` (+ failure-injection tests).
8. `fix(install): propagate global-copy/symlink/chmod failures` + `fix(watchdog): usability probe`
   + `docs(install): fix BSD manual-copy flatten` (+ portability CI fixtures).
9. `test(security): camelCase routing consistency + mutation` (matcher fix already landed).
10. `fix(publication): commit-by-commit secret scan for the default backend` (+ add-remove fixture).
11. `docs(dogfood)` + `docs(release)` + `docs(decision)` ADRs + `chore(release)` VERSION/CHANGELOG.

## Test strategy
Each fix ships with a fixture that asserts its own preconditions and fails without the fix. New
`scripts/test-*.sh` are registered in `run-guard-tests.sh` `TESTS[]` (CI drift-guard). New shipped files
flow through the manifest to `doctor.sh`/`sync.sh`/`install-smoke.sh`; add explicit footprint assertions.

## Mutation-test strategy (focused, no framework)
Mutate and prove a named test fails: evaluator exit-code enforcement · completion-commit enforcement ·
shared range resolver · grade heading binding · evidence base binding · sync retired-file removal ·
native requirement source handling · milestone rollback · watchdog usability fallback · camelCase
normalization · publication commit-by-commit scan.

## Migration strategy
Evidence is a transient per-run artifact (regenerated by `test-evidence.sh`), so schema v3 (heading+base)
takes effect immediately after upgrade; v1/v2 accepted only with a deprecation warning, documented sunset.
Sync retired-file reconciliation is dry-run by default, deletes only `UNCHANGED-RETIRED` after hash match
+ explicit confirmation/`--yes`, never touches locally-modified or project-owned files.

## Portability strategy
macOS Bash 3.2 / BSD (normal + `C.UTF-8`), Linux Bash 5 / GNU / non-root (uid≠0); repo path with spaces;
repo outside `$HOME`; symlinked installer path; unwritable destination.

## Context-budget target
No new agent; no new always-loaded material. New logic is shell-side (scripts/libs loaded only when run).
Baseline: agent-description total 1215/2000 B (researcher 296 / planner 238 / executor 232 / evaluator
449 — all byte-identical to v2.16.0). CLAUDE.md unchanged; evaluator/wrap edits are in BODIES.

## Rollback strategy
Each fix is a self-contained commit revertable alone. The shared resolver (M3) is additive — tick keeps
its ancestor/anchor-parent checks. Sync/close-milestone changes are guarded by dry-run + rollback so a
revert cannot leave a project mid-migration.

## Release criteria
Nonzero evaluator exit cannot pass · failed completion commit cannot publish · review/evidence/scan/tick
agree on heading+base+HEAD · same-HEAD cross-phase reuse fails · retired managed files reconciled safely ·
native requirements documented end-to-end with a passing fixture · milestone closure transactional with
byte-identical rollback · install failures propagate · matcher identical at plan and tick · auto-publish
scans every commit · four agents, no RELEASE_AUDIT · full suite green on the tagged commit across both
platforms · mutations non-vacuous · guarantee table honest.

## Rejected alternatives
- Requiring an external secret scanner for every `--pr` (breaks existing default-backend runs) — rejected
  for the leaner commit-by-commit regex scan.
- A locale-wide `LC_ALL` override for the watchdog — rejected: the premise is contradicted and the hack
  would mask real failures.
- Duplicating base-precedence logic per consumer — rejected for the single shared resolver.

## PLAN_CHECK (pre-implementation, independent)
_To be run before implementation; record the verdict here._
