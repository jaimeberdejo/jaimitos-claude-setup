# Release candidate evidence — v2.17.0

Runtime & Lifecycle Integrity — a correction/hardening release. **No `RELEASE_AUDIT`** (deferred to
v2.18); no new agent; `scripts/tick.sh` stays the sole completion authority and the human the sole
publication authority.

Honesty note: first-run failures are kept below, not hidden — the full guard suite caught two
harness gaps (test-start-phase M4 binding, the shared-lib count) and an independent adversarial review
caught one real regression (the camelCase union); all three were fixed and are recorded here.

## 1. Baseline
- Starting tag/commit: `v2.16.0` = `e2861ae31bf2f5132258ea89a57e0bf91ca96f9c` (annotated, published;
  `origin/master == e2861ae`). Branch: `release-7-runtime-lifecycle-integrity`.
- Starting VERSION: `2.16.0`. Guard suite green at baseline.
- Initial always-loaded context: agent descriptions 1215/2000 B (researcher 296 / planner 238 /
  executor 232 / evaluator 449), **byte-identical at release** (no always-loaded growth).

## 2. Finding disposition (reproduced against source before fixing)

| Obj | Area | Verdict | Shipped fix |
|---|---|---|---|
| 1701 | Evaluator exit vs verdict (exits 1–123) | CONFIRMED | fail-closed `EVAL_RC != 0` before grade (`autopilot.sh`) |
| 1702 | Durable completion commit | CONFIRMED | checked add+commit + HEAD-contains assertion |
| 1703 | One phase identity/range | CONFIRMED | shared `_phase-range.sh` + CLI; all consumers unified |
| 1704/1710 | Grade/evidence binding | CONFIRMED | heading+base (evidence schema 3), tick validates + content_hash |
| 1705 | Native requirement handoff | PARTIALLY — linter already native (**contradicted**); guidance external-only | roadmap/evaluator/planner guidance aligned + native fixture |
| 1704 | Sync retired files | CONFIRMED | report-first reconciliation, `--prune`+confirm, path-safety |
| 1706 | Milestone closure transaction | CONFIRMED | `--name` validation + byte-identical rollback |
| 1707 | Install/portability | CONFIRMED | symlink resolve, global-skills exit, chmod, README flatten |
| 1708 | macOS watchdog locale | **CONTRADICTED premise** + minor finding | perl usability probe; C.UTF-8 proven non-fatal |
| 1709 | camelCase matcher | CONFIRMED | tokenization (union raw+normalized after review fix) |
| 1710 | Secret-history on push | CONFIRMED (default regex) | commit-by-commit scan |

## 3. Runtime integrity (M1/M2)
- **Evaluator exit:** `autopilot.sh` now fails closed on any nonzero `EVAL_RC` (1–123) BEFORE the
  verdict is parsed; the ≥124 watchdog band is unchanged. A grade requires `EVAL_RC==0` AND a final
  `PASS` AND a successful `eval_restore`. Manual `/wrap` passes only verdict text (human-trusted path).
- **Durable completion:** the completion commit is no longer `|| true`; `autopilot.sh` checks
  add+commit, asserts HEAD contains `docs/ROADMAP.md`+`docs/STATE.md`, and gates `RUN_RESULT="success"`
  on it. Failure → branch local, recovery printed, nonzero exit. The roadmap-complete break asserts the
  transition is in HEAD too.
- Negative fixtures (`test-autopilot-gates.sh`): PASS+exit{1,123} → no grade/tick/publish; failed
  completion commit (commit-msg hook) → ticked in working tree but not HEAD, not published, exit nonzero.

## 4. Phase identity & binding (M3/M4)
- Canonical manual source: tracked `.claude/.phase-anchor`; canonical headless source: orchestrator
  `TICK_BASE`. One resolver `.claude/lib/_phase-range.sh` (`TICK_BASE` → anchor → `.phase-base` +
  strict-ancestor + anchor base-integrity), CLI `scripts/phase-range.sh`. `tick.sh` delegates to it;
  the evaluator resolves its window from the CLI; `autopilot.sh` exports `TICK_BASE` so the evaluator
  and tick judge the identical range in headless too.
- Grade fields: `run_id, verdict, no_tests_ok, heading, base`. Evidence (schema 3): adds `heading, base`
  to the v2 set; `content_hash` verified by tick. `tick.sh` refuses on a heading/base mismatch or a
  stale unbound grade, and drops `.tick-evidence.json` on a successful tick.
- Negative fixtures (`test-tick.sh`, `test-phase-range.sh`): wrong base, wrong heading, unbound
  pre-v2.17 grade, wrong-base evidence, content_hash tamper, a valid-v3 positive; resolver precedence,
  empty/reversed/unresolvable/base==HEAD, anchor-narrowing → rc 3.

## 5. Traceability (M5)
Native `docs/SPEC.md` (`to-spec`) requirement sources are now first-class alongside external ones in
the roadmap skill, evaluator and planner guidance (the linter already resolved them — the hypothesis's
linter claim was contradicted). End-to-end fixture (`test-requirements.sh`): a phase whose `Sources:`
names `docs/SPEC.md` resolves its REQ+AC ids under `--strict`; an id removed from the SPEC or mistyped
in the phase fails `--strict`. The evaluator tracing each id to code/tests is model-dependent (see §10).

## 6. Migration (M6)
`sync.sh` retired-file matrix (`test-sync.sh`): unchanged retired → reported then `--prune`-removed +
manifest entry dropped; locally-modified retired → preserved (manual); locally-deleted → stale entry
dropped; `..` traversal and symlink retired paths → refused (never removed/followed); idempotent rerun.

## 7. Milestone closure (M7)
`close-milestone.sh` transaction (`test-close-milestone.sh`): `--name` missing (watchdog-guarded, no
hang) / empty / `..` / path-separator / newline / unknown-arg → exit 2, nothing archived; an injected
archive-move failure rolls back ROADMAP+STATE byte-for-byte (sha compared) with no archive, exit 1.

## 8. Installation & portability (M8)
- `install-smoke.sh`: a symlinked `install.sh` resolves its real repo and installs; a `--global-skills`
  install that can't write exits nonzero (no silent success). shipped lib/CLI present; footprint gate intact.
- `test-autopilot-gates.sh`: a broken-but-present perl falls through to `setsid` (run still ticks); the
  watchdog runs under `LANG=C.UTF-8 LC_ALL=C.UTF-8` (locale warning is non-fatal). OBJ-1708's
  locale-break premise is CONTRADICTED and recorded as such.
- README manual-copy uses `"${d%/}"` (guarded by `test-docs-invariants.sh`) so BSD `cp -r` nests skills.

## 9. Matcher & publication security (M9/M10)
- camelCase tokenization: `OAuthClient.ts`/`getUserSession.ts`/`secretManager.ts` now match; benign
  canaries (`coauthor`/`tokenizer`/`secretary`/`sessional`/`accountant`) stay clean; `author`/`authority`
  match by design. **Adversarial-review fix:** matching is a UNION of the raw and normalized path, so
  adversarially-cased keyword paths (`reFundOrder`, `deLeteUser`, `aUthProvider`) keep the coverage
  v2.16 had — the earlier normalized-only implementation was a false-negative regression, now fixtured.
  Identical decision at plan-review routing and tick (`test-plan-review-route.sh`).
- Secret history: default regex scans commit-by-commit; an AWS key added in commit A and removed in B
  (net-clean over BASE..HEAD) is caught (rc 1). Remains a prefix-matcher — `SECURITY.md` says so.

## 10. Live reference scenarios (M12)
The completion lifecycle is exercised end-to-end by the REAL scripts under `test-autopilot-gates.sh`
(the stubbed-`claude` harness runs the actual autopilot → builder → evaluator → record-grade →
test-evidence → tick → commit path in throwaway repos): TINY/clean, high-stakes→supervised (not
published), secret→refused, needs-work→findings, and the F1 positive publish. **Honest limitation:**
the fully model-driven `/phase` R→P→E→V flow (a real `claude --agent` session per stage) and the
evaluator's semantic requirement-tracing (M5) are model-dependent and are NOT run in this offline suite;
the deterministic lifecycle guarantees are what the fixtures prove.

## 11. Mutation evidence (non-vacuity)
Each fix ships a fixture that fails without it; representative embedded mutations proven non-vacuous:
`_phase-range.sh` dropping the `.phase-base` fallback → `test-phase-range.sh` case 10 fails; restoring
`git commit || true` → M2 gate test fails; breaking the camelCase normalization → camelCase positives
fail; a wrong-base grade/evidence → `test-tick.sh` M4 cases fail; a modified retired file being removed
→ `test-sync.sh` fails. No general mutation framework was built.

## 12. Context & maintenance cost
- No new permanent agent. New always-loaded surface: **none** — the resolver/binding/sync/closure logic
  is shell (`.claude/lib/_phase-range.sh`, `scripts/phase-range.sh`, scripts), loaded only when run;
  `evaluator.md`/`wrap.md`/`roadmap SKILL.md`/`planner.md` changes are all in BODIES. Agent descriptions
  byte-identical (1215/2000 B). CLAUDE.md unchanged.
- Files added: `_phase-range.sh`, `phase-range.sh`, `test-phase-range.sh`, ADR-011, ADR-012, this
  report, the plan. Tests added across 9 suites; installed footprint gains one lib + one script (both
  ship by default — the evaluator + tick need them), tests remain opt-in (`--with-tests`).

## 13. Independent review findings (author is not the sole reviewer)
Three independent reviews (subagents) ran against `v2.16.0..HEAD`.
- **BLOCKING → FIXED:** (Review B, adversarial) the camelCase matcher REPLACED the raw scan with a
  normalized-only scan, dropping coverage for adversarially-cased keyword paths (`reFundOrder` etc.) that
  v2.16.0 caught — a false-negative in the enforced high-stakes gate. **Fixed** by making the scan a
  union of raw+normalized, with regression fixtures. Re-verified.
- **NON-BLOCKING → FIXED:** (Review B, R1) `close-milestone --name` accepted an embedded newline (the
  `[[:cntrl:]]` grep is line-oriented). **Fixed** (exit 2 + test).
- **NON-BLOCKING → FIXED:** (Review C) the plan/CHANGELOG miscounted the agent-description budget as
  1015 B; actual 1215 B (descriptions unchanged from v2.16). **Corrected.**
- **ACCEPTED LIMIT:** (Review B, R2) secrets placed ONLY in a commit *message* are not scanned — a
  pre-existing vector, not introduced by v2.17, and the regex is prefix-based regardless. Documented.
- **ACCEPTED LIMIT / honest residual:** manual mode stays tamper-evident, not builder-proof (headless
  `TICK_BASE` is the trust-equivalent path); legacy v1/v2 evidence skips the evidence-side binding with
  a warning (the grade binding still blocks reuse). Both were confirmed by Review B as correctly bounded.
- **Review A (correctness):** every milestone verdict CORRECT at HEAD; no open correctness defect. Review
  A **independently** found the same M9 fail-open regression (naming `WebHookHandler.ts`/`stripeWebHook.ts`
  in addition to the refund/delete/auth casings) and confirmed `17bd7f2` fixes it, re-verifying the union
  at HEAD. Residuals it accepts as-is: the null-`content_hash` skip (advisory; headless evidence is
  integrity-checked + regenerated), the M1 break-before-`eval_restore` ordering (harmless — run stops, no
  publish), and no circular-symlink guard in `resolve_dir` (pathological). Confirmed no bash-3.2/BSD
  violations; ran the affected suite under bash 3.2.57.
- Two independent reviews (A + B) caught the M9 regression before release — the single most important
  finding, now fixed and double-verified.
- Reviews B and C independently confirmed: no duplicate canonical state (the resolver REPLACED tick's
  inline copy), no field without a consumer, no guarantee exceeding enforcement, no v2.18 leakage, no
  always-loaded growth, every change maps to an objective.

## 14. Final version
`VERSION DECISION: v2.17.0` — a minor release: new user-visible behaviour (a shared resolver, evidence
schema 3, a `sync --prune` flag, install/watchdog fixes, matcher + secret-scan hardening). Not a patch.

## 15. Verification (bound to release commit `4f159de`)
All of the following ran on the clean tree at `4f159de` (this report's own commit is docs-only on top, so
the behavioural evidence holds for the tip):
- macOS **bash 3.2.57 / BSD**: `run-guard-tests.sh` → **All guard tests passed** (28 suites, exit 0).
- Linux **bash 5.1.16(1) / GNU / non-root (uid 1000)** container: `run-guard-tests.sh` → **All guard
  tests passed** (exit 0).
- `.github/scripts/install-smoke.sh` → **PASS** (incl. symlinked installer + failing global-skills).
- `release-check.sh --prepare` → 0 errors (1 grandfathered-tag warning), VERSION 2.17.0 == newest
  CHANGELOG, clean tree, `v2.17.0` absent.
- `shellcheck -S warning -e SC1090,SC1091` over install + scaffold scripts/hooks/libs/sandbox → **exit 0**.
- `actionlint` on both workflows → **exit 0**.
- `bash -n` over every `*.sh` (excl. `.git`/worktrees) → **OK**.
- Focused mutations proven non-vacuous (§11). First-run failures encountered and fixed, not hidden:
  `test-start-phase` M4-binding gap and the shared-lib count (both caught by the full suite); the M9
  camelCase union regression (caught by two independent reviews). All re-verified green.

## 16. Release recommendation

Architecture: four permanent agents; no `RELEASE_AUDIT`; `tick.sh` sole completion authority; human sole
publication authority; no duplicate canonical state. Safety: the invariant holds — nonzero evaluator exit
cannot pass, a failed completion commit cannot publish, review/evidence/scan/tick share one range,
same-HEAD cross-phase reuse is refused, retired-file removal is opt-in+confirmed, closure rolls back
byte-for-byte, the high-stakes union restored the coverage the mid-branch regression dropped, and the
push scan is commit-by-commit. Proportionality/leanness confirmed by independent review; zero always-loaded
growth. Verification is complete on the exact commit across both platforms.

```
RELEASE VERDICT: READY TO TAG
```

Tag `v2.17.0` on the release commit only with explicit operator authorization. No push, tag, PR, merge or
publish has been performed.
