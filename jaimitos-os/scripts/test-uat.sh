#!/usr/bin/env bash
# test-uat.sh — fixtures for scripts/check-uat.sh, the lightweight user-acceptance ledger check.
# Proves: an all-passing (or non-blocking-failure) ledger is clean; a BLOCKING FAILED/BLOCKED item blocks
# a release under --strict; a non-blocking failure does not block; a DEFERRED item must be justified
# (Reason + Risk + Resolution); malformed/duplicate ids and invalid Status fail; and it never mutates.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHK="$SCAFFOLD/scripts/check-uat.sh"
[ -f "$CHK" ] || { echo "test: cannot find check-uat.sh at $CHK" >&2; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
ok()   { bash "$CHK" --strict "$1" >/dev/null 2>&1; }
blk()  { ! bash "$CHK" --strict "$1" >/dev/null 2>&1; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-uat)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

echo "check-uat.sh tests"; echo ""

CLEAN="$WORK/clean.md"
cat > "$CLEAN" <<'EOF'
# User Acceptance
Baseline commit: abc1234
Environment: staging

- UAT-001
  Requirement: AC-004
  Status: PASSED
  Blocking: YES
- UAT-002
  Requirement: AC-006
  Status: DEFERRED
  Reason: needs a real payment sandbox
  Risk: low — read-only path
  Resolution: PHASE-09
  Blocking: NO
EOF

echo "A clean ledger (passing + justified deferral) passes --strict"
ok "$CLEAN" && pass "clean ledger passes" || { fail "clean ledger rejected"; bash "$CHK" --strict "$CLEAN"; }

echo ""
echo "A missing ledger is inert"
bash "$CHK" --strict "$WORK/none.md" >/dev/null 2>&1 && pass "absent ledger exits 0" || fail "absent ledger not inert"

echo ""
echo "A BLOCKING FAILED item blocks the release"
F="$WORK/failed.md"; sed 's/Status: PASSED/Status: FAILED/' "$CLEAN" > "$F"
blk "$F" && pass "Blocking=YES + FAILED → --strict blocks" || fail "blocking failure not caught"
FOUT="$(bash "$CHK" "$F" 2>&1)"   # capture then grep (SIGPIPE+pipefail flake)
printf '%s\n' "$FOUT" | grep -q "blocks the release" && pass "the release blocker is named" || fail "blocker not named"

echo ""
echo "A BLOCKING BLOCKED item blocks the release"
B="$WORK/blocked.md"; sed 's/Status: PASSED/Status: BLOCKED/' "$CLEAN" > "$B"
blk "$B" && pass "Blocking=YES + BLOCKED → --strict blocks" || fail "blocking BLOCKED not caught"

echo ""
echo "A NON-blocking failure does not block the release"
NB="$WORK/nonblock.md"; sed 's/Status: PASSED/Status: FAILED/; s/Blocking: YES/Blocking: NO/' "$CLEAN" > "$NB"
ok "$NB" && pass "Blocking=NO + FAILED → does not block --strict" || fail "non-blocking failure wrongly blocked"

echo ""
echo "A DEFERRED item without justification fails"
DJ="$WORK/defer.md"
cat > "$DJ" <<'EOF'
# UAT
Baseline commit: abc1234
- UAT-001
  Requirement: AC-001
  Status: DEFERRED
  Blocking: NO
EOF
blk "$DJ" && pass "DEFERRED without Reason/Risk/Resolution → --strict fail" || fail "unjustified deferral not caught"

echo ""
echo "Malformed id, duplicate id, and invalid Status all fail"
MAL="$WORK/mal.md"; printf '# UAT\nBaseline commit: x\n- UAT-abc\n  Status: PASSED\n  Blocking: NO\n' > "$MAL"
blk "$MAL" && pass "malformed UAT id (UAT-abc) → --strict fail" || fail "malformed id not caught"
DUP="$WORK/dup.md"; { cat "$CLEAN"; printf -- '- UAT-001\n  Status: PASSED\n  Blocking: NO\n'; } > "$DUP"
blk "$DUP" && pass "duplicate UAT id → --strict fail" || fail "duplicate id not caught"
INV="$WORK/inv.md"; printf '# UAT\nBaseline commit: x\n- UAT-001\n  Status: MAYBE\n  Blocking: NO\n' > "$INV"
blk "$INV" && pass "invalid Status (MAYBE) → --strict fail" || fail "invalid Status not caught"

echo ""
echo "The check never mutates the ledger"
BEFORE=$(cat "$CLEAN"); bash "$CHK" --strict "$CLEAN" >/dev/null 2>&1; AFTER=$(cat "$CLEAN")
[ "$BEFORE" = "$AFTER" ] && pass "ledger byte-identical after check" || fail "check mutated the ledger"

echo ""
echo "Regression (v2.15.0) — absent data must not read as permission"
# v2.14.0 validated Blocking only when present, so an item that OMITTED it was treated as
# "not blocking" and a FAILED acceptance item passed --strict. Forgetting the field was safer
# than mistyping it — the omission most likely in practice was the one that failed open.
NOBLK="$WORK/noblock.md"
printf '# UAT\nBaseline commit: abc1234\n\n- UAT-001\n  Requirement: AC-001\n  Status: FAILED\n  Expected: charged once\n  Actual: double-charged\n' > "$NOBLK"
blk "$NOBLK" && pass "FAILED item with NO Blocking field → --strict blocks (absent ≠ NO)" \
             || fail "an omitted Blocking field failed open on a FAILED item"
NOBLK_OUT=$(bash "$CHK" --strict "$NOBLK" 2>&1)
printf '%s\n' "$NOBLK_OUT" | grep -q "no Blocking" && pass "the missing required field is named" \
                                                   || fail "missing Blocking not named"
# and an omitted Blocking is a structural error even when nothing failed — the field is required
NOBLK_PASS="$WORK/noblock-passed.md"
printf '# UAT\nBaseline commit: abc1234\n\n- UAT-001\n  Requirement: AC-001\n  Status: PASSED\n' > "$NOBLK_PASS"
blk "$NOBLK_PASS" && pass "PASSED item with no Blocking → still a structural error" \
                  || fail "a required field may not be optional in practice"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All check-uat.sh tests passed."; exit 0
else echo "$FAILS check-uat.sh test(s) FAILED."; exit 1; fi
