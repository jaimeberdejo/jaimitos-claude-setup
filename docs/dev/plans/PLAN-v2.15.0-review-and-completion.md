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

## Milestones

**5.1 — the genuine discovery gap.** `skills/grill/SKILL.md`: depth earns its branches from an
unresolved material decision rather than the tier label; an explicit stopping condition ends the
interview once every material decision is settled or recorded as an honest gap. Pinned by
`test-docs-invariants.sh`, including an `assert_absent` proving no `--deep` flag exists.

**5.2 — the scoping rule.** Planner details one active phase, or a bounded batch only when the phases
share one integration boundary and must land together to stay verifiable. ROADMAP keeps the complete
high-level sequence and holds no speculative distant detail. Scheduled ≠ planned.

**5.3 — the review/completion layer.** Findings contract + manual review-pack template
(`.claude/rules/review.md`); Evaluator `RELEASE_AUDIT` mode; `/wrap` gains `RUN RELEASE AUDIT` and
`PLAN NEXT PHASE` **offers** under the file's existing offer-never-act grammar.

---

## Rejection criteria (applied at each milestone, not at the end)

Remove, simplify or defer when: it activates during ordinary work · it creates an artifact nobody
reads twice · it duplicates SPEC/ROADMAP/STATE/phase plans · it adds substantial permanent context ·
manual operation is simpler · release audit repeats phase evaluation · `/wrap` becomes an
orchestration dashboard rather than a completion checklist · ordinary branches receive release-level
ceremony.
