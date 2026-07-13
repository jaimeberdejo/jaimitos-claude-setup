# PLAN — v2.10.0: Engineering disciplines, component creators, skill quality

> **Branch:** `feat/engineering-disciplines-creators` (from `master` @ `5eff507`, `VERSION=2.9.0`, clean tree)
> **Target:** `VERSION=2.10.0`. **No push, no tag, no PR, no autopilot on the control plane.**
> **Plan artifact (tracked):** `docs/dev/plans/PLAN-v2.10.0-engineering-disciplines-creators.md` — copied there as commit 1.

---

## Context

Jaimitos v2.9.0 has a strong *deterministic* spine (`tick.sh` as the sole completion gate, an independent
edit-disabled evaluator, gate-integrity byte-checks) but a thinner *judgement* layer. Research against
`obra/superpowers` and `mattpocock/skills` found:

- `tdd` says "see it fail" but never "fail for the **intended reason**", has no exception path when production
  code must precede the red test, and never runs the wider suite after a targeted green.
- `diagnose` has an excellent feedback-loop discipline but no vocabulary separating **symptom / root cause /
  unverified hypothesis / confirmed evidence**, and nothing that stops a speculative-fix loop.
- Verification-before-completion is enforced *mechanically* (tick gate) but not *behaviourally* — the executor
  may still claim success from a test run predating its final edit.
- The evaluator interleaves two axes: spec compliance (criteria-integrity) and engineering quality (fakery
  patterns) are both present, so a pass on one can mask a failure on the other.
- **Zero coverage** for receiving review feedback, deep-module design vocabulary, and sanctioned prototyping.
- **Zero tooling** for authoring skills/agents. `CONTRIBUTING.md:33-48` is prose, and adding one skill requires
  hand-editing 7 files carrying duplicated counts and parallel lists.

Outcome: strengthen how Jaimitos designs, tests, debugs, verifies and reviews — plus maintainer-only tooling to
create and lint skills/agents — **without** a second orchestrator, planner, executor, evaluator, completion gate,
roadmap, or agent swarm.

---

## Decisions taken (operator-confirmed)

| # | Decision | Consequence |
|---|---|---|
| 1 | **Reject `architecture-audit`** | `mapme` gains architectural-friction flags; the evaluator gains an architecture-fit check. One owner of `docs/ARCHITECTURE.md`. Upstream's HTML-report form rejected outright. |
| 2 | **Creators live in repo-root `.claude/skills/`** | `install.sh` reads *only* `jaimitos-os/` and `skills/` (`install.sh:31-32`) — root `.claude/skills/` is **structurally unshippable**, not list-excluded. Claude Code still auto-discovers it here. |
| 3 | **Zero new production agents** | `agent-creator`'s dogfood is an honest REFUSE. Validated against a maintainer-only fixture agent in tests. |
| 4 | **One release, v2.10.0** | ~10 reviewable commits; creators add no project runtime. |

### Forced deviations from the brief (record these; do not "fix" them)

- **Verdict stays `PASS` / `NEEDS_WORK:`, not `PASS`/`FAIL`.** `record-grade.sh:32` records a grade only when the
  verdict's **last non-empty line is exactly `PASS`**. Changing the token silently breaks the tick gate. The
  two-axis structure is added *above* the verdict line.
- **`prototype` must be reconciled with `CLAUDE.md:10`** ("TDD always… No exceptions on logic code"), which is
  always-loaded and would otherwise make the model refuse to prototype.

---

## What is deterministic vs what is model-dependent

**This table goes in the plan, the maintainer guide, and the final report.** v2.10.0 must not overstate its
guarantees: the linters check *shape*, not *judgement*.

| Guarantee | Enforcement |
|---|---|
| Skill/agent frontmatter validity, naming, description size | **Deterministic** (`test-skills.sh`, `test-agents.sh`) |
| Creators excluded from every installation path | **Deterministic** (install-smoke negative assertion + source-root test) |
| Agent declares an output contract; no hyphenated no-op keys; valid `model` value | **Deterministic** (`test-agents.sh`) |
| Every agent definition covered by `GATE_CONTROL_FILES` | **Deterministic** (`test-agents.sh`) |
| Catalog ⇔ directory consistency; provenance schema valid | **Deterministic** (`test-skills.sh`) |
| Evaluator cannot edit the tree | **Hook/gate enforced** (`_eval-isolation.sh`, snapshot+restore) |
| Evidence belongs to the current commit | **Hook/gate enforced** (`tick.sh` run_id == HEAD) |
| A test failed *for the intended reason* | **Model-dependent** — evidence-reviewed by the evaluator |
| Debugging avoided a speculative-fix loop | **Model-dependent** — evidence-reviewed |
| A new skill/agent was genuinely justified | **Model-dependent + mandatory human review** (control-plane change) |
| Module architecture is proportionate; architecture fit | **Model-dependent** |

---

## Upstream provenance

Both upstreams are cloned at their **pinned SHA into a temp dir outside the repo** — the local plugin cache is a
cross-check, never the provenance source.

```bash
UPSTREAM_DIR="$(mktemp -d)"     # outside the repo; never committed
git clone --filter=blob:none https://github.com/obra/superpowers "$UPSTREAM_DIR/superpowers"
git -C "$UPSTREAM_DIR/superpowers" checkout d884ae04edebef577e82ff7c4e143debd0bbec99
git clone --filter=blob:none https://github.com/mattpocock/skills "$UPSTREAM_DIR/matt-skills"
git -C "$UPSTREAM_DIR/matt-skills" checkout 391a2701dd948f94f56a39f7533f8eea9a859c87
```

| Upstream | Pinned SHA | License |
|---|---|---|
| `obra/superpowers` | `d884ae04edebef577e82ff7c4e143debd0bbec99` (tag `v6.1.1`, 2026-07-02) | MIT © Jesse Vincent |
| `mattpocock/skills` | `391a2701dd948f94f56a39f7533f8eea9a859c87` (2026-07-10) | MIT © Matt Pocock |

Nothing copied verbatim. Every adapted file keeps its one-line attribution comment.

### Adoption matrix

**Superpowers**
| Capability | Verdict | Where it lands |
|---|---|---|
| `test-driven-development` | **MERGE** | `skills/tdd` — red-for-the-right-reason, pristine-output green, explicit exception, wider-suite step |
| `testing-anti-patterns` | **MERGE** | `skills/tdd/mocking.md` + `tests.md` — "gate function" form; complete-mock iron rule |
| `systematic-debugging` | **MERGE** | `skills/diagnose` — evidence taxonomy, one-hypothesis rule, **3-fix architecture escalation** |
| `verification-before-completion` | **MERGE** | `executor.md`, `evaluator.md`, `phase.md`, `wrap.md` — evidence table + gate function. **No new skill, no new gate.** |
| `receiving-code-review` | **ADAPT** | new `skills/review-feedback` |
| `writing-skills` | **ADAPT** | `.claude/skills/skill-creator` + `docs/dev/AUTHORING.md` |
| `requesting-code-review` | **REJECT** | v2.7.0 already delegated review to native `/code-review` + `/security-review` + `scope-guard` + evaluator |
| `using-git-worktrees` | **REFERENCE ONLY** | Repo already has worktree flows; brief rejects a worktree framework |
| `using-superpowers` bootstrap hook, `brainstorming`, `writing-plans`, `subagent-driven-development`, `executing-plans`, `finishing-a-development-branch`, `dispatching-parallel-agents` | **REJECT** | Each is a competing spine (router / planner / executor / completion gate / swarm). Importing one drags the chain. |

**Matt Pocock**
| Capability | Verdict | Where it lands |
|---|---|---|
| `codebase-design` (+`DEEPENING.md`) | **ADAPT** | new `skills/module-design` |
| `prototype` (+`LOGIC.md`,`UI.md`) | **ADAPT** | new `skills/prototype` (both branches inline; no separate ref files) |
| `domain-modeling` | **MERGE** | `skills/glossary` — challenge/sharpen/cross-ref-with-code; 3-condition ADR test |
| `code-review` (two-axis idea) | **MERGE** | The Standards-vs-Spec split **is** the two-axis evaluator. Its Fowler smell baseline, condensed, feeds the engineering-quality axis. |
| `improve-codebase-architecture` | **REJECT** | HTML report app — explicitly rejected. Its *friction signals* merge into `mapme`. |
| `writing-great-skills` | **ADAPT** | `.claude/skills/skill-creator` + `docs/dev/AUTHORING.md` |
| `tdd`, `diagnosing-bugs`, `to-spec`, `grill` | **ALREADY MERGED** (v2.5.0) | Re-diff at the pinned SHA; port only genuinely new material |
| `design-it-twice` | **ALREADY MERGED** (v2.5.0) | `skills/design-twice` — now cross-references `module-design` for vocabulary |

---

## Architecture: what owns what (unchanged authorities in **bold**)

- **`docs/ROADMAP.md`** = sole execution queue · **`docs/STATE.md`** = sole current state · **`scripts/tick.sh`** = sole completion gate
- **`/phase`** = sole orchestrator · **planner** = sole per-phase planner · **executor** = sole implementer · **evaluator** = sole independent grader (edit-disabled)
- **`docs/GLOSSARY.md`** = `glossary` only · **`docs/decisions/`** = `adr` only · **`docs/ARCHITECTURE.md`** = `mapme` only
- New skills own **no artifact**: `module-design` (vocabulary), `prototype` (throwaway code), `review-feedback`
  (a triage + a set of edits). None may tick.

---

## Phase 0 — Baseline (no edits)

Branch; record `git log --oneline -1`, `cat VERSION`; run every check in **Verification** green. Clone both
upstreams at their pinned SHAs (above). Measure the context baseline. **Re-verify against current official
Claude Code docs** (do not assume): the skill frontmatter field set, the subagent field set, valid `model`
aliases, and **which fields are ignored per agent scope** — this feeds Phase 7's scope matrix.

## Phase 1 — Provenance + plan (commit 1)

`integrations/upstreams.lock.json` — per entry: `repo`, `sha`, `license`, `paths_consulted[]`,
`jaimitos_files_influenced[]`, `inspected` (ISO date), `adoption` (`copied|adapted|merged|concept-only`),
`deviations`. Two entries. **No auto-updater**; document the manual flow (inspect pinned SHA → diff → human
review → adapt → update lock → tests + dogfood). Copy this plan to `docs/dev/plans/`.

## Phase 2 — TDD + debugging (commit 2)

**`skills/tdd/SKILL.md`** — extend the existing loop (no second TDD skill): observe the failure **and confirm it
failed for the intended reason**; run the **wider** suite after the targeted green; protect existing behaviour
with regression coverage; **record an explicit exception** when production code must precede the red test; never
claim TDD without an observed meaningful red. Add the compact evidence block (seam / red command / observed
failure / why expected / minimal impl / green command / wider verification / exception). Tiny changes reuse
existing phase artifacts rather than spawning an evidence file. `tests.md` + `mocking.md` gain the "gate function"
pre-action form and the complete-mock iron rule.

**`skills/diagnose/SKILL.md`** — add the evidence taxonomy (symptom · root cause · contributing condition ·
unverified hypothesis · confirmed evidence · unresolved uncertainty); **no repeated speculative fixes without new
evidence**; revert failed speculative changes; **3-fix rule → stop and question the architecture**; first-bad-commit
analysis; report uncertainty honestly. Explicitly **not** an incident review — keep it proportionate. Preserve the
existing `unstick` boundary.

## Phase 3 — Verification + two-axis evaluator (commit 3)

**`executor.md`, `phase.md`, `wrap.md`** — verification must be **fresh after the final edit**: name the exact
command, paste deterministic result evidence, disclose warnings, disclose skipped checks, disclose unverified
assumptions. Ban "should work"/"probably fixed". Never substitute unit tests for a phase's required integration
check. Never claim success when required evidence is unavailable. **No new script. No new gate.**

**`evaluator.md`** — restructure the response:
```md
## Specification compliance      # active phase, Done-when, spec, missing/partial/unrequested behaviour,
                                 # weakened criteria, scope drift  (absorbs today's criteria-integrity check)
## Engineering quality           # correctness, maintainability, proportionality, failure behaviour, meaningful
                                 # tests, security, module boundaries (module-design vocabulary), architecture
                                 # fit, unnecessary complexity, docs alignment, regression risk, fakery
## Verdict
PASS                             # ← MUST remain the last non-empty line (record-grade.sh:32)
```
**A failure in either axis is `NEEDS_WORK`** — one axis may never excuse the other. Keep default-FAIL, untrusted-
input handling, the fakery list, `NO_TESTS_OK`. Document an **optional** dual independent review for high-stakes
milestones — never the default.

## Phase 4 — module-design + prototype (commit 4)

**`skills/module-design/`** — *model-invoked* (planner, executor, evaluator, `design-twice`, `mapme` must reach it).
Short trigger-focused description. Vocabulary: module · interface · implementation · **depth** · **seam** ·
adapter · **leverage** · **locality**. Principles: the **deletion test**; the interface is the test surface; one
adapter = hypothetical seam, two = real; accept dependencies, don't create them; return results over hidden
effects. Anti-goals: no pass-through abstractions, no premature generic interfaces, no speculative abstraction, no
forced rewrites, **project vocabulary wins over imported terminology**. Progressive disclosure → `deepening.md`.
A *discipline*, not a workflow, not a gate. Cross-referenced from `planner.md`, `executor.md`, `design-twice`,
`mapme`, `evaluator.md` — **never loaded wholesale into a session**.

**`skills/prototype/`** — *user-invoked* (`disable-model-invocation: true` → **zero** always-loaded cost; and
auto-firing "write throwaway code" inside a TDD-mandatory scaffold is actively harmful). One prototype answers
**one explicit question**, stated first. Throwaway and marked as such; **isolated from production/runtime paths**
(`/tmp`, a temp branch, or an isolated worktree) — not phrased against `src/`, which many projects don't use. One
command to run it. Surface the state. No persistence unless persistence is the question. Record question /
experiment / result / limitations / decision.

Evidence rule (precise): **prototype tests and outputs may serve as evidence for an explicitly scoped
prototype/research phase, but may never satisfy production implementation or release criteria.** The skill may
never tick; prototype code must be removed or explicitly archived; no debug routes or temporary interfaces left in
production. Transfer only validated learning into SPEC / ADR / roadmap.

**`jaimitos-os/CLAUDE.md`** — one clause reconciling the always-loaded TDD mandate: prototypes are the sanctioned
exception — throwaway, isolated from production/runtime paths, never accepted as production implementation
evidence. (~120 B.)

## Phase 5 — review-feedback + glossary + mapme (commit 5)

**`skills/review-feedback/`** — *user-invoked* (`disable-model-invocation: true`, zero context cost). Nothing covers
this today. Read every comment → map to file/behaviour/spec → **classify** each as: correct and actionable ·
correct but out of scope · misunderstanding · already addressed · conflicting with another comment · unsafe ·
architecturally harmful → verify each against current code, tests, spec, architecture → group accepted changes →
add/update tests → re-run relevant verification → explain rejections factually. **Never comply blindly because a
reviewer has authority. Never modify completed roadmap history. Never tick.** No GitHub-specific automation.

**`skills/glossary/SKILL.md`** — sole `docs/GLOSSARY.md` authority preserved. Add: challenge ambiguous terms,
detect overloaded terms and one-name-two-concepts, compare stated terminology against actual code, stress-test with
edge cases, update resolved definitions immediately, record rejected terminology, keep definitions free of
implementation detail. Offer an ADR only when hard to reverse **and** surprising without context **and** a genuine
trade-off. `docs/decisions/` stays the sole ADR location.

**`skills/mapme/SKILL.md`** — flag architectural friction in `module-design` vocabulary (shallow modules,
pass-through layers, leaky seams, poor locality, oversized interfaces, hidden dependencies, shotgun surgery,
premature abstraction, domain-language mismatch, doc drift). Descriptive only — never refactors.

## Phase 6 — `skill-creator` (commit 6, maintainer-only)

`.claude/skills/skill-creator/SKILL.md` (+ `checks.md`), `disable-model-invocation: true`. Structurally excluded
from every install path. **Prefers improving an existing capability over creating one.**

Pre-creation analysis (problem · recurrence · existing coverage by skill/command/agent/script/rule/doc · invocation
mode · state mutation · artifact ownership · trigger collision · second-authority risk · install scope · context
cost · what evidence would show it useful).

**Refuses** when: an existing skill can absorb it · responsibility too broad · duplicates a workflow · creates a
second planner/executor · creates a second authority for ROADMAP/STATE/SPEC/glossary/ADRs/evaluation/completion · a
command or deterministic script would be safer · a rule suffices · it is only static documentation · trigger
overlap · no checkable output · significant always-loaded context · **it exists only because upstream has it**.

On justification: emits skill dir, `SKILL.md`, valid current frontmatter, invocation classification, allowed/
prohibited tools, authority declaration, inputs/outputs/failure behaviour/completion criteria, progressive-
disclosure refs, catalog entry, install scope, attribution, provenance, deterministic tests, and the **Skill
creation report**. May **not**: auto-add to always-loaded context, create multiple skills when one suffices, copy
upstream without adaptation+attribution, install globally silently, tick, edit evidence/grades, touch completed
roadmap history, self-declare production-ready, or commit/push/tag.

## Phase 7 — `agent-creator` (commit 7, maintainer-only)

`.claude/skills/agent-creator/SKILL.md` (+ `checks.md`), `disable-model-invocation: true`. Same structural
exclusion. **Default posture conservative; `NO NEW AGENT JUSTIFIED` is a success.**

**Scope-aware.** It must first ask where the agent will live — `PROJECT` · `USER` · `PLUGIN` · `MANAGED` ·
`FIXTURE` — then emit only the fields valid for that scope, **warn about fields the scope ignores** (plugin
subagents ignore `permissionMode`, `hooks`, `mcpServers`), state the installation destination, and note the
restart/watch behaviour when a skills/agents directory is created for the first time. The scope×field matrix is
re-verified against official docs in Phase 0.

Enforces: current **camelCase** subagent frontmatter (`tools`, `disallowedTools`, `permissionMode`, `model`) — the
hyphenated skill fields are silently ignored in agents (`doctor.sh:118-143` already warns). Valid `model` values
only (`sonnet|opus|haiku|fable|inherit` or a full current model id) — **no hardcoded obsolete names**. Minimum
tools; explicit read/write boundaries; protected paths; deterministic output contract; orchestrator verification
step; stop conditions; retry policy; **empty/no-op detection**; prompt-injection resistance; context/token estimate.

**Refuses** when the role duplicates researcher/planner/executor/evaluator, would become a second phase planner,
shares implementation ownership, grades its own work, could be a skill or a script, has a vague output contract,
needs no unique context, encourages swarms, could mutate roadmap completion, could forge evidence/grades, has
unjustified write access, or costs disproportionately.

**Gate-integrity rule:** every `.claude/agents/*.md` is in `autopilot.sh`'s `GATE_CONTROL_FILES` — a new agent
definition **must** be added there, and `agent-creator` must say so.

## Phase 8 — Kill the duplicated catalogs, then lint (commit 8)

**This phase removes the maintenance problem rather than paying it again.** Today a new skill means hand-editing
two parallel lists and five prose counts. `install.sh:215-237` already writes every `.claude/skills/<name>/SKILL.md`
it copies into `.claude/.jaimitos-manifest`, so both lists can be **derived**:

- **`doctor.sh`** — replace the hardcoded `REQUIRED_SKILLS` (line 70) with the skill set **derived from
  `.claude/.jaimitos-manifest`**, then assert each still exists. This is strictly stronger: it detects a skill
  dropped or renamed *relative to what was actually installed*. No manifest (pre-2.5.0 install) → warn, as the
  existing no-`.claude/skills/` branch does.
- **`.github/scripts/install-smoke.sh`** — derive the expected set from `skills/*/` minus the global-only/
  maintainer exclusions, instead of restating it. Keep the **negative** assertions explicit and add the new ones:
  `setup-jaimitos-os`, `skill-creator`, `agent-creator` must NOT appear in the target.
- **Prose counts** — `skills/README.md` is the single authoritative catalog. `README.md` may keep a count (both are
  already checked by `test-docs.sh` check #1). Remove the *unchecked* counts from `CONTRIBUTING.md`, `GUIDE.md`,
  `SCAFFOLD.md` in favour of "the bundled skill catalog (see `skills/README.md`)", and **extend `test-docs.sh`
  check #1 to scan those three files too**, so a reintroduced stale count fails CI.

Then two new suites, registered in `run-guard-tests.sh` `TESTS[]` (its drift guard **fails the build** if a
`scripts/test-*.sh` exists unregistered — registration is mandatory). Style: `set -uo pipefail`, `pass`/`fail`
counters, `mktemp -d` + trap, bash 3.2-safe. Model on `test-release-check.sh` (runner shape) and
`test-docs-invariants.sh` (grep assertions reaching into `../skills/`).

**`jaimitos-os/scripts/test-skills.sh`** — objective failures only: duplicate skill names · `name:` ≠ directory ·
missing/empty description · description over the size cap · skill-vs-command name collision (`.claude/commands/`) ·
**every `skills/*/` has a row in `skills/README.md` and every row has a directory** (the catalog⇔directory
invariant that does not exist today) · adapted skills carry attribution · broken local refs · **maintainer-only
exclusion**: `install.sh`/`sync.sh` source roots never include root `.claude/` · `integrations/upstreams.lock.json`
is valid JSON with the required keys and every `jaimitos_files_influenced` path exists · **context budget**: each
model-invoked description ≤ cap and summed model-invoked description bytes ≤ a recorded ceiling.
Heuristic concerns (e.g. an overly broad description) **warn**, never fail.

**`jaimitos-os/scripts/test-agents.sh`** — duplicate agent names · missing description · **hyphenated skill-style
keys in an agent file** (the silent-no-op footgun) · invalid/unsupported `model` value · missing output contract ·
evaluator/reviewer holding `Write`/`Edit` · **every `.claude/agents/*.md` listed in `GATE_CONTROL_FILES`** · a
maintainer-only fixture agent validates, while invalid-frontmatter / unsafe-tool-boundary / missing-no-op fixtures
fail. **`name:` == filename is asserted as a *Jaimitos convention*** (for catalog and gate-integrity simplicity) —
the test comment must say so; Claude Code itself permits them to differ.

**`test-docs-invariants.sh`** (extend, grep assertions): tdd requires observed red + names the exception path ·
diagnose separates hypothesis from evidence and discourages speculative loops · executor requires fresh
verification · evaluator has both axis headings and "either axis fails → NEEDS_WORK" · evaluator's last-line
verdict contract is still `PASS` · prototype states its evidence rule and never ticks · review-feedback lists its
classifications · glossary is still the sole GLOSSARY authority.

**LLM judgement is never mandatory in core CI.**

## Phase 9 — Maintainer guide + catalog (commit 9)

`docs/dev/AUTHORING.md` — authoritative maintainer guide (skill vs agent vs command vs script; user- vs
model-invoked; short trigger-focused descriptions; progressive disclosure; one source of truth; explicit authority;
minimum tools; protected paths; output contracts; no-op detection; retry; context-cost measurement; trigger
collision; catalog consistency; provenance; behavioural dogfood; component removal and consolidation; avoiding
sediment and unnecessary splitting). **Includes the deterministic-vs-model-dependent table above.** Linked **only**
from `CONTRIBUTING.md`. Never added to `jaimitos-os/CLAUDE.md`; never installed.

Update `skills/README.md` (3 new rows + attribution), `README.md`, `CONTRIBUTING.md` (incl. an "Adding an agent"
section pointing at `AUTHORING.md`), `GUIDE.md`, `SCAFFOLD.md` — per the de-duplication rules in Phase 8.

## Phase 10 — Dogfood, then release metadata (commit 10)

Dogfood on real work and **fix what it finds before shipping**:
- **`skill-creator`** → author/revise **`module-design`**: inspect overlap, justify, generate, validate, update
  catalog + provenance, report context cost. Then review it **independently** — the creator does not self-approve.
- **`agent-creator`** → evaluate "should Jaimitos add a separate architecture-review agent?". Expected: **REFUSE** —
  evaluator + `module-design` + `design-twice` + `mapme` already own it. Record that it prevented proliferation.
- **`diagnose`** → on a real bug. Candidate found during research: `jaimitos-os/CLAUDE.md:42` cites
  `toolkit-docs/GUIDE.md`, but `install.sh:153-154` never installs `toolkit-docs/` — **a dangling reference in
  every user project**. Reproduce → root-cause → fix → regression test in `test-docs.sh`'s cited-path check.
- **`tdd`** → drive `test-skills.sh` / `test-agents.sh` red-first.
- **`module-design`**, verification-before-completion, the two-axis evaluator, **`review-feedback`**, **`prototype`**
  → exercised in the above. Record value / friction / redundancy / context overhead / whether each should remain.

Then `VERSION` → `2.10.0`, `CHANGELOG.md` (Added / Changed / provenance / MIT attributions), context-budget
before/after table, and the enforcement table.

---

## Context budget

**Measure at Phase 0 and again at Phase 10.** Acceptance: no large increase in always-loaded context.

| Surface | Before | After (expected) |
|---|---|---|
| `jaimitos-os/CLAUDE.md` (always-loaded) | 3,049 B | +~120 B (prototype clause) |
| `session-start.sh` injection | ~218 lines (60+60+40+30+20+8) | unchanged |
| Model-invoked skill descriptions | 15 shipped | **+1** (`module-design` only) |
| `prototype`, `review-feedback` | — | **0 B** (`disable-model-invocation: true`) |
| `skill-creator`, `agent-creator` | — | **0 B in any project** (maintainer-only, root `.claude/`, never installed) |
| `docs/dev/AUTHORING.md` | — | **0 B** (maintainer repo only) |
| Agent prompts | 4 | 4 (grown: evaluator two-axis, executor verification) |

Long guidance stays on demand: `module-design/deepening.md`, `tdd/tests.md`, `tdd/mocking.md`,
`skill-creator/checks.md`, `agent-creator/checks.md`. **Context cost is not solved by making instructions vague.**

---

## Verification

Every check must be green before the release is declared ready. Anything that cannot run is marked `NOT RUN` with
a reason.

```bash
bash jaimitos-os/scripts/run-guard-tests.sh < /dev/null      # now 21 suites (19 + test-skills + test-agents)
bash .github/scripts/install-smoke.sh
bash jaimitos-os/scripts/test-docs-invariants.sh
bash jaimitos-os/scripts/doctor.sh                           # against a freshly installed target
bash jaimitos-os/scripts/lint-roadmap.sh docs/ROADMAP.md
bash jaimitos-os/scripts/release-check.sh --prepare          # BEFORE tagging (--released is post-tag; not this release)

find . -name "*.sh" -not -path "./.git/*" -print0 | xargs -0 -n1 bash -n
bash .github/scripts/lint-shell.sh                           # shellcheck -S warning -e SC1090,SC1091 (BLOCKING in CI)
actionlint .github/workflows/ci.yml jaimitos-os/.github/workflows/jaimitos-os-ci.yml
jq empty jaimitos-os/.claude/settings.json integrations/upstreams.lock.json
```

**Install-exclusion proof (the load-bearing safety check):** after `bash install.sh <tmp-target>`, assert
`.claude/skills/skill-creator` and `.claude/skills/agent-creator` do **not** exist in the target — mirroring the
existing `setup-jaimitos-os` assertion at `install-smoke.sh:75`. Also assert `sync.sh` never re-adds them.

**Portability:** bash 3.2 / BSD *and* GNU. No `declare -A`, `mapfile`, `${x^^}`, `sort -V`. macOS CI asserts bash
3.2 (`ci.yml:92-96`). Re-run the guard suite **as non-root in a Linux container** before declaring CI green — GNU
vs BSD grep and root-bypasses-chmod have burned this repo before.

---

## Security review (completed at Phase 10)

New skill risks · new agent risks (none added) · protected-path behaviour · evaluator independence preserved
(`_eval-isolation.sh` untouched) · authority conflicts (none: no new artifact owner) · installer exclusion proven
by test · provenance trust (pinned SHAs, no auto-updater, no runtime network) · residual risks.

Untouched: `tick.sh`, `record-grade.sh`, `test-evidence.sh`, `_high-stakes.sh`, `_secret-scan.sh`,
`_eval-isolation.sh`, `_roadmap.sh`, `high-stakes-path-allowlist`. Gate integrity, secret scanning, high-stakes
checks and clean-tree checks are **not weakened**.

---

## Rollback

Every phase is one atomic commit leaving its targeted tests green. Revert granularity is per-commit; the branch is
never pushed until reviewed. The three new shipped skills are additive (delete the dirs + revert the catalog files).
The creators are additive and unshipped.

---

## Acceptance criteria

**Architecture** — one orchestrator, one planner, one implementer, one evaluator authority, one completion gate, no
competing queue. Creators are maintainer-only and cannot alter completion authority.
**Disciplines** — TDD requires observed red; debugging requires reproducible evidence and blocks speculative loops;
completion requires fresh verification; the evaluator separates spec from engineering quality and fails on either;
review feedback is validated not obeyed; `module-design` stays a discipline; `prototype` stays throwaway and never
satisfies production/release criteria; glossary stays singular.
**Creators** — prefer improving existing components; reject duplicates, second planners/executors, write-enabled
evaluators, vague contracts; require no-op detection; check gate-integrity impact; scope-aware; excluded from
installation.
**Reliability** — all existing + new tests pass; install smoke passes; sync safe; doctor accurate; gates fail-closed;
context measured; no maintainer-only component reaches project runtime; real dogfood evidence exists.
**Leanness** — no framework, no swarm, no unnecessary agent, no duplicate skill; long guidance on demand; every added
capability has one distinct responsibility; **no new hand-maintained duplicated list or count**.
**Honesty** — the deterministic-vs-model-dependent table is published; no guarantee is overstated.

Final report: starting architecture · adoption matrix · changes · creator results · verification evidence · security
review · dogfood report · enforcement table · updated rating (every category below 9 states exactly what prevents a
9) · release recommendation ending in `READY FOR RELEASE` or `NOT READY — BLOCKERS:`.
