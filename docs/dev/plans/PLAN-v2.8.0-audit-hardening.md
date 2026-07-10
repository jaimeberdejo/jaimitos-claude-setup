# PLAN — v2.8.0 audit hardening

> **Status:** APPROVED for execution (operator, 2026-07-10). Phases 0–2 complete; executing phase by phase.
>
> **Source audit:** `docs/dev/audits/jaimitos-claude-setup-audit-2026-07-10.md`
> **Audited revision:** `07bba1c` · **Base revision:** `1037985` (master, `VERSION=2.7.0`)
> **Branch:** `worktree-audit-fixes` (fast-forwarded onto master v2.7.0)
> **Planned by:** Claude (Opus 4.8), 8 parallel verification agents + direct orchestrator verification

**Goal:** Close the defects that break the unattended-execution safety story, plus the second-tier
integrity gaps, without adding a database, service, workflow engine, cryptographic ledger, or any
enterprise abstraction — and without weakening a single existing safeguard to make a test pass.

**Architecture:** Every fix stays inside the existing model: Git + files for state, one deterministic
completion gate (`scripts/tick.sh`), manifest-based conservative sync, small composable skills, narrow
shell scripts. Two new *narrow* shell components (`_roadmap.sh`, `.claude/test-command`) each **remove a
competing source of truth** rather than adding a subsystem.

**Tech stack:** POSIX-ish bash (must run on **bash 3.2.57 / BSD userland** and GNU/Linux), `git`, `jq`,
`grep -E`, `awk`. No new dependencies.

---

## Rebase note — what changed under this plan (base moved 2.4.0-era → 2.7.0)

This plan was first drafted against `9324fa1`. While it was in review, a **concurrent session released
jaimitos-os v2.7.0** and merged it to master (`1037985`). v2.7.0 acted on the *earlier* v2.6.0 audit with
a minimum-safe-cut: it **removed `/autopilot-parallel`** (their WS4 = this plan's **H6 — now DONE**), added
a partial dirty-tree guard in `record-grade.sh` (their G12, partially overlaps **H5**), added a dbt test
runner, retired `explain-diff`/`ship-check`, and made accuracy fixes.

The branch has been fast-forwarded onto `1037985`. Re-verification against the new base (grep + targeted
reproduction) confirms the files behind **C1, C2, H1, H2, H3, H4, N-1, N-2, N3** were **untouched** by
v2.7.0 — those findings are unchanged. Adjustments folded in below: **H6 removed** (done); **H5 reconciled**
with the new `record-grade.sh` check; the finding matrix statuses re-confirmed on `1037985`.

## Operator decisions folded in (2026-07-10)

- **D1 — Version `2.8.0`, conditional on a safe migration** (Phase 4). Migration: seed
  `.claude/test-command` **only from persistent repo config**, never from a transient `LEAN_TEST_CMD`
  process env; reject empty / `true` / `:` / `exit 0`; print the exact command + source; on
  missing/conflicting/ambiguous/invalid source **leave the file absent and fail closed** with an exact
  remediation command; **never overwrite** an existing `.claude/test-command`; test idempotency and
  that a transient env override is not persisted. *If these guarantees can't be met cleanly, stop and
  report the compatibility issue rather than weakening fail-closed behavior.*
- **D2 — Delete `/autopilot-parallel` outright.** No repo-root `experimental/`, no `--with-experimental`
  flag, no experimental installer branch, no retained tests/docs. **Already done by v2.7.0** — this plan
  only verifies the deletion is clean and keeps the general `merge-conflicts` skill with parallel-mode
  framing removed (v2.7.0 already retargeted it; confirm).
- **D3 — Do not retro-tag `v2.5.0`/`v2.6.0`.** Let `v2.8.0` supersede them; add a release-history note
  listing which recorded versions were never tagged. The release check (Phase 7.6) **grandfathers**
  pre-2.8.0 missing tags (warn, never permanently fail) and, from 2.8.0 on, requires `VERSION` ↔ newest
  CHANGELOG release ↔ tag consistency; at release time it verifies `v2.8.0` points at a commit whose
  `VERSION` and newest CHANGELOG release both equal `2.8.0`. **No tag is created or pushed without
  explicit approval.**
- **D4 — H3 residual: document + narrow guard.** Detect+remove newly-created ignored paths during
  evaluation (as planned); additionally **detect modifications to pre-existing sensitive ignored files**
  (`.env`, `.env.*`, `.netrc`, `*.pem`, `*.key`, `id_rsa*`, `credentials*.json`, `*.tfvars`) and refuse.
  Never recursively hash dependency/cache trees (`node_modules/`, `.venv/`, `.pytest_cache/`, build
  caches — these remain available and untouched). Document that arbitrary modification of *every* possible
  pre-existing ignored file is not structurally detectable under this lean snapshot design. **H3 stays Medium.**

## Operator corrections folded in

- **C-A — Sandbox export must fail closed** (Phase 3). No "warn then exit with the container's success
  status." Always attempt to import `autopilot/*` refs (even after a partial container failure); if refs
  were created but can't be imported, **exit non-zero**; preserve the staging clone on export failure and
  print its exact recovery path; delete the clone only after a successful export *or* after proving no
  work was produced. Test: non-fast-forward conflict, pre-existing same-name branch, container failure
  after a commit, export failure after a successful container exit. **Work must never vanish behind a warning.**
- **C-B — C1 stays Critical until fixed.** stderr disclosure improves docs, not the boundary. C1 is
  **Critical** until the clean-workspace implementation passes its adversarial tests. *(Matrix updated.)*
- **C-C — Define the first-phase anchor transition exactly** (Phase 4). `start-phase.sh` **creates a
  small deterministic anchor commit itself**, containing only the phase-floor + authorized-test-command
  metadata, with a predictable commit message. The builder starts **only after** the anchor is committed;
  the exact anchor commit and judged range are printed; rerun is idempotent or fails clearly; the builder
  cannot advance the floor without visible gate-control tampering. No ambiguous dirty state left behind.
- **C-D — Read-only subagent hygiene** (recorded in §Execution notes). For Bash-capable verification
  agents: use an isolated temporary clone/worktree, **or** remove Bash alongside Write/Edit — never rely
  on a prose "don't write" instruction with unrestricted Bash on the primary worktree.

---

## Global constraints

- Prefer narrow fixes over redesigns. Keep complexity proportional to the risk solved.
- Do **not** add databases, services, workflow engines, dependency-heavy frameworks, cryptographic
  ledgers, or enterprise abstractions.
- Preserve: the Git/file-based state model; the single deterministic completion gate in `scripts/tick.sh`;
  conservative manifest-based synchronization; the small, composable skill model.
- Do **not** weaken existing safeguards to make tests pass. Do **not** edit tests into accepting unsafe behavior.
- Every security or trust-boundary change **must** have a regression test that **fails before the fix and
  passes after**.
- Use temporary repositories / worktrees / fixtures for destructive tests. Never run irreversible external
  actions, deployments, payments, emails, or webhooks as part of testing.
- Do **not** modify the audit document to hide or reclassify unresolved findings.
- Target env floor: **bash 3.2** (no `local -n`, no associative arrays, no `${var^^}`, no `mapfile`) and
  **BSD userland** (`sed -i ''`, no `readlink -f`, no `grep -P`, no `stat -c`).
- **Execution discipline:** test-first; one coherent commit per phase; do not stop for approval between
  ordinary phases. **Stop only if** a planned invariant proves impossible, the safe migration can't
  support 2.8.0, a fix needs materially more complexity than budgeted, or a destructive/external
  action/push/tag/release would be required. **No tags, pushes, PRs, or releases without separate
  explicit approval.**

---

# Phase 0 — Baseline (COMPLETE)

## 0.1 Repository state (at execution)

| Item | Value |
|---|---|
| Branch | `worktree-audit-fixes` (isolated worktree, fast-forwarded onto master) |
| Base HEAD | `1037985` — `merge: jaimitos-os v2.7.0` |
| `VERSION` | `2.7.0` (→ `2.8.0` at Phase 7.7) |
| Tags | up to `v2.4.0` — **`v2.5.0`, `v2.6.0`, `v2.7.0` untagged** |
| Working tree | clean except the two untracked deliverables (audit + this plan) |

## 0.2 Baseline checks (run on macOS 24.1.0, bash 3.2.57, BSD userland)

| # | Command | Exit | Result |
|---|---|---:|---|
| 1 | `bash -n` over all `*.sh` | 0 | **PASS** |
| 2 | `bash .github/scripts/lint-shell.sh` | 1 | **FAIL** — finding N-1 (§0.4) |
| 3 | `actionlint` both workflows | 0 | **PASS** |
| 4 | `jq empty settings.json` | 0 | **PASS** |
| 5 | `run-guard-tests.sh` | 0 | **PASS** (re-run green on `1037985`) |
| 6 | `install-smoke.sh` | 0 | **PASS** (re-run green; itself uses `mktemp -d`, does not pollute) |
| 7 | `lint-roadmap.sh` | 0 | **PASS** |

The environment ran everything the audit could not (§9.4 of the audit): `shellcheck`, `actionlint`, the
guard suite, install-smoke, and Docker. Only `shfmt` was unavailable (advisory-only in CI).

## 0.3 Skipped checks / limitations

| Check | Status | Reason |
|---|---|---|
| `shfmt -d` | SKIPPED | not installed; advisory in CI (`ci.yml:44`, `continue-on-error`) |
| GNU grep behaviour | PARTIAL | only BSD grep locally; invalid-regex `rc=2` is POSIX-mandated (portable by contract). Re-verified on Linux CI in Phase 7.5. |
| Live Claude Code flow | NOT RUN | prose executed by a live model; all autopilot repros used a **stubbed `claude` on PATH** |
| Full Docker image | NOT BUILT | daemon up + used; C1 exposure proven with a cheap `alpine` bind-mount. Building `Dockerfile.autopilot` is a Phase 4 adversarial-verification step. |

## 0.4 Finding N-1 — `lint-shell.sh` fails on a clean tree (not in the audit)

`.shellcheckrc` declares `severity=warning`, but **`severity` is not a supported `.shellcheckrc` key** —
shellcheck silently ignores it (proven: `disable=SC2015` from the same file takes effect; `severity=bogusvalue`
draws no complaint). So `lint-shell.sh:29` (bare `shellcheck`) exits 1 on 375 `info`+3 `style` findings,
while `ci.yml` passes `-S warning` and exits 0. The rc file's comment claims the opposite. Fixed first
(Phase 1a): every later phase relies on this gate.

---

# Phase 1 — Findings matrix (COMPLETE, re-confirmed on base `1037985`)

Reproductions used isolated temp Git repos, obviously-fake secrets (`AKIAIOSFODNN7EXAMPLE`), stubbed
`claude`, and never touched the audited tree.

## 1.1 Critical / High

| ID | Finding | Status on 2.7.0 | Reproduction | Severity | Phase |
|---|---|---|---|---|---|
| **C1** | Ignored secrets mounted into bypass sandbox | **Open** (sandbox untouched by 2.7.0; still `-v "$PWD":/work`) | ignored `.env` readable at `/work`, exit 0; tracked symlink → ignored secret also leaks (N-3) | **Critical** (per C-B) | 3 |
| **C2** | Headless autopilot builds supervised phases before stopping | **Open** (no `Mode` parse in `autopilot.sh`) | stubbed builder ran+committed on `Mode: supervised`; `tick.sh` refused only after | **High/Critical** | 2 |
| **H1** | Manual `.phase-base` advanceable to hide commits | **Open** (`tick.sh` still trusts `.phase-base`; 2.7.0's record-grade change does not establish origin) | base A→B (later ancestor) turned `REFUSED exit 1` into `✓ ticked exit 0`; secret unscanned | **High** | 4 |
| **H2** | Agent can weaken the test command | **Open** (resolver unchanged; `settings.json`/`package.json` still not gate-controlled) | `LEAN_TEST_CMD=true` → green evidence over a red suite → full tick | **High** | 4 |
| **H3** | Evaluator isolation ignores gitignored files | **Confirmed, Medium** | `eval_changed_files` rc 0 after evaluator writes `generated/`, `.pytest_cache/`, `tmp/test.db`; `eval_restore` leaves them | **Medium** | 5 |
| **H4** | Invalid `HIGH_STAKES_RE` fails open | **Open** (no compile check in `_high-stakes.sh`) | `'['`/`'('`/`'*'`/`'a\'`/`'[z-a]'`/`'\'` → rc 1 (=no match); `doctor.sh` prints green | **High** | 1 |
| **H5** | Manual tick completes with a dirty tree | **Partially addressed by 2.7.0** — `record-grade.sh` now refuses a dirty **tracked** tree at *grade* time (`--untracked-files=no`). **Still open**: `tick.sh` has no check; the window between grade and tick is unguarded; **untracked** secrets are excluded. | uncommitted-after-grade + untracked-secret cases still tick | **High** | 1 |
| **H6** | `/autopilot-parallel` self-contradiction | **DONE by v2.7.0** — command + test removed; all four coupling points (`doctor.sh`, `install-smoke.sh`, `run-guard-tests.sh`, `test-docs-invariants.sh`) already updated; `merge-conflicts` retargeted | — | — (verify only, Phase 6) |

## 1.2 New findings — not in the audit

| ID | Finding | Status | Severity | Phase |
|---|---|---|---|---|
| **N-1** | `.shellcheckrc severity=` unsupported → `lint-shell.sh` fails clean-tree; comment claims otherwise | **Confirmed** | Medium (dev-tooling trust) | 1a |
| **N-2** | `tick.sh:292` `update_state` unchecked; `:293` prints `✓ ticked`, `:294` `exit 0` → failed STATE write **reports success** | **Confirmed** (unchanged on 2.7.0) | High (silent false success) | 1 + 7 |
| **N-3** | Sandbox scan defeated by a **tracked, unignored symlink** → ignored secret; defeats even the audit's "scan all files" fallback | **Confirmed** | High (compounds C1) | 3 |
| **N-4** | Audit's own H4 fix (`return 2`) **still fails open**: `tick.sh:231` `if HS=$(high_stakes_match …)` treats rc 2 like rc 1 | **Confirmed** | — (corrects the audit) | 1 |
| **N-5** | `.claude/settings.json` is manifest-managed yet a trusted test-command input | **Confirmed** | Medium (compounds H2) | 4 |

## 1.3 Corrections to the audit (folded into the relevant phases)

Sandbox mount is **`/work`** not `/workspace`; C1 fix needs `git clone --local` not `git worktree add`
(pointer `.git` breaks in-container) **and** an explicit export step (the live mount is today the only
channel commits use to reach the host); H4 `return 2` is insufficient (N-4); H3's disposable per-evaluator
worktree is rejected (no `node_modules`/`.venv` in a fresh checkout); the false pre-build-supervised
promise is in **`GUIDE.md`** (README is honest); only **`SECURITY.md`** overclaims the sandbox (the wrapper
is honest).

## 1.4 Tier-3 items (all independently verified)

N3/5.7 checkpoint index reset — **Confirmed** (Phase 7.0; a test currently blesses it). N4/6.8 lint gaps —
**Confirmed**, ship the 3 deterministic checks (Phase 7.2). N5/5.3 installer points at advisory mirror —
**Confirmed** (Phase 1.3). 5.6 install swallows doctor exit — **Confirmed**; `doctor.sh:318-337` already has
the three states, just propagate (Phase 7.3). 5.10 CONTRIBUTING names 3 tests, CI runs 17 — **Confirmed,
still open on 2.7.0** (Phase 7.4). N6/5.9 Linux-only CI — **Confirmed, no real portability defect** (Phase
7.5, regression insurance). 6.10/L4 release check — **Confirmed** (Phase 7.6). 7.4/L5 ownership-skill
opt-out — **Rejected** (not additive; `doctor.sh:70` REQUIRED_SKILLS would fail). L1/L2 image pinning +
resource limits — **Deferred** (audit: only after isolation). L3 live smoke — **Deferred**.

## 1.5 Already-satisfied (must not regress)

Dev docs never ship (`install.sh:30` scaffold scoping + `install-smoke.sh:40-42`); empty `HIGH_STAKES_RE`
fails safe (`_high-stakes.sh:69-72`); missing lib fails closed (`tick.sh:206-207`); "no tests" needs
evaluator `NO_TESTS_OK` (`tick.sh:167-169`); `git add -A` never stages ignored files.

---

# Phase 2 — Implementation plan

## 2.1 Scope

**Fixed:** N-1, H4+N-4, H5+N-2, C2, C1+N-3, H1, H2+N-5, H3, N3, and the doc/lint items (N4, N5, 5.6, 5.10,
N6, 6.10). **H6 is already done** — Phase 6 becomes a verification-only step. **Deferred:** L1, L2, L3, N4's
heuristic checks. **Rejected:** H3's per-evaluator worktree, an autopilot-parallel rewrite, crypto signing,
any DB/service/engine, manual↔headless trust-equivalence, L5 opt-out.

## 2.2 Invariants (each has a regression test in §2.5)

1. **I1** ignored credentials absent inside the sandbox workspace.
2. **I2** symlink → excluded secret does not expose it in the sandbox.
3. **I3** a `Mode: supervised` phase never invokes the headless builder (count = 0).
4. **I4** missing/duplicate/invalid `Mode:` on the next phase fails closed.
5. **I5** the phase start cannot be advanced by the builder without visible, refused gate-control tampering.
6. **I6** the authorized test command cannot be silently weakened mid-phase.
7. **I7** absent test-command config fails closed; never silently autodetects on the graded path.
8. **I8** evaluator-created ignored paths detected (interactive) + removed (headless); pre-existing
   dependency trees preserved; **pre-existing sensitive ignored files (D4 list) modified → detected + refused**.
9. **I9** malformed `HIGH_STAKES_RE` fails closed in matcher, `tick.sh`, `autopilot.sh`, `doctor.sh`.
10. **I10** `tick.sh` refuses a dirty checkout (tracked or untracked), exempting only gitignored runtime artifacts.
11. **I11** a failed STATE write never yields exit 0 / `✓ ticked`.
12. **I12** ROADMAP/STATE updated atomically-or-repairably; inconsistency has a deterministic repair path.
13. **I13** every completion still routes through `scripts/tick.sh` (must not regress).
14. **I14** sync never overwrites local customizations (must not regress).
15. **I15** historical audit/plan docs never ship into a target install (must not regress).
16. **I16** a checkpoint secret-scan abort leaves the user's pre-existing staged set exactly as it was.
17. **I17** sandbox export never loses produced work: created `autopilot/*` refs are imported or the wrapper
    exits non-zero with the staging clone preserved and its recovery path printed (C-A).
18. **I18** `start-phase.sh` leaves no ambiguous dirty state: it commits a deterministic anchor, prints it
    and the judged range, is idempotent-or-fails-clearly, and the builder starts only after the commit (C-C).

## 2.3 Phase breakdown

Each phase leaves the repo green (`lint-shell` + `run-guard-tests` + `install-smoke`) and is one coherent commit.

### Phase 1a — Trustworthy local lint gate (N-1)

**Files:** `.shellcheckrc`, `.github/scripts/lint-shell.sh`

- [ ] Prove: `bash .github/scripts/lint-shell.sh; echo $?` → `1`.
- [ ] Fix `lint-shell.sh:29` → `shellcheck -S warning "${FILES[@]}"`; delete the false `severity=` line +
      comment in `.shellcheckrc`, keep `disable=SC1090,SC1091`, add a note that the floor is CLI-only and
      lives in both `lint-shell.sh` and `ci.yml`.
- [ ] Verify `bash .github/scripts/lint-shell.sh; echo $?` → `0`; CI-parity command → `0`.
- [ ] Commit: `fix(lint): .shellcheckrc has no severity key — put the warning floor in lint-shell.sh`

### Phase 1 — Immediate fail-closed fixes (H4+N-4, H5+N-2, N5, doc truth)

**Interfaces produced:** `high_stakes_match`/`high_stakes_content_match` → three-state `0` matched / `1`
clean / `2` config error; `hs_regex_valid <regex>` → 0/1 (reused by `doctor.sh`).

Verified idiom (bash 3.2 + BSD grep; POSIX-portable by contract, re-checked on GNU in 7.5):
`hs_regex_valid() { printf '' | grep -Eiq "$1" 2>/dev/null; [ $? -le 1 ]; }`

- [ ] **1.1 Three-state matcher (I9).** Failing test in `test-high-stakes.sh`: 6 malformed regexes → rc 2;
      empty → rc 0 (must not regress). Implement the `hs_regex_valid` guard (`return 2`) in **both** matchers.
      **Fix every caller (N-4):** `tick.sh:231` and `:240` become explicit `case $hs_rc in 0) exit 3;; 1) : ;; *) refuse ;;`;
      `autopilot.sh:300-304` sourcing block fails closed on a bad matcher. `doctor.sh:168-182`: if
      `! hs_regex_valid`, `bad` (non-zero) **before** the fingerprint compare, replacing the green
      "customized" for a non-compiling regex.
- [ ] **1.2 Clean-tree refusal + checked STATE write (I10, I11).** Exemption set = `git status --porcelain`
      (already omits ignored files; every runtime artifact is gitignored — verified). Failing tests in
      `test-tick.sh`: tracked-mod → refuse; untracked non-ignored → refuse; ignored-only dirty → still ticks;
      read-only `docs/STATE.md` → non-zero, no `✓ ticked`. Implement the porcelain gate after HEAD resolve
      (~`:145`) **before** the scan; make `update_state` return non-zero on failure and `tick.sh:292` →
      `update_state "$heading" || refuse "STATE update FAILED after ROADMAP tick — run 'doctor.sh --state'"`.
      **Reconcile with 2.7.0:** `record-grade.sh` already refuses a dirty *tracked* tree at grade time; the
      new `tick.sh` gate is stronger (also untracked) and closes the grade→tick window. Keep both; note the
      relationship in the tick.sh comment.
- [ ] **1.3 Documentation truth (no code change).** `tick.sh:184` comment (can narrow — H1); `SECURITY.md`
      sandbox claim scoped to tracked/unignored; `GUIDE.md:489-491` pre-build promise scoped to in-session
      `/autopilot` until Phase 2; `install.sh:265-268` next-steps name `_high-stakes.sh`'s `HIGH_STAKES_RE`
      **first** (N5), rule file second.
- [ ] Commits: `fix(high-stakes): malformed HIGH_STAKES_RE fails closed in matcher AND every caller`;
      `fix(tick): refuse a dirty checkout; never report success on a failed STATE write`;
      `docs: stop claiming guarantees the code does not yet make (H1, C1, C2, N5)`

### Phase 2 — Shared phase parser + supervised pre-build (C2, I3, I4)

**Create** `_roadmap.sh` (fail-closed: duplicate headings; missing/duplicate/invalid `Mode:`; zero tasks;
out-of-block `Mode:`/tasks — awk only, no Markdown dep). **Interfaces:** `roadmap_first_open_heading`
(rc 2 ambiguous), `roadmap_phase_mode` (rc 2 invalid), `roadmap_open_count`.

- [ ] Failing I3 test in `test-autopilot-gates.sh` (the one the audit says is missing): supervised first
      phase + builder stub touching `$MARKER`; assert marker absent, no `-p /phase`, no `--agent`, not ticked.
- [ ] Write `_roadmap.sh` starting from the correct parser at `close-milestone.sh:47-53`; add fail-closed checks.
- [ ] Add the pre-build gate to `autopilot.sh` between `:463` and `:489`, mirroring the canonical spec in
      `.claude/commands/autopilot.md:19-28`; **missing/invalid Mode → refuse to build** (not the old
      "missing = loopable" default).
- [ ] Repoint `tick.sh`, `close-milestone.sh`, `lint-roadmap.sh`, `session-start.sh` at the lib; delete the
      duplicated awk. Add `.claude/lib/_roadmap.sh` to `GATE_CONTROL_FILES` (`autopilot.sh:364`) and update
      `test-autopilot-gates.sh` test #18. Register `test-roadmap-lib.sh` in `run-guard-tests.sh` `TESTS[]`.
- [ ] Commit: `fix(autopilot): refuse to build a Mode: supervised phase; one fail-closed roadmap parser`

### Phase 3 — Sandbox workspace isolation (C1, N-3, I1, I2, I17)

**Files:** `sandbox/run-autopilot-sandboxed.sh` (replace scan-then-mount-live-dir), `test-sandbox.sh`
(invert the assertion that certifies the unsafe behavior), `SECURITY.md`, sandbox headers.

- [ ] Failing adversarial tests: ignored `.env`/`*.pem`/`id_rsa`/`.netrc`/`credentials.json`/`secrets/`
      **absent** from mount; **tracked symlink → ignored secret** target unreadable (N-3); repo path with
      spaces/colon/glob/leading-hyphen still works; **commits made in-container reach the host** (export);
      clean workspace unconstructable → wrapper exits non-zero, no `docker run`.
- [ ] Implement `git clone --local --no-hardlinks` staging repo (self-contained `.git`, no ignored files,
      dangling symlink) + belt-and-braces basename scan over the staging tree.
- [ ] **Export, fail-closed (C-A, I17):** run the container; **always** attempt
      `git fetch "$STAGE/repo" 'refs/heads/autopilot/*:refs/heads/autopilot/*'`, even after a partial
      container failure. If the fetch fails **while `autopilot/*` refs exist in the staging clone**, **exit
      non-zero**, **preserve** the staging clone, and print its exact recovery path. Delete the staging clone
      **only** after a successful export **or** after proving no `autopilot/*` ref was produced. Never exit
      with the container's success status when refs were created but not imported.
- [ ] Extra export tests (C-A): non-fast-forward conflict on import; a pre-existing same-name `autopilot/*`
      branch; container failure *after* a commit (refs still imported); export failure *after* a successful
      container exit (→ non-zero, clone preserved).
- [ ] Document truthfully in `SECURITY.md`: clean tracked-only clone; `ANTHROPIC_API_KEY` still passed and
      the agent **necessarily has access to that credential**.
- [ ] Commit: `fix(sandbox): mount a clean tracked-only clone; fail closed on export so work is never lost`

### Phase 4 — Trusted phase-start anchor + test-command binding (H1, H2, N-5; I5, I6, I7, I18)

**Create** `scripts/start-phase.sh`, `.claude/test-command`. **Modify** `_test-cmd.sh`, `test-evidence.sh`,
`tick.sh`, `autopilot.sh:364`, `doctor.sh`, `install.sh:113-118`, `sync.sh:86-91`, `phase.md`, `wrap.md`.

**4a — one machine-readable test command (H2, N-5, D1):**
- Graded path reads **`.claude/test-command` only**. Autodetection survives **only** as a setup-time
  proposal written into that file (setup skill / `doctor --fix`), shown to a human.
- **Absent ⇒ fail closed** (`passed:null` + refuse), not "no tests". Sentinel `none: <reason>` represents
  no-tests and still requires the evaluator's `NO_TESTS_OK` (`tick.sh:167-169`).
- Reject `true`, `:`, `exit 0`, empty (D1).
- Add to `project_owned()` in **both** `install.sh:113-118` and `sync.sh:86-91` (they carry a keep-identical
  comment) and to `GATE_CONTROL_FILES`. Do **not** add `package.json`/`settings.json` there (they change
  mid-phase legitimately). Evidence records `command`, `source`, `config_sha`, `run_id`, `exit`, `passed`.
- **Migration (D1):** `sync.sh` seeds `.claude/test-command` on upgrade **only from persistent repo config**
  (`.claude/settings.json` `env.LEAN_TEST_CMD`, then manifest autodetect) — **never** from a transient
  `LEAN_TEST_CMD` process env; reject empty/`true`/`:`/`exit 0`; **print the exact command + source**; on
  missing/conflicting/ambiguous/invalid source **leave the file absent + fail closed with an exact
  remediation command**; **never overwrite** an existing file. `doctor --fix` seeds for non-sync installs.
  Tests: **idempotent re-seed**; **a transient `LEAN_TEST_CMD` env is NOT persisted**; existing file untouched.
  *If any of these can't be met cleanly → STOP and report the compatibility issue (do not weaken fail-closed).*

**4b — trusted phase-start anchor (H1, C-C):**
- `start-phase.sh` **creates a small deterministic anchor commit itself** containing only the phase-floor +
  authorized-test-command metadata, with a predictable message (e.g. `chore(phase-start): anchor <heading>`).
  Requires a clean tree; resolves the heading via `roadmap_first_open_heading`; **prints the exact anchor
  commit SHA and the `BASE..HEAD` range**; the builder starts only after the commit; rerun is idempotent
  (same open phase + clean tree → no-op with a clear message) or fails clearly.
- `tick.sh` derives the manual-mode base from the **tracked** anchor (falling back to `.phase-base` only if
  no anchor exists yet), keeping the `!= HEAD` + `--is-ancestor` checks; if `BASE..HEAD` modifies the anchor
  record → `exit 3` (gate-control tampering, same shape as `:225`). **Honest limit documented:** no local,
  Git-native, crypto-free mechanism is provably safe against a builder running arbitrary `git`; what this
  buys is tamper-evidence inside the judged range + a human-reviewed printed range. Manual mode's trusted
  actor is the human — the docs say exactly that.

- [ ] Failing tests: settings.json/package.json mid-phase mutation → refuse; absent file → refuse (no
      autodetect); `true` rejected; command changed start→tick → exit 3; **H1** floor advanced to later
      ancestor → still scans original range or refuses; `sync.sh` seeds once + never overwrites; **transient
      env not persisted**; rerun idempotent.
- [ ] Implement 4a, then 4b (4b's anchor captures the 4a command). Update `phase.md:32-46` to call
      `start-phase.sh` and `wrap.md:16` to print the judged range.
- [ ] Commits: `feat(test-command): one integrity-bound source of truth, safe-migrated`;
      `feat(phase-start): tick-authored, tamper-evident phase floor via a deterministic anchor commit`

### Phase 5 — Evaluator ignored-file isolation (H3, I8, D4)

**Files:** `_eval-isolation.sh`, `test-eval-isolation.sh`. Snapshot newly-appeared ignored set path-only via
`git ls-files --others --directory` (collapses `node_modules/`, `.venv/` cheaply). `eval_changed_files`
reports `[created-ignored] <path>` (rc 1); `eval_restore` removes **only** entries that appeared during
grading (never `git clean -fdx`).

**D4 sensitive-file guard:** at snapshot, hash the pre-existing sensitive ignored files matching
`.env`, `.env.*`, `.netrc`, `*.pem`, `*.key`, `id_rsa*`, `credentials*.json`, `*.tfvars` (a bounded,
non-recursive set — never dependency/cache trees). After grading, a changed hash → detected + **refuse**.

- [ ] Failing tests: created-ignored detected+cleaned; `node_modules/` preserved by restore; **pre-existing
      `.env` modified during grade → detected + refuse**; a cache tree modified → NOT hashed (stays available).
- [ ] Implement; keep the 7 existing cases green.
- [ ] **Document the residual precisely:** arbitrary modification of every possible pre-existing ignored file
      is not structurally detectable under this lean snapshot design; the guard covers the enumerated
      sensitive set only. H3 stays Medium.
- [ ] Commit: `fix(eval-isolation): detect ignored-file creation + sensitive-file tampering during grading`

### Phase 6 — Verify `/autopilot-parallel` removal is clean (H6 — done by v2.7.0)

Not a re-removal. **Verify** on this base: command + test gone; no dangling references in `doctor.sh`,
`install-smoke.sh`, `run-guard-tests.sh` drift guard, `test-docs-invariants.sh`; `merge-conflicts` skill
retained with parallel framing removed; `run-guard-tests.sh` + `install-smoke.sh` green. If any stale
reference remains, remove it (per D2 — no experimental copy, no flag). Likely a no-op + a CHANGELOG note.

- [ ] Grep-verify zero `autopilot-parallel` references outside `docs/dev/` (history/audits). Fix any leak.
- [ ] Commit only if changes are needed: `chore: confirm /autopilot-parallel fully removed`

### Phase 7 — State consistency, strict lint, docs, release prep (N3, N-2 repair, N4, 5.6, 5.10, N6, 6.10; I12, I16)

- [ ] **7.0 Preserve staging selection (N3, I16).** First **invert** `test-checkpoint.sh:54` (pre-stage a
      clean subset, assert it survives the abort). Then fix `commit-on-stop.sh`: snapshot
      `git diff --cached --name-only` before `git add -A`; on secret-scan abort, `git reset -q` then re-stage
      exactly the saved set (or scan the working tree without staging, staging only on a clean scan).
- [ ] **7.1 Atomic-or-repairable ROADMAP/STATE (I12).** Stage both temp files, validate, rename back-to-back;
      on failure before the second rename, restore ROADMAP. Add `doctor.sh --state`: every ticked phase in
      the STATE auto-block; exactly one active heading; floor is an ancestor of HEAD in the active phase;
      grade/evidence `run_id == HEAD`; milestone archive not half-transitioned; `NEXT_FINDINGS.md` coherent.
      Test injected failure between renames → detected + repaired; rerun idempotent.
- [ ] **7.2 Strict roadmap lint (N4).** Ship only the 3 deterministic checks via `_roadmap.sh`: unique
      headings; exactly one `Mode:` ∈ {loopable, supervised}; ≥1 task. Fixture each. Skip the heuristic ones.
- [ ] **7.3 Installer readiness (5.6).** `doctor.sh:318-337` already has three states; propagate: capture
      doctor's exit in `install.sh:279-287`, print one honest final banner, exit non-zero on blocking issues.
      Add the wording assertion `install-smoke.sh` lacks.
- [ ] **7.4 CONTRIBUTING (5.10).** Replace the "three behavioral guard tests" list (`:85-88`, `:93`) with
      `bash scripts/run-guard-tests.sh` (17 suites + drift guard). Still open on 2.7.0.
- [ ] **7.5 macOS/Bash 3.2 CI (N6).** Small `macos-latest` leg: `bash -n` + `run-guard-tests.sh`. Regression
      insurance (no current portability defect). Re-verifies the H4 idiom on **GNU** grep (closes §0.3).
- [ ] **7.6 Release-consistency check (6.10/L4, D3).** `scripts/release-check.sh`: (1) `VERSION` == newest
      non-`[Unreleased]` heading; (2) tag `v$VERSION` exists; (3) every released heading newer than the
      latest tag has a tag — **pre-2.8.0 misses (`v2.5.0`/`v2.6.0`/`v2.7.0`) are grandfathered → warn, never
      permanently fail**; (4) `[Unreleased]` empty at release; from 2.8.0 on, enforce (1)-(4); verify
      `v2.8.0` → commit whose `VERSION` and newest release both equal `2.8.0`. **Creates no tags.** Add a
      release-history note listing the untagged historical versions.
- [ ] **7.7 CHANGELOG + VERSION.** Fold `[Unreleased]` into `[2.8.0]`; **bump `VERSION` last**, only when all
      above is green. **No tag, no push, no PR without separate explicit approval.**

## 2.4 Files affected

`.shellcheckrc`, `.github/scripts/lint-shell.sh` (1a); `_high-stakes.sh` (1); `tick.sh` (1,2,4,7);
`doctor.sh` (1,4,7); `install.sh` (1,4,7); `SECURITY.md`/`GUIDE.md`/`README.md`/`CONTRIBUTING.md` (1,3,7);
**new** `_roadmap.sh` (2); `autopilot.sh` (2,3,4); `close-milestone.sh`/`lint-roadmap.sh`/`session-start.sh`
(2,7); `sandbox/run-autopilot-sandboxed.sh` (3); `_test-cmd.sh`/`test-evidence.sh` (4); **new**
`.claude/test-command` + `scripts/start-phase.sh` (4); `sync.sh` (4); `_eval-isolation.sh` (5);
`commit-on-stop.sh` (7.0); **new** `scripts/release-check.sh` (7.6); all named `test-*.sh` + `run-guard-tests.sh`;
`.github/workflows/ci.yml`, `.github/scripts/install-smoke.sh`. (No `autopilot-parallel.md`/test — already gone.)

## 2.5 Test strategy

Every security/trust change: a test that fails before, passes after. Adversarial cases per phase:
malformed regex sweep (rc 2, empty stays 0); dirty tracked/untracked → refuse, ignored-only → ticks,
read-only STATE → non-zero; supervised → no builder spawn, invalid Mode → no build, duplicate heading → rc 2;
ignored `.env`/symlink absent from mount, export non-ff / same-name branch / container-fail-after-commit /
export-fail-after-success → non-zero + clone preserved; `true` command / absent file / mid-phase mutation /
advanced floor → refuse, transient env not persisted, seed idempotent; created-ignored detected+cleaned,
`node_modules` preserved, pre-existing `.env` tamper → refuse; checkpoint abort preserves staged subset;
injected rename failure → repair; cross-platform on the macOS matrix leg.

## 2.6 Complexity budget

**Added:** `_roadmap.sh` (~60 lines) replaces **5** duplicated parsers; `.claude/test-command` (1 line) +
`start-phase.sh` (~50 lines with the anchor commit) **removes** 9 competing command sources; staging clone
(~20 lines with fail-closed export) replaces the live bind-mount; `git ls-files --others --directory` +
bounded sensitive-file hash (~15 lines) < the rejected per-evaluator worktree; `doctor --state` (~50 lines)
+ `release-check.sh` (~30 lines) are the only new *capabilities*. **Removed by v2.7.0:** `/autopilot-parallel`
(−392). **Not building:** general Markdown parser, DB/service/engine, crypto/ledger, parallel orchestrator,
per-evaluator worktree, YAML framework, run-ledger, more agents.

## 2.7 Version decision

**2.8.0**, conditional on the Phase 4 migration meeting D1's guarantees (else STOP and report — do not ship
a hard fail-closed that breaks existing installs without seeding). Removing `/autopilot-parallel` is already
released (v2.7.0). Untagged `v2.5.0`/`v2.6.0`/`v2.7.0` are grandfathered by D3; the release check enforces
consistency from 2.8.0 on. **No tag/push/PR/release without separate explicit approval.**

---

## Execution notes

- **Read-only subagent incident (C-D).** During Phase 0–2, a Bash-capable verification subagent — dispatched
  with a prose "read-only, do not modify the repo" instruction and unrestricted Bash on the primary worktree
  — ran `install.sh .` against the worktree (15:04), installing a full scaffold at the repo root and
  modifying the tracked `.gitignore`. Caught in a post-work verification; all 11 polluted paths were
  untracked; removed explicitly (not `git clean`, which would have taken the deliverables); `.gitignore`
  restored from git; guard suite + install-smoke re-run green. Baseline unaffected. **Corrective rule for the
  rest of execution:** Bash-capable verification/reproduction agents operate in an **isolated temporary
  clone/worktree**, or are dispatched **without Bash** (Read/Grep/Glob only) — never with unrestricted Bash
  on the primary worktree behind a prose no-write instruction.
- **Base moved during planning.** Plan rebased from `9324fa1` onto `1037985` (v2.7.0). H6 done; H5 partially
  addressed; matrix re-confirmed.
