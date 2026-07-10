#!/usr/bin/env bash
# test-roadmap-lib.sh — unit tests for the shared fail-closed roadmap parser (.claude/lib/_roadmap.sh).
# One parser now feeds tick.sh, autopilot.sh's pre-build supervised gate, and close-milestone.sh, so
# its fail-closed behavior (duplicate heading, missing/duplicate/invalid Mode) is load-bearing.
set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/lib/_roadmap.sh"
[ -f "$LIB" ] || { echo "test: cannot find _roadmap.sh at $LIB" >&2; exit 1; }
# shellcheck disable=SC1090
. "$LIB"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t roadmaplib)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
RM="$WORK/ROADMAP.md"

echo "roadmap parser tests"; echo ""

echo "roadmap_first_open_heading:"
printf '## Phase 1 — A\n- [x] done\nMode: loopable\n\n## Phase 2 — B\n- [ ] todo\nMode: loopable\n' > "$RM"
h=$(roadmap_first_open_heading "$RM"); rc=$?
{ [ "$rc" = 0 ] && [ "$h" = "## Phase 2 — B" ]; } && pass "first phase with an open item (skips fully-ticked Phase 1)" || fail "wrong first-open heading (rc=$rc, h='$h')"

printf '## Phase 1 — A\n- [x] done\nMode: loopable\n' > "$RM"
roadmap_first_open_heading "$RM" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && pass "no open items → rc 1" || fail "expected rc 1 for a fully-ticked roadmap (rc=$rc)"

printf '## Phase 1 — Dup\n- [ ] todo\nMode: loopable\n\n## Phase 1 — Dup\n- [ ] other\nMode: loopable\n' > "$RM"
roadmap_first_open_heading "$RM" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && pass "duplicate heading (ambiguous) → rc 2 (fail-closed)" || fail "duplicate heading not fail-closed (rc=$rc)"

roadmap_first_open_heading "$WORK/nope.md" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && pass "missing file → rc 2" || fail "missing file not rc 2 (rc=$rc)"

echo ""
echo "roadmap_phase_mode:"
printf '## Phase 1 — A\n- [ ] todo\nDone when: x\nMode: supervised\n' > "$RM"
m=$(roadmap_phase_mode "$RM" "## Phase 1 — A"); rc=$?
{ [ "$rc" = 0 ] && [ "$m" = supervised ]; } && pass "single Mode: supervised → 'supervised'" || fail "supervised misparsed (rc=$rc, m='$m')"

printf '## Phase 1 — A\n- [ ] todo\nMode: loopable\n' > "$RM"
m=$(roadmap_phase_mode "$RM" "## Phase 1 — A"); rc=$?
{ [ "$rc" = 0 ] && [ "$m" = loopable ]; } && pass "single Mode: loopable → 'loopable'" || fail "loopable misparsed (rc=$rc, m='$m')"

printf '## Phase 1 — A\n- [ ] todo\nDone when: x\n' > "$RM"
m=$(roadmap_phase_mode "$RM" "## Phase 1 — A"); rc=$?
{ [ "$rc" = 0 ] && [ -z "$m" ]; } && pass "no Mode: line → rc 0 + empty (unclassified)" || fail "missing Mode not rc0/empty (rc=$rc, m='$m')"

printf '## Phase 1 — A\n- [ ] todo\nMode: loopable\nMode: supervised\n' > "$RM"
roadmap_phase_mode "$RM" "## Phase 1 — A" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && pass "two Mode: lines → rc 2 (ambiguous, fail-closed)" || fail "duplicate Mode not fail-closed (rc=$rc)"

printf '## Phase 1 — A\n- [ ] todo\nMode: banana\n' > "$RM"
roadmap_phase_mode "$RM" "## Phase 1 — A" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && pass "invalid Mode value → rc 2 (never waved through as 'not supervised')" || fail "invalid Mode not fail-closed (rc=$rc)"

# A Mode: line belonging to a DIFFERENT phase must not leak into this phase's result.
printf '## Phase 1 — A\n- [ ] todo\nMode: loopable\n\n## Phase 2 — B\n- [ ] todo\nMode: supervised\n' > "$RM"
m=$(roadmap_phase_mode "$RM" "## Phase 1 — A"); rc=$?
{ [ "$rc" = 0 ] && [ "$m" = loopable ]; } && pass "phase-2's Mode does not leak into phase-1" || fail "cross-phase Mode leak (rc=$rc, m='$m')"

echo ""
echo "roadmap_open_count:"
printf '## Phase 1 — A\n- [ ] one\n- [ ] two\n- [x] three\nMode: loopable\n' > "$RM"
c=$(roadmap_open_count "$RM" "## Phase 1 — A")
[ "$c" = 2 ] && pass "counts exactly the open items in the block (2)" || fail "open count wrong (got '$c')"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All roadmap parser tests passed."; exit 0
else echo "$FAILS roadmap parser test(s) FAILED."; exit 1; fi
