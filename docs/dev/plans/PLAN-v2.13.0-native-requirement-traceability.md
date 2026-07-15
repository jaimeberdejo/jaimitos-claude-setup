# PLAN — v2.13.0: Native requirement traceability (lean extension)

> **Branch:** `release-3-native-traceability` (from `master` @ `e58a8bf`, `VERSION=2.12.0`, clean tree).
> **Target:** `VERSION=2.13.0`. **No push, no tag, no PR, no autopilot on the control plane.** Bumping
> VERSION / tagging is its own operator checkpoint.
> **Plan artifact (tracked):** this file — copied here as commit 1.
> **Baseline recorded:** guard suite 21/21 green, `lint-roadmap` / `test-docs-invariants` /
> `release-check --prepare` all exit 0 on `e58a8bf`.

---

## Context

The Release 3 brief asks Jaimitos to own requirement traceability natively —
`SPEC REQ/AC → roadmap phase → plan task → code/test evidence → evaluator → tick` — extracting the one proven
capability from the **rejected** Release 2 Spec Kit experiment without any Spec Kit runtime, artifacts, or
permanent context cost.

**Half of it already shipped.** A repository audit found that `origin/master` was already at **v2.12.0
(`e58a8bf`), tagged**, and the brief was written without knowledge of it. v2.12.0 delivered the **lean
roadmap→evaluator half** of the exact chain:

- roadmap phases may carry optional `Sources:` + `Requirements:` lines (any id scheme) — `skills/roadmap/SKILL.md`
- the `evaluator` gained a **conditional** Axis-A "Requirement traceability" bullet: when a phase declares
  `Requirements:`, each listed id becomes an additional acceptance criterion traced to code/test; an
  untraceable id is an unmet criterion → `NEEDS_WORK`
- v2.11.2 first hardened the roadmap parser to be `Requirements:`-safe (anchored `- [ ]` regexes in `_roadmap.sh`)
- `test-docs-invariants.sh` asserts the section stays conditional and names no tool

What v2.12.0 **deliberately did not do** (its commit message argues *for* leanness): adopt a native
`REQ-###`/`AC-###` format, touch the **spec side** (`SPEC.md`/`grill`/`to-spec`), touch the **plan side**
(`planner`), or validate id format. That is exactly this release's genuinely-new surface.

Outcome: native `REQ/AC/OBJ` ids flow the *whole* chain, mostly via conventions in skill/agent **bodies**
(loaded on invocation, not always) + one bounded validation helper — near-zero always-loaded delta, no new
spec hierarchy, no second task queue, no second completion mechanism. `scripts/tick.sh` stays the sole
completion authority, untouched.

---

## Decisions taken (operator-confirmed)

| # | Decision | Consequence |
|---|---|---|
| 1 | **Scope = lean native extension** | Build native ids on the spec + plan sides only; reuse the shipped roadmap/evaluator seam. Skip the heavy migration engine and any standalone second linter. |
| 2 | **Base = fast-forward to v2.12.0, target v2.13.0** | v2.12.0 is taken; build additive. FF is non-destructive. |
| 3 | **`grill` discovers, `to-spec` owns ids** | The interviewer surfaces requirement candidates; the closer is the *sole* assigner/preserver of canonical ids (a mid-interview choice can reverse; ids aren't minted until close). |
| 4 | **Validation is a focused shared helper, not a linter overload** | New `_requirements.sh` owns `REQ/AC/OBJ` semantics; `lint-roadmap.sh` merely *calls* it when a phase carries `Requirements:`. |
| 5 | **Native ids = `REQ-###` / `AC-###` / `OBJ-###`; `AC` globally unique in the spec** | External ids accepted *structurally* (`PREFIX-###`) only when a source defines them; core hard-codes no external-prefix semantics. |
| 6 | **`Status: Approved` + blocking `[NEEDS CLARIFICATION]` = strict failure** | `Proposed`/`clarifying` requirements may retain the marker. |
| 7 | **Legacy id adoption is request-only + review-first** | Not prompted on every legacy workflow; original content preserved, no auto-renumber. |
| 8 | **No cosmetic evaluator commit** | The evaluator is touched only if a real `docs/SPEC.md` source-resolution gap surfaces. |
| 9 | **Disposable dogfood code stays out of the toolkit** | Commit only focused deterministic fixtures + the dogfood findings report. |

---

## The chain and its authorities (unchanged)

```
docs/SPEC.md  REQ/AC/OBJ definitions        ← to-spec (sole id owner)
      ↓ referenced by
docs/ROADMAP.md  Sources: / Requirements:    ← roadmap skill (shipped v2.12.0)
      ↓ mapped by
phase plan  task → REQ/AC/OBJ                 ← planner
      ↓ implemented + tested
code + tests                                  ← executor (TDD)
      ↓ traced by
evaluator "Requirement traceability" section  ← evaluator (shipped v2.12.0; conditional, edit-disabled)
      ↓ gated by
record-grade.sh → tick.sh                      ← the SOLE completion authority (untouched)
```

Deterministic id structure is validated by `_requirements.sh` (via `lint-roadmap.sh`); semantic satisfaction
stays evaluator + human judgment.

---

## Design

### 1. Spec-side native ids — `jaimitos-os/docs/SPEC.md`, `skills/grill/SKILL.md`, `skills/to-spec/SKILL.md`
- **`SPEC.md`:** add an **optional** `## Requirements (optional — REQ/AC)` section with a commented example
  (`### REQ-001 — title`, `Status:` one of `Proposed|Clarifying|Approved|Deferred|Rejected|Superseded`, nested
  `- AC-001: …`). The measurable `## Success criterion` stays the default anchor; **tiny specs use only that.**
  Must not perturb the roadmap skill's content-derived readiness. `[NEEDS CLARIFICATION]` preserved.
- **`grill` (body):** discover/clarify requirement candidates; do **not** mint canonical ids.
- **`to-spec` (body) — sole id owner:** assign/preserve `REQ/AC/OBJ`, never renumber/recycle, surface unresolved
  `[NEEDS CLARIFICATION]`; legacy adoption only on explicit request, review-first.
- **Leanness:** guidance lives in skill *bodies*; `description:` fields stay ~unchanged (always-loaded delta ≈ 0).

### 2. Plan-side task→id mapping — `jaimitos-os/.claude/agents/planner.md`
When the active phase declares `Requirements:`, each task notes the `REQ/AC/OBJ` it satisfies — reproduced from
the phase, never invented. Tiny/unnumbered phases skip it. No second task hierarchy.

### 3. Deterministic validation — new `jaimitos-os/.claude/lib/_requirements.sh`, called by `lint-roadmap.sh`
Focused helper owning id semantics. `lint-roadmap.sh` calls it only when a phase carries `Requirements:`.
Advisory by default, `--strict` fails. Checks: malformed ids; dup within a phase; native `REQ/AC/OBJ` +
structural external `PREFIX-###` (defined-by-source only); `AC` spec-global uniqueness; cross-ref to
`docs/SPEC.md`; `Approved` + blocking `[NEEDS CLARIFICATION]` → strict fail. **Not** deterministic:
completeness, semantic correctness, measurability, test quality, satisfaction.
**Portability:** Bash 3.2 / BSD + non-root mawk; awk arrays ok; regex via `ENVIRON` not `-v`; no
`declare -A`/`mapfile`/`${x,,}`/`sort -V`/`grep -P`.

### 4. Evaluator / completion — no protocol change, no cosmetic change
The v2.12.0 conditional bullet already traces and expresses an unmet id via the final `NEEDS_WORK` line →
`record-grade.sh` records no grade → `tick.sh` gate 2 refuses. `tick.sh`, `record-grade.sh`, `.phase-grade`,
`.tick-evidence.json` byte-unchanged. Touch the evaluator only if a real `docs/SPEC.md` source-resolution gap
appears.

---

## Files changed

| File | Purpose | Compat |
|---|---|---|
| `jaimitos-os/docs/SPEC.md` | optional REQ/AC section | additive; tiny specs unaffected |
| `skills/grill/SKILL.md` | discover candidates (no minting) | additive; desc ~unchanged |
| `skills/to-spec/SKILL.md` | sole id owner; legacy adoption on request | additive; desc ~unchanged |
| `jaimitos-os/.claude/agents/planner.md` | task→id mapping when Requirements present | additive; inert otherwise |
| `jaimitos-os/.claude/lib/_requirements.sh` | **new** id-validation helper | new; runs only when Requirements present |
| `jaimitos-os/scripts/lint-roadmap.sh` | call helper when Requirements present | advisory; legacy passes |
| `jaimitos-os/.claude/agents/evaluator.md` | only if source resolution requires it | conditional invariant kept verbatim |
| `jaimitos-os/scripts/test-lint.sh` | id-validation fixtures | — |
| `jaimitos-os/scripts/test-docs-invariants.sh` | spec/plan prose contracts + no-speckit | — |
| `docs/decisions/ADR-001-*.md` | terse 4-line decision record | new (maintainer-only, unshipped) |
| `README.md`, `docs/dev/AUTHORING.md` | docs + guarantee/enforcement table | additive |
| `VERSION`, `CHANGELOG.md` | 2.13.0 + heading | release prep (no tag/push) |

**Reuse, don't rebuild:** the `Sources:`/`Requirements:` roadmap block, the conditional evaluator bullet, the
anchored `_roadmap.sh` regexes, `next-adr.sh`, the `ok/bad/assert_has/assert_absent` test header, and the
manifest derive-not-duplicate pattern.

---

## Deterministic vs semantic enforcement

| Guarantee | Enforcement |
|---|---|
| `REQ/OBJ` unique, **`AC` globally unique**, refs resolve, format valid, `Approved` free of blocking `[NEEDS CLARIFICATION]` | **DETERMINISTIC** (`_requirements.sh` via `lint-roadmap.sh`) |
| Legacy specs/phases still valid | **DETERMINISTIC tests** (`test-lint`, `test-docs-invariants`) |
| Evaluator edit-disabled / evidence bound to HEAD / tick sole gate | **Existing deterministic gates** (unchanged) |
| Requirement implemented correctly; AC meaningful; test genuinely proves it | **MODEL-DEPENDENT** (evaluator) |
| Phase can complete | Existing evaluator → `record-grade` → `tick.sh` chain |

---

## Compatibility, migration, rollback
- Legacy specs (no ids): unchanged; adoption request-only + review-first.
- Legacy phases (no `Requirements:`): evaluator/parser/tick behave exactly as today.
- External ids: accepted only when defined by the authoritative source; bounded shape, not every token.
- Rollback: additive commits revert cleanly; optional id blocks removable; original content intact; completed
  roadmap history never rewritten.

---

## Tests
- `test-lint.sh` (drives `_requirements.sh` via `lint-roadmap`): valid spec passes; dup REQ fails; **dup AC
  anywhere fails**; malformed id fails; unknown roadmap ref fails; **`Approved` + `[NEEDS CLARIFICATION]` fails,
  `Proposed` + marker passes**; legacy spec passes; phase without `Requirements:` passes; external `PREFIX-###`
  accepted only when defined. Split to `test-requirements.sh` (+ `run-guard-tests.sh` registration) only if it
  outgrows `test-lint`.
- `test-docs-invariants.sh`: SPEC states REQ/AC optional + tiny exempt; grill/to-spec/planner mention them
  conditionally; evaluator conditional wording preserved; no `speckit`/`spec kit` anywhere new.
- Regression: `test-roadmap-lib.sh` / `test-tick.sh` prove a `Requirements:` block creates no false open tasks
  and doesn't alter counting/tick; requirement metadata alone cannot tick.
- Portability: full guard suite on macOS (Bash 3.2/BSD) **and** non-root Linux/mawk before claiming green.

---

## Dogfood
Native flow on a real account-export/deletion scenario in a **scratchpad** sample project:
`grill → to-spec (REQ/AC) → ROADMAP Requirements → /phase → planner → TDD → evaluator → tick.sh`. ≥1 REQ,
several ACs, ≥1 high-stakes deletion under a supervised phase; negatives (id not implemented; no meaningful
test; unknown id; legacy phase; high-stakes can't bypass supervised). Commit **only** fixtures + the findings
report; the disposable project stays in scratchpad.

---

## Context budget
Record before/after bytes+tokens for `CLAUDE.md`, `evaluator.md`, `planner.md`, the model-invoked
`description:` set (~5035B; cap 6000B), roadmap templates, session-start. Target always-loaded delta ≈ 0;
compare with the measured Spec Kit permanent cost. Do not shrink the evaluator to save bytes.

---

## Verification (exact commands)
```bash
bash jaimitos-os/scripts/run-guard-tests.sh < /dev/null
bash jaimitos-os/scripts/lint-roadmap.sh --strict
bash .github/scripts/install-smoke.sh
bash jaimitos-os/scripts/test-docs-invariants.sh
bash jaimitos-os/scripts/release-check.sh --prepare
find . -name "*.sh" -not -path "./.git/*" -print0 | xargs -0 -n1 bash -n
bash .github/scripts/lint-shell.sh
actionlint .github/workflows/ci.yml jaimitos-os/.github/workflows/jaimitos-os-ci.yml
```
Run on macOS (Bash 3.2/BSD) **and** non-root Linux (GNU + mawk). Report any check `NOT RUN — <reason>`.

---

## Commit structure (small; each leaves tests green; no push/tag)
1. `docs(plan): scope native requirement traceability (v2.13.0)`
2. `docs(adr): record the Spec Kit experiment → native decision`
3. `feat(spec): define native REQ/AC/OBJ conventions in the SPEC template`
4. `feat(to-spec): assign and preserve stable REQ/AC/OBJ ids (sole owner) + legacy adoption`
5. `feat(grill): discover and clarify requirement candidates (no id minting)`
6. `feat(plan): map plan tasks to requirements`
7. `feat(lint): _requirements.sh helper, called by lint-roadmap when Requirements present`
8. `test(traceability): id-validation + prose-contract fixtures`
9. `docs(traceability): README, AUTHORING enforcement table, migration`
10. `test(dogfood): record native end-to-end findings report`
11. `chore(release): v2.13.0 — version + changelog` (prepare only; tag/push is a separate operator checkpoint)

Experiment cleanup (close PR #4, keep branch) is report-only — not mixed into these commits.

---

## Deliberately out of scope (report as DELIBERATELY REJECTED)
Standalone `lint-requirements.sh` (replaced by the `_requirements.sh` helper); a dedicated migration
skill/engine (folded into `to-spec`, request-only); a REQ/AC lifecycle state machine; cosmetic evaluator edits;
hard-coded external-prefix semantics; mandatory ids for tiny/legacy work; committing throwaway dogfood code;
any second spec hierarchy / task queue / completion mechanism / evaluator; any Spec Kit runtime, `.specify/`,
`specs/`, `tasks.md`, preset, or CLI dependency.
