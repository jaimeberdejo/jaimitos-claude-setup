#!/usr/bin/env bash
# test-enforcement.sh — fixtures for scripts/lint-enforcement.sh, the enforcement-ledger structure check.
# Proves: a valid ledger passes; a missing ledger is inert; deterministic claims must name a real strength;
# an ADVISORY claim is NOT rejected but cannot masquerade as DETERMINISTIC; a DEFERRED row needs a real
# trigger; duplicate/malformed ids and empty required fields fail; and it never mutates anything.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$SCAFFOLD/scripts/lint-enforcement.sh"
[ -f "$LINT" ] || { echo "test: cannot find lint-enforcement.sh at $LINT" >&2; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-enf)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# strict_ok <file> ; strict_fail <file>
strict_ok()   { bash "$LINT" --strict "$1" >/dev/null 2>&1; }
strict_fail() { ! bash "$LINT" --strict "$1" >/dev/null 2>&1; }

echo "lint-enforcement.sh tests"; echo ""

VALID="$WORK/valid.md"
cat > "$VALID" <<'EOF'
# Enforcement Ledger
Baseline commit: abc1234
Last reviewed: 2026-07-16

| ID | Claim | Source | Enforcement | Strength | Status | Trigger |
|---|---|---|---|---|---|---|
| ENF-001 | UI must not access persistence directly | ADR-004 | dependency test | DETERMINISTIC | ACTIVE | every CI run |
| ENF-002 | Auth changes require security review | SECURITY.md | PLAN_CHECK + CODEOWNERS | MODEL-DEPENDENT + HUMAN-DEPENDENT | ACTIVE | auth path modified |
| ENF-003 | New modules require ownership mapping | OWNERSHIP.md | plan checker | STRUCTURAL + MODEL | ACTIVE | new component path |
| ENF-004 | Legacy adapter removed after migration | SPEC REQ-018 | deferred trigger | DEFERRED | DEFERRED | PHASE-08 completes |
| ENF-005 | Prefer small commits | CONTRIBUTING.md | advisory documentation | ADVISORY | ACTIVE | code review |
EOF

echo "A valid ledger passes --strict"
strict_ok "$VALID" && pass "valid ledger passes" || { fail "valid ledger rejected"; bash "$LINT" --strict "$VALID"; }

echo ""
echo "A missing ledger is inert (exit 0, nothing to lint)"
bash "$LINT" --strict "$WORK/does-not-exist.md" >/dev/null 2>&1 && pass "absent ledger exits 0" || fail "absent ledger did not exit 0"

echo ""
echo "Duplicate ledger id fails"
D="$WORK/dup.md"; { cat "$VALID"; echo '| ENF-001 | duplicate id | X | Y | ADVISORY | ACTIVE | z |'; } > "$D"
strict_fail "$D" && pass "duplicate ENF id rejected" || fail "duplicate id not caught"

echo ""
echo "Malformed id fails"
M="$WORK/malformed.md"; sed 's/ENF-001/ENF-1/' "$VALID" > "$M"
strict_fail "$M" && pass "malformed id (ENF-1) rejected" || fail "malformed id not caught"

echo ""
echo "Empty Source fails (a claim with no source is unverifiable)"
S="$WORK/nosrc.md"; sed 's/| ADR-004 |/|  |/' "$VALID" > "$S"
strict_fail "$S" && pass "empty Source rejected" || fail "empty Source not caught"

echo ""
echo "Unknown Strength token fails"
ST="$WORK/badstr.md"; sed 's/DETERMINISTIC | ACTIVE | every CI run/MAGIC | ACTIVE | every CI run/' "$VALID" > "$ST"
strict_fail "$ST" && pass "unknown Strength token rejected" || fail "unknown Strength not caught"

echo ""
echo "A DEFERRED row with no concrete trigger fails"
DF="$WORK/deferred.md"; sed 's/| DEFERRED | PHASE-08 completes |/| DEFERRED | - |/' "$VALID" > "$DF"
strict_fail "$DF" && pass "DEFERRED without trigger rejected" || fail "DEFERRED without trigger not caught"

echo ""
echo "Advisory prose cannot be labelled DETERMINISTIC"
AV="$WORK/advindet.md"
sed 's/| dependency test | DETERMINISTIC |/| advisory documentation | DETERMINISTIC |/' "$VALID" > "$AV"
strict_fail "$AV" && pass "DETERMINISTIC-over-advisory rejected" || fail "advisory-as-deterministic not caught"

echo ""
echo "An honest ADVISORY row is accepted (advisory is a valid, distinct strength)"
ADV="$WORK/adv.md"
cat > "$ADV" <<'EOF'
# Enforcement Ledger
Baseline commit: abc1234
Last reviewed: 2026-07-16

| ID | Claim | Source | Enforcement | Strength | Status | Trigger |
|---|---|---|---|---|---|---|
| ENF-001 | Prefer small commits | CONTRIBUTING.md | advisory documentation | ADVISORY | ACTIVE | code review |
EOF
strict_ok "$ADV" && pass "honest ADVISORY row accepted" || fail "ADVISORY row wrongly rejected"

echo ""
echo "A file with no ledger table fails"
NT="$WORK/notable.md"; printf '# Enforcement Ledger\n\nJust prose, no table.\n' > "$NT"
strict_fail "$NT" && pass "no-table ledger rejected" || fail "missing table not caught"

echo ""
echo "Missing Baseline commit is a warning, not a hard failure"
NB="$WORK/nobaseline.md"; grep -v 'Baseline commit' "$VALID" > "$NB"
strict_ok "$NB" && pass "missing baseline warns but still passes structure" || fail "missing baseline wrongly failed"
NBOUT="$(bash "$LINT" "$NB" 2>&1)"   # capture then grep — never `cmd | grep -q` (SIGPIPE+pipefail flake)
printf '%s\n' "$NBOUT" | grep -q 'Baseline commit' && pass "the baseline warning is printed" || fail "no baseline warning printed"

echo ""
echo "The linter never mutates the ledger it reads"
BEFORE="$(cat "$VALID")"; bash "$LINT" --strict "$VALID" >/dev/null 2>&1; AFTER="$(cat "$VALID")"
[ "$BEFORE" = "$AFTER" ] && pass "ledger byte-identical after lint" || fail "linter mutated the ledger"

echo ""
echo "Regression (v2.15.0) — a row must never escape validation"
# v2.14.0 detected separator rows with an UNANCHORED regex, so a DATA row whose cell merely started
# with "--" (a CLI flag in a Claim, or "-- none --" in an Enforcement cell) matched and was skipped.
# The row was then never counted, so an all-skipped ledger reported "no rows" + structure OK + exit 0
# under --strict. The rows most likely to be swallowed were exactly the ones the ledger exists to catch.
DASH="$WORK/dashdash.md"
cat > "$DASH" <<'EOF'
# Enforcement Ledger
Baseline commit: abc1234
Last reviewed: 2026-07-16

| ID | Claim | Source | Enforcement | Strength | Status | Trigger |
|---|---|---|---|---|---|---|
| ENF-001 | --dangerously-skip-permissions needs a sandbox | SECURITY.md | | BOGUS_TOKEN | DEFERRED | |
EOF
strict_fail "$DASH" && pass "a row whose cell starts with -- is still validated (not read as a separator)" \
                    || fail "a -- prefixed cell let the whole row skip validation"

# v2.14.0's data-row branch fell through to the table-end rule, whose /^[^|]/ matched an INDENTED row
# (it starts with a space) and closed the table after row 1 — every later row fell out unvalidated.
INDENT="$WORK/indent.md"
printf '# Enforcement Ledger\nBaseline commit: abc1234\nLast reviewed: 2026-07-16\n\n  | ID | Claim | Source | Enforcement | Strength | Status | Trigger |\n  |---|---|---|---|---|---|---|\n  | ENF-001 | a real claim | ADR-001 | a real test | DETERMINISTIC | ACTIVE | every CI run |\n  | ENF-001 | DUPLICATE id | | | TOTAL_GARBAGE | DEFERRED | |\n' > "$INDENT"
strict_fail "$INDENT" && pass "an indented table validates every row, not just the first" \
                      || fail "only the first row of an indented table was validated"

# The anchored separator must still accept standard GFM alignment rows, or a valid ledger fails with
# nonsense ":---" id errors (the inverse failure of the same loose regex).
ALIGN="$WORK/align.md"
printf '# Enforcement Ledger\nBaseline commit: abc1234\nLast reviewed: 2026-07-16\n\n| ID | Claim | Source | Enforcement | Strength | Status | Trigger |\n|:---|:---|:---|:---|:---:|:---|:---|\n| ENF-001 | a claim | ADR-001 | a test | DETERMINISTIC | ACTIVE | every CI run |\n' > "$ALIGN"
strict_ok "$ALIGN" && pass "a GFM alignment row (|:---|) is a separator, not a malformed data row" \
                   || fail "alignment row misparsed as data"

echo ""
echo "Regression (v2.15.0) — a mistyped flag must not become the file path"
bash "$LINT" --strictt "$VALID" >/dev/null 2>&1
[ "$?" = "2" ] && pass "unknown flag → exit 2 (not silently read as the ledger path)" \
               || fail "a mistyped flag was swallowed as the file path"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All lint-enforcement.sh tests passed."; exit 0
else echo "$FAILS lint-enforcement.sh test(s) FAILED."; exit 1; fi
