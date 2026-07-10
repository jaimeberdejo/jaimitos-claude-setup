# PLAN — v2.6.0: Closing guarantees (evaluator symmetry, sandbox fail-closed, real scanner)

> **Status:** APPROVED (corrected), executing on branch `claude/new-session-7tbpgu` (restarted from
> the merged `master`, per the merged-PR rule — no stacking on already-merged history).
> **Source:** two v2.6.0 draft prompts, judged before execution. This PLAN records where the
> drafts' premises were wrong and what was decided instead.

---

## What the drafts got wrong (verified against the repo before writing this)

- **"Security code nobody has ever linted" (v2 Fase 1) — FALSE.** `.github/workflows/ci.yml`
  already runs `shellcheck -S warning -e SC1090,SC1091` over `install.sh`, `.github/scripts/*.sh`,
  `jaimitos-os/scripts/*.sh` (incl. `tick.sh`, `autopilot.sh`, `sync.sh`), hooks and libs, and
  CONTRIBUTING already mandates it. So the "diagnostic" framing is dropped. The genuine delta —
  `.shellcheckrc`, `shfmt` (absent), a convenience `scripts/lint-shell.sh` — is folded into the
  closure phase as **minor hardening**, not reported as findings.
- **Frontmatter audit (v2 Fase 0b) — NO-OP here.** `grep -l "allowed-tools\|disallowed-tools\|
  permission-mode" jaimitos-os/.claude/agents/` returns empty; the 4 agents use only `tools` /
  `model`. Nothing to fix. The preventive `doctor` check is kept, but as **`warn`, not `bad`**:
  the official docs (verified) confirm subagents use `tools`/`disallowedTools`/`permissionMode`
  (camelCase) and skills use `allowed-tools`/`disallowed-tools` (hyphenated), but do **not** state
  whether the CLI *rejects* or *silently ignores* a hyphenated field in a subagent. Unknown →
  `warn`. (Escalate to `bad` in a 2.6.x only if rejection is later confirmed empirically.)
- **Evaluator symmetry (both drafts' crown jewel) — REAL, but Option A as written is a footgun.**
  Confirmed: headless `autopilot.sh` has `cleanup_eval_changes` (`git reset --hard HEAD` + untracked
  `rm`); interactive `/phase` has no equivalent. BUT that mechanism is safe **only because headless
  runs in a throwaway worktree guaranteed clean before grading** — its safety is a property of the
  environment, not the mechanism. Replicating `reset --hard` + `rm untracked` in the user's LIVE
  checkout can eat uncommitted work. Decided: **conservative hybrid** (below).

## Severity note (corrected in review)
The evaluator has `Bash`; `>` is a Write by another name, and nobody watches the working tree
*during* a grade. The real vector is not a malicious grader but a **complacent** one: it re-runs
the suite, a test writes a fixture, the fixture makes the grade pass. `/phase` being "supervised"
does not cover this — detect-and-refuse does, documentation does not. This is the phase that matters.

---

## Scope (decision: lean + real v2 delta)
Fixes/hardening only, **zero new surface** (the two new flags are safety brakes, not features):
1. Evaluator isolation symmetry — the one broken guarantee.
2. Sandbox fail-closed + explicit parallel-independence assertion.
3. `LEAN_SECRET_SCANNER` opt-in real backend.
4. Closure: shellcheck delta (shfmt/.shellcheckrc/lint-script) + docs + CHANGELOG + VERSION.

Out of scope (deferred, with reactivation criteria in the CHANGELOG): statusline, MCP profiles,
monorepo, devcontainer, PR-level code-review, per-stack templates, `/audit-setup`, install
profiles, run-ledger JSONL, two-axis evaluator, context7 MCP, modern command frontmatter.

---

## Fase 1 — Evaluator isolation lib + interactive hybrid (the important one)

**New lib `jaimitos-os/.claude/lib/_eval-isolation.sh`** (sourced, not a hook), three functions:
- `eval_snapshot` → captures `EVAL_PRE_UNTRACKED` (`git ls-files --others --exclude-standard`),
  `EVAL_PRE_SNAP` (`git stash create` — empty ⇔ tracked tree clean; NON-destructive), and
  `EVAL_PRE_GRADE_HEAD`. Returns non-zero (fail-closed) if not a git repo / no HEAD → caller must
  NOT invoke the evaluator.
- `eval_restore` → **DESTRUCTIVE**, headless/throwaway-worktree only. Byte-identical behavior to
  autopilot's former `cleanup_eval_changes`: dirty-before-grading ⇒ STOP; evaluator-committed
  (HEAD moved) ⇒ `reset --hard PRE_GRADE_HEAD` + STOP; else `reset --hard HEAD` + remove only
  newly-created untracked; verify exact restoration or STOP. Same message strings the existing
  autopilot tests grep for ("evaluator COMMITTED during grading", …).
- `eval_changed_files` → **NON-DESTRUCTIVE detection**, interactive use. Compares current state to
  the snapshot (tracked: `git diff` between the snapshot's stash-ref/HEAD and a fresh
  `git stash create`; untracked: set difference), prints the exact files the evaluator touched
  (`[committed]` / `[modified] path` / `[created] path`), returns 1 if any, 0 if clean. Never
  touches the tree — a human is present and cleans up. Works even if the tree started dirty
  (user WIP is in both snapshots and cancels out).

**`autopilot.sh`**: source the lib; replace the inline `PRE_*` capture with `eval_snapshot` (+
fail-closed break if it returns non-zero) and the inline `cleanup_eval_changes` with `eval_restore`.
Behavior identical — verified by the existing `test-autopilot-gates.sh` (evaluator-commit detected,
edits discarded, ticks from clean tree).

**`commands/phase.md` step 6**: before invoking the evaluator subagent, run `eval_snapshot`
(fail-closed: if it fails, don't grade). After it returns, run `eval_changed_files`; if non-empty,
**refuse to report the phase clean / refuse to advance to `/wrap`**, print the exact file list, and
say the human must remove them and re-grade. Non-destructive. Also record the attempt in the log/
grade breadcrumb (`evaluator_wrote_files=1` in `.phase-grade` — a new `key=value` line that
`tick.sh`'s keyed greps ignore, so it can't break parsing).

**`test-eval-isolation.sh`** (added to run-guard-tests): (a) `eval_restore` returns the tree to the
prior state after a simulated writer; (b) untracked created files are cleaned by `eval_restore`;
(c) `eval_snapshot` fail-closed outside a git repo; (d) `eval_changed_files` names the exact files
(tracked-modified, untracked-created, committed) and returns 1, is silent+0 when clean, and does
**not** mutate the tree; (e) `eval_changed_files` works with a dirty (WIP) start.

**Done when:** lib owns the logic (autopilot doesn't duplicate it); the new test + existing
autopilot tests green; GUIDE documents that **both** modes isolate the evaluator, and exactly how
they differ (headless discards; interactive detects-and-refuses because it must not touch a live tree).

## Fase 2 — Sandbox fail-closed + parallel assertion + doctor frontmatter warn

- **Wrapper** `run-autopilot-sandboxed.sh`: add `-e JAIMITOS_SANDBOXED=1` so the container run
  carries the marker.
- **`autopilot.sh`**: when `--dangerously-skip-permissions` is set AND no sandbox signal
  (`JAIMITOS_SANDBOXED=1` **or** a container indicator like `/.dockerenv`) → **refuse**, unless
  `--i-understand-no-sandbox` is passed. Refusal names what's skipped + how to run the wrapper.
  With the override: run, print an unmistakable banner, log it to the run log. **No change** when
  `--dangerously-skip-permissions` is absent. Document both signals as *reminders, not a security
  boundary* (an env var is forgeable).
- **`/autopilot-parallel`**: require the literal phrase `I assert these phases are independent`
  (advisory — it's a command doc the model follows, stated as such). Move it under
  **"Advanced / experimental"** in README + GUIDE, listing its absent guarantees vs headless (no
  child watchdog, no retry; evaluator-change isolation now available via the Fase 1 lib — note it).
- **`doctor.sh`**: new `warn` if any `.claude/agents/*.md` uses a hyphenated skill-style field
  (`allowed-tools`/`disallowed-tools`/`permission-mode`) or another skill-only key — the canonical
  subagent spelling is camelCase, and a hyphenated field is (at best) a silently-ignored no-op, so
  the restriction you think you set doesn't exist. Kept even though the grep is empty today
  (preventive). Covered in `test-doctor.sh`.
- **`test-sandbox.sh`**: refusal without a sandbox signal; run with `--i-understand-no-sandbox` +
  banner; normal run inside the wrapper (signal present). Parallel-phrase check: test or
  documented manual verification in the commit.

## Fase 3 — `LEAN_SECRET_SCANNER` opt-in backend

- `_secret-scan.sh`: `LEAN_SECRET_SCANNER` ∈ {`regex` (default, unchanged), `gitleaks`,
  `trufflehog`}. `secret_scan_diff <range>` keeps the SAME contract + exit codes (0 clean / 1
  leak / 2 cannot-scan-fail-closed). Consumers (`tick.sh`, `commit-on-stop.sh`) untouched —
  verified by `grep -rn "secret_scan_diff"` before/after (same count, same files).
- Fail-closed: `gitleaks`/`trufflehog` selected but binary absent ⇒ return 2 (cannot-scan), never
  silent fallback to regex.
- gitleaks invocation (flags verified against the installed version; `detect`/`protect` deprecated):
  `gitleaks git --log-opts="<base>..HEAD" --report-format json --report-path <tmp> --redact
  --exit-code 1 --no-banner`; translate JSON findings to the lib's finding format, map exit 0→clean,
  1→leak. trufflehog only as an experimental extra (`--since-commit <base> --only-verified --fail
  --json --no-update`), with the documented base-not-ancestor caveat — validate the base commit first.
- `doctor.sh`: if `LEAN_SECRET_SCANNER != regex`, `bad` if the binary is missing; if `regex`,
  `info` that a reinforced option exists.
- `test-secret-scan.sh` (extended): default regex intact; `gitleaks` selected + binary absent ⇒
  fail-closed (rc 2); with a stub `gitleaks` on PATH ⇒ findings translated + correct exit code;
  `tick.sh`/`commit-on-stop.sh` unmodified with both backends.

## Fase 4 — Closure

- **Minor hardening (NOT a diagnostic phase):** `.shellcheckrc` (severity floor = warning);
  `scripts/lint-shell.sh` running `shellcheck` + `shfmt -d` over the toolkit's `*.sh`; add a
  `shfmt -d` step to CI (shellcheck already there). Any real shellcheck finding is fixed and noted;
  if none (expected, CI is already green), say so — no inventing findings. Every `# shellcheck
  disable=` needs a one-line justification.
- **CHANGELOG v2.6.0**: *Fixed* (evaluator asymmetry — described as the guarantee bug it is);
  *Added* (`--i-understand-no-sandbox`, parallel assertion, `LEAN_SECRET_SCANNER`, doctor checks,
  `shfmt`/lint-script); *Changed* (parallel → Advanced/experimental); *Deferred* (each with a
  reactivation trigger).
- GUIDE: the touched sections; Part 4 stays the security single source. README: one line on the
  opt-in scanner; parallel under Advanced. `VERSION` → 2.6.0. **No tag, no milestone close.**
- Run `test-docs.sh` (counts/paths may have moved).

## Order & verification
Fase 1 → 2 → 3 → 4. Fase 1 is the one that matters — if cut short, stop after it and let it merge
alone. Each phase: tests + atomic commit. Final: `doctor.sh`, `run-guard-tests.sh`,
`lint-shell.sh`, install-smoke on a clean target; summary of what changed, which test covers each
guarantee, what stayed out of scope and why.
