#!/usr/bin/env bash
# test-requirements.sh — fixtures for the v2.14.0 traceability EXTENSION on top of R3's requirements
# validator: orphan/coverage detection (requirements_orphans) and the trace-requirements.sh report.
# Proves: an approved requirement no phase plans is surfaced (orphan); a requirement covered by its own id
# OR a child AC is NOT an orphan; a Deferred/Rejected requirement is never an orphan; orphans are advisory
# (never fail --strict) while a structural problem does fail --strict; and the report is inert with no ids.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRACE="$SCAFFOLD/scripts/trace-requirements.sh"
LIB="$SCAFFOLD/.claude/lib/_requirements.sh"
[ -f "$TRACE" ] && [ -f "$LIB" ] || { echo "test: missing trace-requirements.sh or _requirements.sh" >&2; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
has()   { printf '%s\n' "$2" | grep -q "$1"; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-req)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
mkdir -p "$WORK/docs"; cd "$WORK" || exit 1

write_spec() {
  cat > docs/SPEC.md <<'EOF'
# Spec
## Requirements
### REQ-001 — export
Status: Approved
- AC-001: contains data
### REQ-002 — import
Status: Approved
- AC-002: imports data
### OBJ-001 — keep the parser healthy
Status: Approved
### REQ-003 — a future thing
Status: Deferred
EOF
}

echo "trace-requirements.sh / requirements_orphans tests"; echo ""

echo "An approved requirement no phase plans is surfaced as an orphan"
write_spec
cat > docs/ROADMAP.md <<'EOF'
## Phase 1 — export
- [ ] build it
Done when: it works
Mode: loopable
Requirements:
- REQ-001
## Phase 2 — import
- [ ] build it
Done when: it works
Mode: loopable
Requirements:
- AC-002
EOF
OUT=$(bash "$TRACE" 2>&1)
has "OBJ-001" "$OUT"                              && pass "unplanned OBJ-001 flagged as orphan"                 || fail "orphan OBJ-001 not surfaced: $OUT"
has "REQ-001 is defined and active" "$OUT"       && fail "referenced REQ-001 wrongly orphaned"                 || pass "a directly-referenced requirement is not an orphan"
has "REQ-002 is defined and active" "$OUT"       && fail "AC-covered REQ-002 wrongly orphaned"                 || pass "a requirement covered via its child AC is not an orphan"
has "REQ-003" "$OUT"                             && fail "Deferred REQ-003 wrongly orphaned"                   || pass "a Deferred requirement is never an orphan (intentional)"

echo ""
echo "Orphans are advisory — they never fail --strict"
bash "$TRACE" --strict >/dev/null 2>&1 && pass "an orphan does not fail --strict" || fail "orphan wrongly failed --strict"

echo ""
echo "Full coverage → no orphans"
cat >> docs/ROADMAP.md <<'EOF'
## Phase 3 — maintenance
- [ ] build it
Done when: it works
Mode: loopable
Requirements:
- OBJ-001
EOF
OUT=$(bash "$TRACE" 2>&1)
has "every active requirement is planned" "$OUT" && pass "full coverage reports no orphans" || fail "full coverage not clean: $OUT"

echo ""
echo "A structural problem (unresolved reference) DOES fail --strict"
write_spec
cat > docs/ROADMAP.md <<'EOF'
## Phase 1 — bogus
- [ ] build it
Done when: it works
Mode: loopable
Requirements:
- REQ-999
EOF
bash "$TRACE" --strict >/dev/null 2>&1 && fail "unresolved reference did not fail --strict" || pass "unresolved reference fails --strict"
OUT=$(bash "$TRACE" 2>&1)
has "REQ-999" "$OUT" && pass "the unresolved reference is named in the report" || fail "unresolved reference not named"

echo ""
echo "requirements_orphans returns rc 0 even when it finds orphans (never a build blocker)"
write_spec
printf '## Phase 1 — x\n- [ ] t\nDone when: y\nMode: loopable\n' > docs/ROADMAP.md   # references nothing
( . "$LIB"; requirements_orphans docs/ROADMAP.md docs/SPEC.md >/dev/null ) && pass "requirements_orphans rc 0 with orphans present" || fail "requirements_orphans returned nonzero"

echo ""
echo "The report is inert when the project defines no ids"
printf '# Spec\n## Success criterion\nit works\n' > docs/SPEC.md
printf '## Phase 1 — x\n- [ ] t\nDone when: y\nMode: loopable\n' > docs/ROADMAP.md
OUT=$(bash "$TRACE" 2>&1)
has "no structural problems" "$OUT"              && pass "inert: structure clean with no ids"   || fail "inert structure wrong: $OUT"
has "every active requirement is planned" "$OUT" && pass "inert: coverage clean with no ids"     || fail "inert coverage wrong: $OUT"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All trace-requirements.sh tests passed."; exit 0
else echo "$FAILS trace-requirements.sh test(s) FAILED."; exit 1; fi
