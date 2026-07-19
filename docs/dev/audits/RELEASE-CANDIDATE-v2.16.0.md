# Release candidate evidence — v2.16.0

**Commit under test:** `ea7283f35015bc57da651a4b61bcd996803223f9` (`chore(release): v2.16.0`)
**Branch:** `release-6-consistency-proportionality`  ·  **VERSION:** `2.16.0`  ·  **Base:** `41677d4` (tag `v2.15.0`)
**Recorded:** 2026-07-19 (this evidence file is the only change committed after `ea7283f`; every result below
was produced against `ea7283f` with a clean tree).

> Honesty note: results are transcribed as run. First-run failures are **kept**, with the correction beside
> them. Nothing is reported as passing that was not run.

---

## 1. Environments

| Env | OS / arch | Bash | Userland | User |
|---|---|---|---|---|
| A (local) | Darwin 24.1.0 arm64 | **3.2.57** | BSD | interactive (macOS) |
| B (container) | Ubuntu (aarch64) | **5.3.9** | GNU | **non-root, uid 1001** |

Env A is the macOS bash-3.2 / BSD leg the CI `macos-checks` job mirrors. Env B is a fresh
`ubuntu:latest` container, repo copied to a `tester`-owned tree, both suites run as the non-root `tester`
user (`id -u` = 1001) — the Linux bash-5 / GNU / non-root leg. (A probe line printed `(root)` for the
username due to an unescaped `$(id -un)` expanding in the outer shell; `id -u`=1001 is authoritative and the
run was genuinely non-root.)

## 2. Suite results (all on `ea7283f`)

| Command | Env A (macOS 3.2) | Env B (Linux 5, non-root) |
|---|---|---|
| `bash jaimitos-os/scripts/run-guard-tests.sh </dev/null` | **exit 0** — all guard tests passed | **exit 0** — all guard tests passed |
| `bash .github/scripts/install-smoke.sh` | **exit 0** — PASS | **exit 0** — PASS |
| `bash jaimitos-os/scripts/release-check.sh --prepare` | **exit 0** — 1 warning (grandfathered pre-2.8.0 untagged releases), 0 errors | — |
| `find . -name '*.sh' -not -path './.git/*' -not -path '*/.claude/worktrees/*' \| xargs -n1 bash -n` | **63 scripts, 0 syntax errors** | (covered by run-guard chmod+syntax paths) |
| `shellcheck -S warning -e SC1090,SC1091 …` (CI flag set) | **clean** | — |
| `actionlint .github/workflows/ci.yml jaimitos-os/.github/workflows/jaimitos-os-ci.yml` | **clean** | — |

`run-guard-tests.sh` runs 28 suites, including the new `test-plan-review-route.sh` and the extended
`test-sync.sh` (case 20, resolved-conflict re-sync). The drift guard confirms every `scripts/test-*.sh`
is registered.

release-check `--prepare` on `ea7283f`: `VERSION (2.16.0) == newest CHANGELOG release` ✓; `[Unreleased]`
empty ✓; working tree clean ✓; `v2.16.0` not yet created (expected in prepare mode) ✓.

## 3. Portability — repo path containing spaces (Env A)

Installed with `--with-tests` into `…/dir with spaces/`, `git init`, then:
- `install.sh` → exit 0; `doctor.sh` → no `✗ missing` (only "not yet configured" warnings, expected);
- `plan-review-route.sh` → `ROUTE=DETERMINISTIC_ONLY` (correct); `test-plan-review-route.sh` → PASS.

## 4. Focused mutation checks (non-vacuity) — Env A

Each mutation was applied in place, the **named** test run, required to FAIL, then the file restored via
`git checkout`. The tree was verified clean after each run.

| # | Target (file) | Mutation | Named test | Result |
|---|---|---|---|---|
| 1 | `record-grade.sh` | invert the exact-`PASS` acceptance (`!=` → `=`) | `test-tick.sh` | **caught (test fails)** |
| 2 | `tick.sh` | widen evidence-schema gate `1\|2` → `1\|2\|99` | `test-tick.sh` | **caught** |
| 3 | `check-plan-freshness.sh` | neuter the `--strict` hard-fail (`miss > 0` → `miss > 999`) | `test-stale-plan.sh` | **caught** |
| 4 | `plan-review-route.sh` | disable high-stakes → FULL (`HS_SIGNAL = 1` → `= 9`) | `test-plan-review-route.sh` | **caught** |
| 5 | `plan-review-route.sh` | invalid tier no longer flagged (`TIER_VALID=0` → `1`) | `test-plan-review-route.sh` | **caught** |
| 6 | `classify-work.sh` (doc invariant) | reintroduce "enforcement ledger" on a scanned surface | `test-docs-invariants.sh` | **caught** |
| 7 | `VERSION` | bump to `9.9.9` (≠ CHANGELOG) | `release-check.sh --prepare` | **caught (exit 1)** |
| 8 | `install.sh` | drop the `diagnose` skill from the copy | `install-smoke.sh` | **caught (missing skill)** |

**First-run correction (kept):** mutation #1 first targeted `record-grade.sh`'s explicit `PLAN_*` reject
`case`. The test **still passed** — not because it is vacuous, but because that case is defense-in-depth: the
primary exact-`PASS` match (line 47) already refuses a `PLAN_PASS` last line, so removing the redundant case
does not change the outcome. Retargeted to the primary acceptance (row 1 above); then caught. This is itself
a finding: PLAN_* rejection is layered.

## 5. Context budget (always-loaded)

| Surface | Before (v2.15.0) | After (v2.16.0) |
|---|---|---|
| `CLAUDE.md` | 3140 B | **3140 B** |
| Model-invoked skill descriptions | 5173 B / 6000 B | **5173 B / 6000 B** |
| Agent descriptions | 1215 B / 2000 B | **1215 B / 2000 B** |
| **Total always-loaded** | 9528 B | **9528 B (+0 B)** |

`plan-review-route.sh` is a script and `/phase` a command — both load on invocation. No new agent, no new
always-loaded workflow. Well within the ≤250 B target.

## 6. Installed footprint

| Install | `scripts/test-*.sh` shipped | `run-guard-tests.sh` |
|---|---|---|
| default (`install.sh <t>`) | **2** (`test-evidence.sh`, `test-hooks.sh`) | absent |
| `--with-tests` / `--with-ci` | **29** (full guard suite) | present |

Default installed footprint drops by ~27 files. `sync.sh` verified to NOT re-add the suite to a lean
project and to leave sourced libs non-executable after an update. File modes vs `v2.15.0`: only the two
intended lib demotions (755→644) and the two new executable scripts; no unexpected mode change.

## 7. Verdict inputs

All guard + install + adversarial (mutation) + portability checks pass on `ea7283f` across macOS bash 3.2
and Linux bash 5 non-root; shellcheck + actionlint clean; evidence is bound to the exact release commit; no
test result predates it. Remaining warning is the pre-2.8.0 grandfathered untagged releases (accepted, not
retro-tagged). **No tag / push / merge performed — that is the operator's checkpoint.**
