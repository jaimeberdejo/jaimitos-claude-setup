# PLAN — v2.9.0 trust hardening

> **Status:** APPROVED for execution (operator, 2026-07-11). Phase 0 complete; executing phase by phase.
>
> **Source audit:** `docs/dev/audits/jaimitos-claude-setup-reaudit-2026-07-11.md` (score 8.2/10)
> **Base revision:** `1e11578` (master, `VERSION=2.8.1`)
> **Branch:** `worktree-audit-fixes` (isolated worktree)
> **Target:** `v2.9.0` — raise ≥ 9.0/10 by closing the reproduced trust gaps.

**Goal:** close the remaining concrete trust gaps without adding a database, service, workflow engine,
crypto ledger, or parallel-agent framework. Every fix stays in the Git/file model, routes completion
through the single `scripts/tick.sh` gate, and keeps the setup lean, auditable, and understandable.

**Env floor:** bash 3.2.57 / BSD userland AND GNU/Linux; `git`, `jq`, `grep -E`, `awk`. No new deps.

---

## Phase 0 — Baseline

### 0.1 Repository state (at execution)

| Item | Value |
|---|---|
| Branch | `worktree-audit-fixes` (isolated worktree) |
| Base HEAD | `1e11578` — `fix(ci): H4 malformed-regex test …` (= `master` = `origin/master`) |
| `VERSION` | `2.8.1` (→ `2.9.0` at Phase 7) |
| Newest CHANGELOG release | `[2.8.1] — 2026-07-11` |
| Tags | `v2.8.1`→`22be654`, `v2.8.0`→`cea876a`; master is **1 untagged commit ahead** of `v2.8.1` |
| Working tree | clean |

> Note: the worktree branch briefly carried 3 accidental test-pollution commits (from an H1
> reproduction whose `newrepo()` `cd` ran in a subshell); it was reset to `1e11578` before any
> production edit. This is the same "isolate destructive tests" discipline the v2.8.0 plan recorded.

### 0.2 Baseline checks (macOS 24.1.0, bash 3.2.57, BSD grep; GNU grep re-checked via Docker)

| # | Command | Exit | Result |
|---|---|---:|---|
| 1 | `bash -n` over all tracked `*.sh` | 0 | PASS |
| 2 | `bash .github/scripts/lint-shell.sh` | 0 | PASS |
| 3 | `actionlint` both workflows | 0 | PASS |
| 4 | `jq empty .claude/settings.json` | 0 | PASS |
| 5 | `run-guard-tests.sh` (claude stubbed) | 0 | PASS — 16 suites (recorded Phase 0) |
| 6 | `install-smoke.sh` | 0 | PASS |
| 7 | `lint-roadmap.sh docs/ROADMAP.md` | 0 | PASS |
| 8 | `release-check.sh` | 0 | PASS (1 grandfather warning) |

Tools available: `docker` 29.4.0, `shellcheck`, `actionlint` 1.7.12, `jq`, GNU grep via Docker
(Ubuntu 22.04, bash 5.1) — run the guard suite **as non-root** there (root bypasses `chmod`
failure-injection, spuriously failing the N-2 / state cases). Live `claude` CLI: not run.

---

## Phase 1 — Finding-validation matrix

Reproductions used isolated temp Git repos, fake secrets (`AKIAIOSFODNN7EXAMPLE`), stubbed
`claude`/`docker`/`gh`, and the audited clone — never destructive against the primary worktree.

| ID | Issue | Reproduction against `1e11578` | Observed | Severity | Fix? | Invariant enforced |
|---|---|---|---|---|---|---|
| **F1** | Autopilot `--pr` publishes an incomplete run | code-trace: ordinary-failure breaks (`autopilot.sh:534,545,602,611,628,692,699`) leave `RUN_ABORTED=0`/`HS_BLOCKED=0`; finish `--pr` push at `:721` reached | incomplete/ungraded run can push+PR | High | Yes | publish iff the complete requested run succeeded |
| **F2** | Sandbox loses work when `--no-worktree` forwarded | code-trace: exporter keys only on `refs/heads/autopilot/*` (`run-autopilot-sandboxed.sh:133`); `--no-worktree` commits on clone's branch → no `autopilot/*` → EXIT trap deletes clone | produced commits discarded | High | Yes | never delete any produced work; reject export-breaking options |
| **F3** | Manual anchor: test-command identity unbound + base narrowable (audit H1/H2/M3, I1) | reproduced: rewrote `.phase-anchor base=` to later ancestor, committed, re-ticked → secret hidden, **tick rc 0**; tick never compares anchor test_command | manual narrowing/test-swap succeeds | Med-High | Yes | anchor identity == evidence == current; anchor `base` = parent of its setting commit |
| **F4** | Partial ROADMAP/STATE completion (audit N2-residual) | code: `tick.sh` mutates ROADMAP then STATE; a STATE failure leaves ROADMAP ticked (rerun then refuses "no open items") | half-applied state | Med | Yes (Option 2) | both files change or neither; no `✓ ticked` until both succeed |
| **F5** | Checkpoint index not byte-exact (audit N3-residual) | code: `commit-on-stop.sh` re-adds whole files by name → partial staging / renames / mode / intent-to-add / conflicts lost | curated index not preserved | Low-Med | Yes | index tree-equivalent to pre-hook on abort |
| **F6** | Evaluator misses new file in pre-existing ignored dir (audit H3-residual) | analysis: `--directory` collapse hides a new file under an existing ignored dir; survives `eval_restore`, can affect post-grade evidence rerun | possible false pass | Low-Med | Yes (bounded) | configured fixture dirs are shallow-snapshotted |
| **F7** | release-check verifies tag existence, not identity/remote (audit M1) | reproduced: `git tag -f v2.8.1 <root>` → release-check still "✓ tag exists" rc 0 | wrong-commit tag passes | Low-Med | Yes | `--released` verifies tag→commit VERSION/CHANGELOG + remote |

Bonus (cheap audit wins): **L2** macOS CI asserts bash 3.2; **L4** root-guard the permission-injection tests.

---

## Phase 2 — Invariants, architecture, alternatives

### Invariants (each has a fail-before/pass-after regression test)
- **I-F1** a branch is pushed/PR'd only when the complete requested run finished successfully; a single authoritative `RUN_RESULT` defaults non-publishable.
- **I-F2** the sandbox never deletes produced work (any ref/HEAD/branch/detached/dirty/untracked); export-breaking options are rejected before the container runs.
- **I-F3a** manual tick refuses unless anchor-identity == evidence-identity == current-authorized test-command identity (source+command+config_sha).
- **I-F3b** the anchor's `base=` must equal the parent of the commit that last set `.phase-anchor`; else `exit 3` (closes narrowing + self-rewrite).
- **I-F3c** bounded high-confidence wrapped no-ops (`sh -c true`, `bash -c 'exit 0'`, only-`echo`/`printf`/`exit 0`) are rejected as graded commands.
- **I-F4** ROADMAP+STATE update atomically-or-rolled-back; no `✓ ticked` until both succeed; rollback failure preserves backups + prints recovery; leftover artifacts refuse.
- **I-F5** on checkpoint abort the Git index is tree-equivalent to pre-hook (all staging states); working tree unchanged.
- **I-F6** created/modified files under configured ignored fixture dirs are detected (interactive) / removed-or-STOP (headless); dependency/cache trees never recursed.
- **I-F7** `--released` fails unless the annotated `v$VERSION` tag points at a commit whose VERSION + newest CHANGELOG equal `$VERSION`; remote tag verified when origin exists.

### Architecture (all Git/file, no new subsystem)
Single-state publication decision (F1); pre/post ref inventory + option refusal (F2); extended tracked anchor schema + tick-time identity/parent checks (F3); in-`tick.sh` two-file backup/replace/rollback (F4); raw `.git/index` snapshot (F5); bounded shallow ignored-dir snapshot (F6); two release-check modes (F7).

### Alternatives rejected
Full `doctor --state` invariant/repair engine (deferred — Option 2 operator decision); disposable per-evaluator worktree (no `node_modules`); arbitrary command-equivalence; a DB/service/daemon/lock-server/workflow engine; parallel orchestration; crypto attestation.

---

## Phase 3 — Files affected

`scripts/autopilot.sh` (F1); `sandbox/run-autopilot-sandboxed.sh` (F2); `scripts/start-phase.sh`,
`.claude/lib/_test-cmd.sh`, `scripts/tick.sh`, `scripts/test-evidence.sh` (F3); `scripts/tick.sh` (F4);
`.claude/hooks/commit-on-stop.sh` (F5); `.claude/lib/_eval-isolation.sh`, new `.claude/eval-fixture-paths`,
`install.sh`, `scripts/sync.sh` (F6); `scripts/release-check.sh` + new `scripts/test-release-check.sh` (F7).
Tests: `test-autopilot-gates.sh`, `test-sandbox.sh`, `test-start-phase.sh`, `test-test-cmd.sh`,
`test-tick.sh`, `test-checkpoint.sh`, `test-eval-isolation.sh`, `test-release-check.sh`,
`run-guard-tests.sh` (register new). CI: `.github/workflows/ci.yml` (L2). Docs: README, SECURITY, GUIDE,
CONTRIBUTING, SCAFFOLD.md, CLAUDE.md, command docs, CHANGELOG, VERSION.

---

## Phase 4 — Test strategy

TDD: each fix gets a test that fails on `1e11578` and passes after. Adversarial batteries per §Phase 1
of the brief. Publication/gh/push invocations logged to an out-of-repo file (observable, not text-matched).
Permission-injection cases guarded with `[ "$(id -u)" -ne 0 ]`. Full guard suite green after every phase
on macOS bash 3.2 and non-root Linux (Docker).

---

## Phase 5 — Migration

`.claude/test-command` never overwritten; anchors lacking `test_config_sha` → tick prints a clear
re-anchor instruction (fail-closed); transient env never persisted; `.claude/test-command` +
`.claude/eval-fixture-paths` are project-owned in both `install.sh` and `sync.sh`; install/doctor output
stays accurate; migration idempotency tested.

---

## Phase 6 — Documentation & release

One authoritative security narrative (SECURITY/GUIDE), short summaries elsewhere. Document: the autopilot
publication contract; sandbox supported/rejected options + recovery; manual anchor identity + parent-check;
manual-vs-headless trust; ROADMAP/STATE rollback (and that the full `doctor --state` repair stays deferred);
exact index preservation; evaluator ignored-fixture residual; release-check prepare/released. `VERSION`→`2.9.0`;
`[2.9.0]` changelog; `[Unreleased]` emptied; install stamps 2.9.0. **No tag/push/PR.**

---

## Complexity budget

`RUN_RESULT` (~15) · export inventory (~30) · anchor identity + parent-check (~40) · rollback-safe
two-file transition (~40–70, **Option 2**: no `doctor --state`) · raw-index snapshot (~15) · shallow
fixture snapshot (~25) · release modes (~50). Not building: DB/service/daemon/engine, command-equivalence,
parallel orchestration, crypto.

---

## Ordered implementation phases (one green commit each)

1. F1 publication state. 2. F2 sandbox export. 3. F3 anchor identity + base check + no-op extension.
4. F4 rollback-safe transition (Option 2). 5. F5 exact index. 6. F6 eval fixtures + F7 release modes.
7. Docs, L2/L4 wins, migration tests, VERSION/CHANGELOG → 2.9.0, final adversarial battery.
