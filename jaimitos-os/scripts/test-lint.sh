#!/usr/bin/env bash
# test-lint.sh — covers the Phase 8 polish helpers: scripts/next-adr.sh (deterministic ADR
# numbering + collision guard) and scripts/lint-roadmap.sh (Done-when lint).
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXT_ADR="$SCAFFOLD/scripts/next-adr.sh"
LINT="$SCAFFOLD/scripts/lint-roadmap.sh"
for f in "$NEXT_ADR" "$LINT"; do [ -f "$f" ] || { echo "test: missing $f" >&2; exit 1; }; done

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-lint)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO/scripts" "$REPO/docs" "$REPO/.claude/lib"
  cp "$NEXT_ADR" "$REPO/scripts/"; cp "$LINT" "$REPO/scripts/"
  # Copy the sibling libs so lint-roadmap can source the requirement-id validator (which sources
  # _roadmap.sh for the shared task regex). Absent → id validation is simply inert.
  for l in _requirements.sh _roadmap.sh; do
    [ -f "$SCAFFOLD/.claude/lib/$l" ] && cp "$SCAFFOLD/.claude/lib/$l" "$REPO/.claude/lib/"
  done
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A && git commit -q -m init )
}

echo "next-adr tests"; echo ""
mkrepo a1
[ "$( cd "$REPO" && bash scripts/next-adr.sh )" = "001" ] && pass "next-adr: empty dir → 001" || fail "next-adr empty wrong"
mkrepo a2; mkdir -p "$REPO/docs/decisions"; : > "$REPO/docs/decisions/ADR-001-x.md"; : > "$REPO/docs/decisions/ADR-002-y.md"
[ "$( cd "$REPO" && bash scripts/next-adr.sh )" = "003" ] && pass "next-adr: highest+1 (003)" || fail "next-adr increment wrong"
mkrepo a3; mkdir -p "$REPO/docs/decisions"; : > "$REPO/docs/decisions/ADR-007-z.md"
[ "$( cd "$REPO" && bash scripts/next-adr.sh )" = "008" ] && pass "next-adr: respects zero-padding gaps (008)" || fail "next-adr padding wrong"

echo ""
echo "lint-roadmap tests"; echo ""
mkrepo l1
printf '## Phase 1 — A\n- [ ] t\nDone when: the suite is green\nMode: loopable\n\n## Phase 2 — B\n- [ ] u\nDone when: builds clean\nMode: supervised\n' > "$REPO/docs/ROADMAP.md"
( cd "$REPO" && bash scripts/lint-roadmap.sh --strict ) >/dev/null 2>&1 && pass "lint-roadmap: valid schema (Done when + task + Mode) → exit 0" || fail "lint-roadmap false-positived on a good roadmap"

# strict schema checks (N4): duplicate heading, invalid Mode, no task each fail --strict
printf '## Phase 1 — A\n- [ ] t\nDone when: x\nMode: loopable\n\n## Phase 1 — A\n- [ ] u\nDone when: y\nMode: loopable\n' > "$REPO/docs/ROADMAP.md"
( cd "$REPO" && bash scripts/lint-roadmap.sh --strict ) >/dev/null 2>&1 && fail "lint-roadmap missed a duplicate heading" || pass "lint-roadmap: duplicate phase heading → --strict exit 1"
printf '## Phase 1 — A\n- [ ] t\nDone when: x\nMode: banana\n' > "$REPO/docs/ROADMAP.md"
( cd "$REPO" && bash scripts/lint-roadmap.sh --strict ) >/dev/null 2>&1 && fail "lint-roadmap missed an invalid Mode" || pass "lint-roadmap: invalid Mode value → --strict exit 1"
printf '## Phase 1 — A\nDone when: x\nMode: loopable\n' > "$REPO/docs/ROADMAP.md"
( cd "$REPO" && bash scripts/lint-roadmap.sh --strict ) >/dev/null 2>&1 && fail "lint-roadmap missed a task-less phase" || pass "lint-roadmap: phase with no task → --strict exit 1"
mkrepo l2
printf '## Phase 1 — A\n- [ ] t\nDone when: ok\n\n## Phase 2 — B\n- [ ] u\n' > "$REPO/docs/ROADMAP.md"   # phase 2 missing Done when
( cd "$REPO" && bash scripts/lint-roadmap.sh --strict ) >/dev/null 2>&1 && fail "lint-roadmap missed a phase with no Done when" || pass "lint-roadmap: missing Done when → --strict exit 1"
out=$( cd "$REPO" && bash scripts/lint-roadmap.sh ); rc=$?
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'Phase 2'; } && pass "lint-roadmap: advisory mode warns but exits 0" || fail "lint-roadmap advisory mode wrong (rc=$rc)"

echo ""
echo "requirement-id validation (lint-roadmap → _requirements.sh)"; echo ""
# Fixtures write docs/SPEC.md + docs/ROADMAP.md into a repo whose .claude/lib carries the helper.
mkrepo r1
wr() { printf '%s' "$1" > "$REPO/docs/SPEC.md"; printf '%s' "$2" > "$REPO/docs/ROADMAP.md"; }
strict() { ( cd "$REPO" && bash scripts/lint-roadmap.sh --strict ) >/dev/null 2>&1; }
advise() { ( cd "$REPO" && bash scripts/lint-roadmap.sh ); }

SPEC_OK='## Requirements (optional — REQ/AC)
### REQ-001 — export
Status: Approved
- AC-001: all supported data.
- AC-002: owner-only download.
'
ROAD_OK='## Phase 1 — Export
Sources:
- docs/SPEC.md
Requirements:
- REQ-001
- AC-001
- AC-002

- [ ] implement
Done when: green.
Mode: supervised
'
wr "$SPEC_OK" "$ROAD_OK"
strict && pass "req-id: valid REQ/AC spec+roadmap → --strict exit 0" || fail "req-id false-positived on a valid spec"

# unknown roadmap reference
wr "$SPEC_OK" '## Phase 1 — Export
Sources:
- docs/SPEC.md
Requirements:
- REQ-001
- AC-999

- [ ] implement
Done when: green.
Mode: supervised
'
strict && fail "req-id missed an unknown reference" || pass "req-id: roadmap references unknown id → --strict exit 1"
out=$(advise); rc=$?
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'AC-999'; } && pass "req-id: unknown ref warns in advisory mode but exits 0" || fail "req-id advisory mode wrong (rc=$rc)"

# duplicate id inside one phase
wr "$SPEC_OK" '## Phase 1 — Export
Sources:
- docs/SPEC.md
Requirements:
- REQ-001
- REQ-001

- [ ] implement
Done when: green.
Mode: supervised
'
strict && fail "req-id missed a duplicate id in one phase" || pass "req-id: duplicate id in one phase → --strict exit 1"

# duplicate AC anywhere in the spec (global uniqueness)
wr '## Requirements
### REQ-001 — a
Status: Approved
- AC-001: x.
### REQ-002 — b
Status: Approved
- AC-001: reused id.
' "$ROAD_OK"
strict && fail "req-id missed a globally-duplicated AC id" || pass "req-id: AC id duplicated anywhere in the spec → --strict exit 1"

# malformed id
wr "$SPEC_OK" '## Phase 1 — Export
Sources:
- docs/SPEC.md
Requirements:
- req-001

- [ ] implement
Done when: green.
Mode: supervised
'
strict && fail "req-id missed a malformed id" || pass "req-id: malformed id (req-001) → --strict exit 1"

# Status: Approved carrying a blocking [NEEDS CLARIFICATION] → strict failure
wr '## Requirements
### REQ-001 — a
Status: Approved
Must do X [NEEDS CLARIFICATION: which X?].
- AC-001: x.
' '## Phase 1 — X
Sources:
- docs/SPEC.md
Requirements:
- REQ-001

- [ ] do
Done when: green.
Mode: supervised
'
strict && fail "req-id let an Approved requirement keep a blocking [NEEDS CLARIFICATION]" || pass "req-id: Approved + [NEEDS CLARIFICATION] → --strict exit 1"

# a Proposed requirement MAY keep the marker
wr '## Requirements
### REQ-001 — a
Status: Proposed
Must do X [NEEDS CLARIFICATION: which X?].
- AC-001: x.
' '## Phase 1 — X
Sources:
- docs/SPEC.md
Requirements:
- REQ-001

- [ ] do
Done when: green.
Mode: supervised
'
strict && pass "req-id: Proposed requirement may retain [NEEDS CLARIFICATION] → exit 0" || fail "req-id wrongly failed a Proposed requirement carrying the marker"

# external PREFIX-### is accepted only when the source defines it
wr '## Requirements
### FR-001 — external req
- AC-001: x.
' '## Phase 1 — X
Sources:
- docs/SPEC.md
Requirements:
- FR-001
- AC-001

- [ ] do
Done when: green.
Mode: supervised
'
strict && pass "req-id: external FR-001 defined in the spec → exit 0" || fail "req-id rejected an external id the spec defines"
wr '## Requirements
### REQ-001 — a
- AC-001: x.
' '## Phase 1 — X
Sources:
- docs/SPEC.md
Requirements:
- FR-999

- [ ] do
Done when: green.
Mode: supervised
'
strict && fail "req-id accepted an undefined external id" || pass "req-id: external FR-999 not defined by the source → --strict exit 1"

# a phase sourced from an EXTERNAL file is not cross-referenced against docs/SPEC.md
wr "$SPEC_OK" '## Phase 1 — X
Sources:
- specs/external/prd.md
Requirements:
- FR-042
- JIRA-1234

- [ ] do
Done when: green.
Mode: supervised
'
strict && pass "req-id: external-sourced phase not cross-referenced against docs/SPEC.md → exit 0" || fail "req-id wrongly cross-referenced an external-sourced phase"

# legacy: a roadmap with no Requirements: block anywhere is fully inert
mkrepo r2
printf '## Phase 1 — A\n- [ ] t\nDone when: green\nMode: loopable\n' > "$REPO/docs/ROADMAP.md"
( cd "$REPO" && bash scripts/lint-roadmap.sh --strict ) >/dev/null 2>&1 && pass "req-id: no Requirements: block anywhere → inert, --strict exit 0" || fail "req-id was not inert on a legacy roadmap"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All lint/helper tests passed."; exit 0
else echo "$FAILS lint test(s) FAILED."; exit 1; fi
