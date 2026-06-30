# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); this project
uses [Semantic Versioning](https://semver.org/).

## [1.0.1] — 2026-06-30

Hardening and documentation-consistency pass. No new features; safer defaults and
accurate docs.

### Changed — safety
- **Kill-switch fails closed:** `AGENT_STOP` blocks even if the hook itself errors.
- **Secret-leak prevention:** `commit-on-stop` won't stage/commit secret-bearing files;
  broadened the `permissions.deny` set and `.gitignore` coverage for `.env*`/keys/credentials.
- **Anchored verdict parsing:** the evaluator's PASS/FAIL is matched strictly — an
  unrecognized verdict stops the loop instead of being guessed.
- **Criteria immutability:** the builder can't edit the current phase's `Done when:`/heading.
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
