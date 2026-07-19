#!/usr/bin/env bash
# test-plan-review-route.sh — fixtures for scripts/plan-review-route.sh, the deterministic /phase plan-gate
# router. Proves the route table AND that each fixture's precondition actually holds (a clear-STANDARD
# fixture proves NO risk signal is present; a risky-STANDARD fixture proves the high-stakes path really
# matches HIGH_STAKES_RE; the hard-stale fixture proves check-plan-freshness --strict really fails) — so no
# case can pass vacuously. Also proves the ordinary path did not get heavier: TINY and clear-STANDARD return
# a non-FULL route + exit 0, i.e. the caller dispatches NO evaluator PLAN_CHECK.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTE_SH="$SCAFFOLD/scripts/plan-review-route.sh"
[ -f "$ROUTE_SH" ] || { echo "test: cannot find plan-review-route.sh at $ROUTE_SH" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-route)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
N=0

# mkproj <tier> <planned-path> — fresh NON-git project fixture (freshness stays "undetermined", exit 0, so
# only the tier + high-stakes + clarification signals are exercised); cds in. Empty <tier> = unset.
mkproj() {
  N=$((N+1)); local R="$WORK/r$N"; mkdir -p "$R/.claude/lib" "$R/docs/plans" "$R/src"; cd "$R" || exit 1
  cp "$SCAFFOLD/.claude/lib/_high-stakes.sh" "$SCAFFOLD/.claude/lib/_test-cmd.sh" .claude/lib/
  printf 'pytest -q\n' > .claude/test-command
  printf -- '---\nstatus: ready\ntier: %s\n---\n# Spec\n## Requirements\n### REQ-001 — x\n- AC-001: works\n' "$1" > docs/SPEC.md
  printf '# Plan\n\n## Change ownership\nPlanned writes: `%s`\nRequired reads: `docs/SPEC.md`\n' "$2" > docs/plans/p.md
}
# route <args...> — run the router, capture stdout + rc into OUT / RC
route() { OUT="$(bash "$ROUTE_SH" "$@" 2>&1)"; RC=$?; }
has()   { printf '%s\n' "$OUT" | grep -qF "$1"; }

echo "plan-review-route.sh tests"; echo ""

echo "TINY + benign path → SKIP, no evaluator dispatch (exit 0)"
mkproj TINY "README.md"
# precondition: the declared path is NOT high-stakes
if bash -c '. .claude/lib/_high-stakes.sh; high_stakes_match "README.md" >/dev/null 2>&1'; then
  fail "PRECONDITION broken: README.md unexpectedly matches HIGH_STAKES_RE"; else pass "precondition: README.md is not high-stakes"; fi
route --plan docs/plans/p.md --heading "## Phase 1"
{ [ "$RC" -eq 0 ] && has "ROUTE=SKIP"; } && pass "TINY clean → SKIP + exit 0 (no PLAN_CHECK)" || fail "TINY clean routing wrong (rc=$RC): $OUT"

echo ""
echo "TINY + high-stakes path → FULL + Supervised (a false/stale TINY cannot bypass real risk)"
mkproj TINY "src/auth/login.ts"
if bash -c '. .claude/lib/_high-stakes.sh; high_stakes_match "src/auth/login.ts" >/dev/null 2>&1'; then
  pass "precondition: src/auth/login.ts matches HIGH_STAKES_RE"; else fail "PRECONDITION broken: auth path not high-stakes"; fi
route --plan docs/plans/p.md
{ [ "$RC" -eq 10 ] && has "ROUTE=FULL_PLAN_CHECK" && has "Supervised: YES"; } \
  && pass "TINY + high-stakes → FULL + supervised + exit 10" || fail "TINY high-stakes not escalated (rc=$RC): $OUT"

echo ""
echo "Clear low-risk STANDARD → DETERMINISTIC_ONLY, no evaluator dispatch (exit 0)"
mkproj STANDARD "src/widgets/list.ts"
if bash -c '. .claude/lib/_high-stakes.sh; high_stakes_match "src/widgets/list.ts" >/dev/null 2>&1'; then
  fail "PRECONDITION broken: benign path matched high-stakes"; else pass "precondition: no risk signal present"; fi
route --plan docs/plans/p.md
{ [ "$RC" -eq 0 ] && has "ROUTE=DETERMINISTIC_ONLY" && has "Risk signals: none"; } \
  && pass "clear STANDARD → DETERMINISTIC_ONLY + exit 0 (agent review skipped)" || fail "clear STANDARD routing wrong (rc=$RC): $OUT"
has "PLAN_CHECK skipped" && pass "block states the independent PLAN_CHECK was skipped (not 'approved')" || fail "block does not state PLAN_CHECK skipped: $OUT"

echo ""
echo "Risky STANDARD (a forcing signal present) → FULL"
mkproj STANDARD "src/billing/charge.ts"
if bash -c '. .claude/lib/_high-stakes.sh; high_stakes_match "src/billing/charge.ts" >/dev/null 2>&1'; then
  pass "precondition: at least one forcing signal (billing path) present"; else fail "PRECONDITION broken: billing path not high-stakes"; fi
route --plan docs/plans/p.md
{ [ "$RC" -eq 10 ] && has "ROUTE=FULL_PLAN_CHECK"; } && pass "risky STANDARD → FULL + exit 10" || fail "risky STANDARD not FULL (rc=$RC): $OUT"

echo ""
echo "DEEP → FULL (always)"
mkproj DEEP "src/widgets/list.ts"
route --plan docs/plans/p.md
{ [ "$RC" -eq 10 ] && has "ROUTE=FULL_PLAN_CHECK"; } && pass "DEEP → FULL" || fail "DEEP not FULL (rc=$RC): $OUT"

echo ""
echo "Supervised → FULL (always), even a benign STANDARD"
mkproj STANDARD "src/widgets/list.ts"
route --plan docs/plans/p.md --supervised
{ [ "$RC" -eq 10 ] && has "ROUTE=FULL_PLAN_CHECK" && has "Supervised: YES"; } && pass "supervised → FULL" || fail "supervised not FULL (rc=$RC): $OUT"

echo ""
echo "Invalid tier value → FULL (fail-safe: a bad tier buys no reduced review)"
mkproj "BOGUS" "src/widgets/list.ts"
route --plan docs/plans/p.md
{ [ "$RC" -eq 10 ] && has "ROUTE=FULL_PLAN_CHECK" && has "invalid tier value 'BOGUS'"; } \
  && pass "invalid tier → FULL + flagged" || fail "invalid tier not fail-safe (rc=$RC): $OUT"

echo ""
echo "Unset tier → treated as STANDARD (documented default), routes on risk"
mkproj "" "src/widgets/list.ts"
route --plan docs/plans/p.md
{ [ "$RC" -eq 0 ] && has "Selected tier: STANDARD" && has "ROUTE=DETERMINISTIC_ONLY"; } \
  && pass "unset tier → STANDARD default → DETERMINISTIC_ONLY" || fail "unset tier not defaulted (rc=$RC): $OUT"

echo ""
echo "Blocking [NEEDS CLARIFICATION] → FULL"
mkproj STANDARD "src/widgets/list.ts"
printf '# Plan\n## Change ownership\nPlanned writes: `src/widgets/list.ts`\n[NEEDS CLARIFICATION] which endpoint?\n' > docs/plans/p.md
route --plan docs/plans/p.md
{ [ "$RC" -eq 10 ] && has "blocking [NEEDS CLARIFICATION]"; } && pass "blocking clarification → FULL" || fail "blocking clarification not FULL (rc=$RC): $OUT"

echo ""
echo "Hard-stale plan (invalid baseline) → FULL"
N=$((N+1)); GR="$WORK/g$N"; mkdir -p "$GR/.claude/lib" "$GR/docs/plans" "$GR/src"; cd "$GR" || exit 1
cp "$SCAFFOLD/.claude/lib/_high-stakes.sh" "$SCAFFOLD/.claude/lib/_test-cmd.sh" .claude/lib/
printf 'pytest -q\n' > .claude/test-command
printf -- '---\nstatus: ready\ntier: STANDARD\n---\n# Spec\n' > docs/SPEC.md
git init -q; git config user.email t@t.t; git config user.name t
printf '# Plan\nBaseline: deadbeef1234\n## Change ownership\nPlanned writes: `src/widgets/list.ts`\n' > docs/plans/p.md
git add -A >/dev/null; git commit -qm base
# precondition: check-plan-freshness --strict really fails on this fixture
if bash "$SCAFFOLD/scripts/check-plan-freshness.sh" --strict docs/plans/p.md >/dev/null 2>&1; then
  fail "PRECONDITION broken: freshness --strict passed on an invalid baseline"; else pass "precondition: freshness --strict fails (invalid baseline)"; fi
route --plan docs/plans/p.md
{ [ "$RC" -eq 10 ] && has "plan hard-stale"; } && pass "hard-stale plan → FULL" || fail "hard-stale not FULL (rc=$RC): $OUT"

echo ""
echo "Override integrity"
mkproj STANDARD "src/payments/charge.ts"
route --plan docs/plans/p.md --override deterministic
{ [ "$RC" -eq 10 ] && has "REFUSED"; } && pass "override to weaker on high-stakes → REFUSED (stays FULL)" || fail "high-stakes override not refused (rc=$RC): $OUT"
mkproj STANDARD "src/widgets/list.ts"
route --plan docs/plans/p.md --override skip
{ [ "$RC" -eq 0 ] && has "ROUTE=SKIP" && has "reason: MISSING"; } \
  && pass "reasonless override is structurally visible (reason: MISSING), not warn-only" || fail "reasonless override not visible (rc=$RC): $OUT"
mkproj TINY "README.md"
route --plan docs/plans/p.md --override full --reason "extra caution"
{ [ "$RC" -eq 10 ] && has "ROUTE=FULL_PLAN_CHECK" && has "reason: extra caution"; } \
  && pass "override to STRONGER review always honoured" || fail "stronger override not honoured (rc=$RC): $OUT"

echo ""
echo "A weaker override cannot waive the full review for ANY forcing signal (audit regression)"
mkproj DEEP "src/widgets/list.ts"
route --plan docs/plans/p.md --override skip
{ [ "$RC" -eq 10 ] && has "REFUSED" && has "ROUTE=FULL_PLAN_CHECK"; } && pass "DEEP + --override skip → REFUSED (stays FULL)" || fail "DEEP override not refused (rc=$RC): $OUT"
mkproj "BOGUS" "src/widgets/list.ts"
route --plan docs/plans/p.md --override deterministic
{ [ "$RC" -eq 10 ] && has "REFUSED"; } && pass "invalid tier + --override deterministic → REFUSED" || fail "invalid-tier override not refused (rc=$RC): $OUT"
mkproj STANDARD "src/widgets/list.ts"
printf '# Plan\n## Change ownership\nPlanned writes: `src/widgets/list.ts`\n[NEEDS CLARIFICATION] which?\n' > docs/plans/p.md
route --plan docs/plans/p.md --override skip
{ [ "$RC" -eq 10 ] && has "REFUSED"; } && pass "blocking clarification + --override skip → REFUSED" || fail "clarification override not refused (rc=$RC): $OUT"
N=$((N+1)); GO="$WORK/ov$N"; mkdir -p "$GO/.claude/lib" "$GO/docs/plans"; cd "$GO" || exit 1
cp "$SCAFFOLD/.claude/lib/_high-stakes.sh" "$SCAFFOLD/.claude/lib/_test-cmd.sh" .claude/lib/
printf 'pytest -q\n' > .claude/test-command
printf -- '---\ntier: STANDARD\n---\n# Spec\n' > docs/SPEC.md
git init -q; git config user.email t@t.t; git config user.name t
printf '# Plan\nBaseline: deadbeef1234\n## Change ownership\nPlanned writes: `src/widgets/list.ts`\n' > docs/plans/p.md
git add -A >/dev/null; git commit -qm base
route --plan docs/plans/p.md --override skip
{ [ "$RC" -eq 10 ] && has "REFUSED"; } && pass "hard-stale plan + --override skip → REFUSED" || fail "hard-stale override not refused (rc=$RC): $OUT"

echo ""
echo "The decision block never prints a false '[ok]' it did not verify"
mkproj STANDARD "src/billing/charge.ts"   # high-stakes → FULL; the DETERMINISTIC_ONLY checklist must not appear
route --plan docs/plans/p.md --override deterministic
{ [ "$RC" -eq 10 ] && ! has "[ok] no high-stakes path declared in the plan"; } \
  && pass "a forced-FULL phase prints no false '[ok] no high-stakes path' checklist" || fail "false [ok] attestation printed (rc=$RC): $OUT"

echo ""
echo "High-stakes detection: a bare multi-dot filename is not truncated"
mkproj STANDARD "auth.service.ts"
if bash -c '. .claude/lib/_high-stakes.sh; high_stakes_match "auth.service.ts" >/dev/null 2>&1'; then
  pass "precondition: auth.service.ts matches HIGH_STAKES_RE (truncated 'service.ts' would not)"; else fail "PRECONDITION broken: auth.service.ts not high-stakes"; fi
route --plan docs/plans/p.md
{ [ "$RC" -eq 10 ] && has "high-stakes path"; } && pass "auth.service.ts (bare multi-dot) → FULL (not truncated to service.ts)" || fail "multi-dot filename truncated, missed high-stakes (rc=$RC): $OUT"

echo ""
echo "Usage: missing --plan / nonexistent plan fail closed (exit 2)"
route --plan "$WORK/nope.md"; [ "$RC" -eq 2 ] && pass "nonexistent plan → exit 2" || fail "nonexistent plan not exit 2 (rc=$RC)"
route; [ "$RC" -eq 2 ] && pass "missing --plan → exit 2" || fail "missing --plan not exit 2 (rc=$RC)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All plan-review-route tests passed."; else echo "$FAILS plan-review-route test(s) FAILED."; exit 1; fi
