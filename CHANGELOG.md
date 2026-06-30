# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); this project
uses [Semantic Versioning](https://semver.org/).

## [1.0.3] — 2026-06-30

Second enforcement-hardening pass, driven by a multi-agent audit. Closes the remaining gaps
between the safety *claims* and the code that backs them, broadens the guards, and makes the
docs honest about which guarantees apply to which run mode. No breaking changes.

### Fixed — safety enforcement
- **High-stakes phases are no longer pushed by `--pr`.** Previously the high-stakes gate `break`d
  before ticking, but the builder's per-task commits were already in the branch and the finish
  block still ran `git push` + `gh pr create`. Now a high-stakes trip sets a flag and the branch
  **stays local even with `--pr`**. Guarded by a new behavioral test (`test-autopilot-gates.sh`).
- **Evaluator commits are now discarded too.** `cleanup_eval_changes` did `git reset --hard HEAD`
  (working-tree only); it now also detects a commit the evaluator made (HEAD moved during grading),
  reverts to the pre-grade HEAD, and STOPs.
- **Broadened high-stakes detection.** `HIGH_STAKES_RE` now matches `authentication/`, `oauth/`,
  `login`, `wallet`, `kyc`, `ledger`, and `delete`/`email`/`deploy`/`refund`/`webhook` — categories
  the docs named but the old regex missed. Regression-tested (`test-high-stakes.sh`).
- **Broadened secret scan.** Adds Stripe (`sk_live_`/`rk_live_`), Google (`AIza…`), and
  URL-embedded `user:password` credentials; `commit-on-stop` now fails **closed** if the scan lib
  is missing. The "never commits credentials" claim is scoped to "the shapes it recognizes."
  Regression-tested (`test-secret-scan.sh`).

### Changed
- **Honest, mode-scoped claims.** README/CLAUDE.md/LOOP-ENGINEERING now state that the deterministic
  sole-ticker / eval-discard / secret-scan / high-stakes-no-push guarantees hold in the **headless**
  `scripts/autopilot.sh`; the in-session `/autopilot` and `/wrap` have an independent grader but an
  advisory tick. Fixed the `/phase` "ticks on PASS" contradiction.
- **`Mode:` tag documented as advisory** (autopilot.sh does not parse it; the enforced control is
  the high-stakes path gate).
- **Ship-by-directory installer.** Toolkit docs moved to `lean-stack/toolkit-docs/` and excluded by
  directory (not a hardcoded filename list); `setup-lean-stack` is no longer copied per-project;
  `cp` failures now fail the install; installed version is stamped for `doctor.sh`.
- **Customization safety.** `setup-lean-stack` now edits the *enforced* `HIGH_STAKES_RE`, and
  `doctor.sh` warns when it's still the shipped default.
- **Shared libs moved** `.claude/hooks/_*.sh` → `.claude/lib/`; hooks read stdin without blocking on
  a TTY; `commit-on-stop` gained a `LEAN_CHECKPOINT=off` opt-out.

### Added
- `SECURITY.md`, `CONTRIBUTING.md`, a README Quickstart, a complete 10-skill index.
- CI now runs **shellcheck + actionlint** and the three behavioral guard tests.

## [1.0.2] — 2026-06-30

Enforcement-hardening pass: closes the gap between what the docs promised and what the code
actually enforces, fixes a real runtime crash, and stops the installer polluting target repos.
Driven by an independent multi-auditor review. No breaking changes to the manual workflow; the
headless loop's defaults changed (worktree isolation is now ON by default).

### Added — real enforcement
- **Shared guard libraries** `.claude/hooks/_secret-scan.sh` and `_high-stakes.sh`, sourced by
  both `commit-on-stop.sh` and `scripts/autopilot.sh` so the same guards run everywhere.
- **Content-aware secret scan:** beyond filename matching, high-confidence token regexes (AWS
  `AKIA`, PEM private-key blocks, `sk-`/`ghp_`/`xox*`) over the staged diff. `commit-on-stop`
  refuses to commit on a hit; `autopilot.sh` scans before its post-PASS commit and before any
  `--pr` push (the builder's per-task commits don't pass the Stop hook, so the push is gated too).
- **High-stakes gate in `autopilot.sh`:** a graded phase whose diff touches auth/money/migrations/
  etc. is **never auto-ticked/committed/pushed** — the loop stops for supervised review. The
  `paths:` in `high-stakes.md` and `HIGH_STAKES_RE` in `_high-stakes.sh` are kept in sync.
- **Evaluator-change cleanup (real independence):** `autopilot.sh` snapshots the tree before
  grading and **discards any file change the evaluator makes** before ticking — so a grader can't
  edit code into passing. Ambiguous/dirty pre-grade state → STOP, never tick.
- **`--no-worktree`, `--max-minutes` validation**, anchored numeric arg parsing (malformed counts
  like `5x`/`3-` are rejected, not silently ignored), and a `STEER.md` mirror into the worktree.
- **Root CI** `.github/workflows/ci.yml` + `.github/scripts/install-smoke.sh`: shell-syntax,
  `settings.json` validation, `install.sh` lint, and an install smoke test (no tool-doc pollution,
  no README clobber, idempotency, `.gitignore` merge). `test-hooks.sh` gained a secret-scan test;
  `doctor.sh` now flags any `<...>` placeholder and checks the shared libs.

### Changed — safer defaults
- **Worktree isolation is the DEFAULT** for `scripts/autopilot.sh`; opt out with `--no-worktree`
  (which runs in-place and warns loudly).
- **`format-on-edit.sh` is format-only** — dropped `ruff check --fix` / `eslint --fix`, which can
  silently change code semantics.
- **Installer no longer flattens toolkit docs** (GUIDE/LOOP-ENGINEERING/README) into targets. The
  scaffold's note ships as `SCAFFOLD.md` (can't clobber your README). CI is opt-in via `--with-ci`
  and ships as `lean-stack-ci.yml`.
- **Evaluator stderr → `autopilot.log`** (was `/dev/null`); the loop prints a log tail on an empty
  grade before stopping.

### Fixed
- **Final-phase crash:** removed `grep -c … || echo 0` in `tick_phase` (it produced `"0\n0"` and
  crashed the integer compare on the last phase). `grep -c` already prints a count.
- **`.phase-base` overwrite on retry:** `/phase` now preserves the phase base across NEEDS_WORK
  retries (only resets it for a genuinely new phase), so the evaluator's whole-phase diff and
  criteria-integrity check stay honest.

### Changed — docs & honesty
- Added an **"Enforcement reality"** section (GUIDE) — deterministic vs advisory layers; the
  `Bash(...)` denies are documented as a best-effort speed-bump, not containment; the real
  boundary for unattended runs is a sandbox/no-creds container.
- **Single-sourced** the hooks table (→ GUIDE), the skills catalog (→ `skills/README.md` /
  `OWNERSHIP.md`), and the guardrails theory (→ `LOOP-ENGINEERING.md`); other docs now point to them.
- Relabeled the **fabricated native `/goal` command** in `LOOP-ENGINEERING.md` as aspirational/
  unverified (hedged like `ENABLE_TOOL_SEARCH`). Standardized skill-vs-`/command` naming
  (`mapme` etc. are skills). Fixed `docs/STATE.md`'s next-action and reconciled both `.gitignore`s
  (added `!.env.example`/`!.env.sample`; dropped the stale `*.zip` rule).

## [1.0.1] — 2026-06-30

Hardening and documentation-consistency pass. No new features; safer defaults and
accurate docs.

### Changed — safety
- **Kill-switch fails closed:** `AGENT_STOP` blocks even if the hook itself errors.
- **Secret-leak prevention:** `commit-on-stop` won't stage/commit secret-bearing files;
  broadened the `permissions.deny` set and `.gitignore` coverage for `.env*`/keys/credentials.
- **Anchored verdict parsing:** the evaluator's PASS/FAIL is matched strictly — an
  unrecognized verdict stops the loop instead of being guessed.
- **Criteria immutability:** the builder is instructed not to edit the current phase's
  `Done when:`/heading, and the evaluator grades against a `.phase-base` snapshot so weakening
  the live criteria is detected, not rewarded (advisory + detection, not a hard block).
- **Test gate default-on in headless:** `autopilot.sh` runs with the test gate enabled.
- **Worktree kill-switch:** `AGENT_STOP` is honored inside `--worktree` runs.

### Fixed — install & health
- `install.sh` merges (not clobbers) an existing `.gitignore`.
- `doctor.sh` completeness: checks the hard dependencies (`git`, `jq`, `claude`) and reports
  what's missing.

### Changed — docs
- Added **Prerequisites** and **Troubleshooting** sections to the root README.
- Documented `autopilot.sh --allow-dirty`; marked `npx skills` / `openspec` as optional companions.
- Removed the dangling `personal-skills.zip` reference (skills live in `skills/`).
- Reconciled skill counts (6 workflow + 3 ownership + `setup-lean-stack`) and the roadmap
  phase-count wording (adaptive few/medium/many, not a hardcoded range).
- Softened the high-stakes "auto-loads" claim: path-scoped rule loading is unreliable, so the
  same constraints are kept in `CLAUDE.md`.

## [1.0.0] — 2026-06-30

First public release. A lean, project-neutral Claude Code operating system:
auto-maintained docs, deterministic hooks, an independent evaluator, two autonomous
loops (watchable + headless), path-scoped rules, and a pack of portable skills.

### Added — scaffold (`lean-stack/`)
- `CLAUDE.md` lean constitution; `docs/` source-of-truth set (SPEC, ROADMAP, STATE,
  ARCHITECTURE, decisions/, plans/).
- Commands: `/resume`, `/wrap`, `/phase` (research → plan → TDD → self-check; never
  self-ticks the roadmap), and `/autopilot N` (watchable in-session loop).
- `evaluator` subagent: fresh context, no edit tools, default-FAIL contract; the sole gate.
- Hooks: `session-start` (state re-injection incl. NEXT_FINDINGS), `steer` (mid-run
  redirect via JSON additionalContext), `kill-switch` (AGENT_STOP), `format-on-edit`,
  `test-gate` (opt-in deterministic TDD gate), `commit-on-stop` (honest checkpoint),
  `ownership-nudge`.
- `scripts/autopilot.sh`: fresh-process loop with preflight, strict verdict parsing,
  per-phase thrash cap, `--worktree`/`--pr` isolation, flexible count (`N`, `N-M`, `all`),
  and script-as-sole-roadmap-ticker (only on an independent PASS).
- `scripts/doctor.sh` health check, `scripts/test-hooks.sh` smoke tests, `.github/workflows/ci.yml`.
- `.claude/rules/high-stakes.md`: path-scoped extra care for auth/migrations/money/etc.
- `permissions.deny` covering secret reads (Read) and best-effort shell exfil (Bash).

### Added — install
- `install.sh`: idempotent, deterministic installer (copies scaffold + skills, chmods, runs
  doctor; `--force`, `--global-skills`). Copying static files stays deterministic — no model.

### Added — skills (`skills/`)
- Workflow: `roadmap` (spec → phases, adaptive count), `adr`, `ship-check`, `scope-guard`,
  `explain-diff`, `unstick`. The three review skills are report-only (`disallowed-tools`).
- Ownership: `teach-back`, `mapme`, `quizme`.
- Meta: `setup-lean-stack` — runs `install.sh`, then customizes CLAUDE.md/high-stakes for the
  detected stack (the only part that needs intelligence).

### Added — docs
- `README.md` (comprehensive entry), `lean-stack/GUIDE.md` (manual),
  `lean-stack/LOOP-ENGINEERING.md` (autonomous-loop theory),
  `PRACTICE-PROJECT.md` (standalone, deletable hands-on tutorial — kept out of `lean-stack/`
  so `install.sh` never copies it into real projects).

### Security
- Read-tool deny rules are a real boundary; Bash deny rules are documented as
  defense-in-depth (use sandboxing + `permission_mode: default` for the real shell boundary).
