# PLAN — v2.15.0: Review handoffs, release audit & human-controlled completion

> **Branch:** `release-5-review-and-completion` (from `master` @ `8be108a`, tag `v2.14.0`,
> `VERSION=2.14.0`). R5 builds on R4's progressive control plane, which is **released**.
> **Target:** `VERSION=2.15.0`. **No push, no tag, no PR, no history rewrite, no destructive reset,
> no unattended autopilot on the control plane.** Bumping VERSION / tagging is its own operator
> checkpoint.
> **Plan artifact (tracked):** this file — committed as commit 0.
> **Baseline recorded on `8be108a`:** clean tree; `run-guard-tests.sh` all green;
> `release-check --prepare` exit 0; `CLAUDE.md` 3140 B; model-invoked skill descriptions
> **5157 B / 6000 B** (headroom 843 B).

---

## Context

The brief for this release asked for eleven capabilities across three milestones, on a stated base of
"Release 4 = v2.13.0" targeting v2.14.0.

**The brief's baseline was wrong.** Verified ground truth: `v2.13.0` is **Release 3**;
**Release 4 is `v2.14.0`, released** (`origin/master` = `8be108a` = annotated tag `v2.14.0`). v2.14.0
was therefore taken, and R5 targets **v2.15.0**.

**The larger finding: most of the brief was already built.** R3 shipped the traceability spine; R4
shipped tiers, `PLAN_CHECK`, brownfield `mapme`, the enforcement ledger, and plan revalidation.
Audited against the real tree, only **four** of the eleven proposed capabilities are genuinely new —
all in the review/completion layer. The rest are already complete, or duplicate an existing owner.

R5 therefore ships the genuine gaps and **records the rejections** rather than building surface for
its own sake. A rejected capability is a valid result.

**Invariant preserved:** the four conditional agents stay four; `scripts/tick.sh` stays the sole path
that flips `- [ ]` → `- [x]`; no wave entity, no tracker authority, no automatic release action.
Always-loaded context does not grow: every surface R5 touches loads on invocation.

---

## Phase 0 — audit classification (all eleven proposed capabilities)

| # | Proposed | Verdict | Evidence |
|---|---|---|---|
| 1 | `grill --deep` flag/mode | **REJECT — overlap** | `grill` rule 5 already scales depth by `tier:`; DEEP already earns architecture alternatives / failure modes / migration / threat model. Activation is a *derived condition*, not a user-typed mode; a mode flag would cost always-loaded description bytes to express a condition the body already evaluates. |
| 2 | Disposable discovery artifact | **DEFER — no demand** | All nine proposed sections already have an owner (SPEC `## Open questions` / `## Deep design` / `Non-goals` / `Constraints`; `mapme`'s VERIFIED/INFERRED/UNKNOWN tags; ADRs). Its `ACTIVE/READY_FOR_SPEC/BLOCKED` states duplicate the gate-enforced `status:` machine, which `SPEC.md` calls "the ONE stored spec-lifecycle bit". |
| 3 | Discovery → `to-spec` handoff | **ALREADY COMPLETE** | `grill` already offers `to-spec` at close and writes settled decisions into SPEC live. `to-spec` requires closing from **SPEC.md alone** — a discovery-file input would either duplicate SPEC's open questions or close a spec blind to real open decisions. |
| 4 | Optional `DEC-###` ids | **REJECT — overlap** | `ADR-###` is already the durable decision id (`next-adr.sh`). An id in a file deleted at handoff either dangles or was never referenced. |
| 5 | Plan only the active phase / bounded batch | **NEW (small) → Planner** | No `active-phase-only` / long-horizon / bounded-batch rule existed. The genuine 5.2 gap. |
| 6 | Stale-assumption revalidation | **ALREADY COMPLETE** | `planner.md` `## Assumption revalidation` + `check-plan-freshness.sh` + **ADR-006** ("an invalidated plan may not keep a prior PASS"). |
| 7 | Proportionate review routing | **ALREADY COMPLETE** | R4 tiers + `PLAN_CHECK` / `IMPLEMENTATION_REVIEW` activation rules. |
| 8 | Minimal findings contract | **NEW — justified** | No severity vocabulary exists anywhere. `review-feedback` classifies *disposition*, not *gravity* — orthogonal axes. |
| 9 | Manual review-pack template | **NEW — justified** | Nothing portable exists. |
| 10 | Evaluator `RELEASE_AUDIT` | **NEW — justified** | Third mode of one edit-disabled reviewer; ADR-005 precedent ("a MODE, not a new agent"). |
| 11 | Human-controlled `/wrap` | **NEW (small) → `/wrap`** | `wrap.md` has the offer-never-act grammar but lacks these options and never calls `release-check.sh`. |

**Net: R5 = the review/completion layer + two short prose gaps.**

---

## Decisions taken (operator-confirmed)

| # | Decision | Consequence |
|---|---|---|
| 1 | **Base = released `v2.14.0` @ `8be108a`, target v2.15.0** | The brief's "v2.13.0 = R4" was wrong; v2.14.0 is taken by the released R4. Local `master` was 20 commits behind, which caused an initial misread — corrected by `ls-remote` against origin. The stale branch tip `74bc1e8` is **not** the base: `8be108a` carries a later merge + a file-mode fix. |
| 2 | **v2.14.0 is independently audited before R5 builds on it** | Its only record was a dogfood report by its own author — *not cleared*. Defects found are fixed **in core**, never compensated for in an R5 layer. The audit doubles as the real `RELEASE_AUDIT` dogfood. |
| 3 | **Deep discovery stays a branch of `grill`** | No `--deep` flag, no discovery artifact, no `FACT/ASM/DEC` ids, no `to-spec` change. Ships only the genuine gap: depth keys off *unresolved material decisions*, and the interview has an explicit **stopping condition**. |
| 4 | **The discovery artifact is dogfood-gated, not pre-rejected** | If a real ambiguous DEEP initiative shows `SPEC.md` genuinely cannot hold the unresolved state, the case is brought to the operator before anything is built. Absent that evidence: rejection ADR, mirroring ADR-003. |
| 5 | **Planning in waves is documentation language, not an entity** | No `WAVE-###`, no wave state/files/completion. ROADMAP stays the full high-level sequence; only the active phase (or a justified bounded batch) is detailed. |
| 6 | **Evaluator gains a third mode, not a twin** | `RELEASE_AUDIT` is a `---`-separated section of the same edit-disabled evaluator, on a channel `record-grade.sh` never reads. It **never ticks**. No release-review agent or skill. |
| 7 | **Review packs start as a manual template** | Automation deferred until the template survives 2–3 real projects and manual assembly demonstrably hurts. |
| 8 | **External review is user-triggered; findings are untrusted** | No provider integration, no automatic routing, no parallel review by default. External approval can never tick or release. |
| 9 | **Ticket export stays out of scope** | Deferred until repeated real coordination demand shows manual copying is materially costly. No exporter, no credentials, no mapping files. |

---

## Placement rationale (why files land where they do)

- **`jaimitos-os/.claude/rules/review.md`** holds the findings contract + pack template.
  `toolkit-docs/*` is **never shipped** (`install.sh` excludes it explicitly), so it cannot hold
  operational guidance a user project needs. `.claude/rules/` installs and loads **on demand** —
  precedent: `.claude/rules/high-stakes.md`. Always-loaded cost: **zero**.
- **`docs/dev/`** is maintainer-only and never installs (`install.sh` reads only `jaimitos-os/` and
  `skills/`). That is why the brief's `docs/dev/discovery/` path would have produced a capability
  that never reaches a user project — one of the reasons capability #2 is deferred rather than built.

---

## What actually shipped — the plan changed mid-flight, twice

**The independent audit of the v2.14.0 base changed the release.** Five reviewers found 1 critical and
4 high defects, all reproduced. The pattern — *five correct validators wired to nothing, graded
DETERMINISTIC in the docs* — made the planned review layer the wrong next thing: a findings contract and
a review-pack template that nothing invokes would have been the **same shape as the defect**, stacked on
top of it. `RELEASE_AUDIT` was blocked regardless, since a third mode ending in `PASS` inherits the
demonstrated `record-grade.sh` collision.

Operator decision: **correction-first, defer the review layer to v2.16.0**, and **make the claims true in
code** rather than relabelling them. Second decision, once the evidence was in: **delete** the enforcement
and UAT ledgers rather than wire them.

**5.1 — shipped as scoped.** `skills/grill/SKILL.md`: depth earns its branches from an unresolved material
decision rather than the tier label; an explicit stopping condition ends the interview. Zero always-loaded
bytes. Pinned, including an `assert_absent` proving no `--deep` flag exists.

**5.2 — ALREADY COMPLETE. Ships nothing.** My Phase 0 classification was wrong: it came from a keyword
grep, not the concept. `roadmap/SKILL.md` already says *"One milestone's worth of phases. Don't roadmap the
entire product; roadmap the next shippable increment"* and *"Be one vertical slice / bounded scope"*; the
planner is dispatched per-phase by `/phase` ("a plan for the phase you're given"), so it **structurally
cannot** plan ahead; and a plan written early goes stale via `check-plan-freshness` + ADR-006. The toolkit
answers the brief's concern with a different, coherent boundary: ROADMAP = one milestone, plan = one phase,
`milestone` = the next increment. **Bounded batch: REJECT** — it has no artifact home (the plan filename is
derived per-phase), each phase must leave the app demoable, and `tick.sh` ticks one phase.

**5.3 — DEFERRED to v2.16.0.** Preconditions now met by this release: the `record-grade.sh` discriminator
exists, so a third mode is no longer blocked. Preconditions still open: `tier:` is unvalidated (do not
tier-scale a release audit while an unjustified TINY buys less review); and a findings schema would be the
**7th bespoke hand-parsed markdown format** — a pattern that produced two of the fail-opens fixed here.
Test `RELEASE_AUDIT` against AUTHORING's ladder first: "did the validators pass, is evidence fresh, is the
tag clean" is *mechanical*, and a deterministic script outranks an evaluator mode.

## Correction work (the bulk of v2.15.0)

Fail-opens: SIGPIPE in `check-plan-freshness` (10/10) · absent-target id skip · `Baseline commit:` parse ·
5 `shift 2` hangs · typo'd-flag exit 0 · unreachable-validator exit 0 · `--`-prefixed ledger rows ·
indented tables · omitted UAT `Blocking:`. Claims made true: PLAN_CHECK token discriminator · hoisted
untrusted-input defense · agent-description cap · read-only proof over all validators. Honesty: +412 B
published, guarantee rows split, "never a gate" corrected, dogfood "Not run" completed.

Every fix has a regression fixture; **every fixture was verified non-vacuous** by reverting the fix and
confirming it fails. That mattered — the first SIGPIPE fixture passed against the buggy code (42KB < the
64KB pipe buffer), so it now asserts its own precondition and fails loudly rather than going quietly
vacuous, which is the exact defect that hid this bug in v2.14.0's own suite.

---

## Rejection criteria (applied at each milestone, not at the end)

Remove, simplify or defer when: it activates during ordinary work · it creates an artifact nobody
reads twice · it duplicates SPEC/ROADMAP/STATE/phase plans · it adds substantial permanent context ·
manual operation is simpler · release audit repeats phase evaluation · `/wrap` becomes an
orchestration dashboard rather than a completion checklist · ordinary branches receive release-level
ceremony.
