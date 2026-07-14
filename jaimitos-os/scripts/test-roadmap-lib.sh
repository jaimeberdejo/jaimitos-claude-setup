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
echo "ONE definition of an open task (anchoring):"
# A line that merely CONTAINS the substring "- [ ]" — prose, a quoted example, a "Done when:" that
# talks about checkboxes — is NOT a task. lint-roadmap.sh has always counted tasks ANCHORED; this
# library counted them UNANCHORED, and tick.sh's gsub rewrote them. Those three must agree, because
# a roadmap is allowed to talk about its own notation.
POISON='Done when: every `- [ ]` under this phase is checked'
printf '## Phase 1 — A\n- [x] real task\n%s\nMode: loopable\n' "$POISON" > "$RM"

c=$(roadmap_open_count "$RM" "## Phase 1 — A")
[ "$c" = 0 ] && pass "prose that merely mentions '- [ ]' is not an open task (count 0)" \
             || fail "prose counted as an open task (got '$c') — a phase like this could never tick"

h=$(roadmap_first_open_heading "$RM" 2>/dev/null); rc=$?
[ "$rc" = 1 ] && pass "prose alone does not make a phase 'open' (rc 1)" \
              || fail "prose made the phase look open (rc=$rc, h='$h')"

# The library and the linter must agree on the same file: both see exactly one task, none open.
LINT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lint-roadmap.sh"
bash "$LINT" --strict "$RM" >/dev/null 2>&1
[ $? = 0 ] && pass "lint-roadmap.sh and the parser agree on the same roadmap" \
           || fail "linter and parser disagree — the drift this library exists to prevent"

echo ""
echo "roadmap_open_total:"
printf '## Phase 1 — A\n- [ ] one\n%s\nMode: loopable\n\n## Phase 2 — B\n- [ ] two\n- [x] three\nMode: loopable\n' "$POISON" > "$RM"
t=$(roadmap_open_total "$RM")
[ "$t" = 2 ] && pass "whole-file open count ignores prose (2, not 3)" || fail "open total wrong (got '$t')"

echo ""
echo "roadmap_first_open_task:"
printf '## Phase 1 — A\n%s\n- [ ] the real next action\nMode: loopable\n' "$POISON" > "$RM"
t=$(roadmap_first_open_task "$RM"); rc=$?
{ [ "$rc" = 0 ] && [ "$t" = "the real next action" ]; } \
  && pass "next action is the first real task, not the prose line above it" \
  || fail "next action misread (rc=$rc, t='$t')"

echo ""
echo "roadmap_tick_phase:"
# The mutation itself. It must flip ONLY anchored task lines inside the block, and leave every other
# byte — including prose that mentions the notation — exactly as it was.
printf '## Phase 1 — A\n- [ ] one\n%s\nMode: loopable\n\n## Phase 2 — B\n- [ ] two\n' "$POISON" > "$RM"
roadmap_tick_phase "$RM" "## Phase 1 — A" > "$WORK/ticked.md"; rc=$?
{ [ "$rc" = 0 ] && grep -qxF -- '- [x] one' "$WORK/ticked.md"; } \
  && pass "ticks the real open task in the target phase" || fail "did not tick the real task (rc=$rc)"
grep -qxF -- "$POISON" "$WORK/ticked.md" \
  && pass "prose mentioning '- [ ]' survives the tick byte-for-byte" \
  || fail "the tick REWROTE prose text — roadmap corruption"
grep -qxF -- '- [ ] two' "$WORK/ticked.md" \
  && pass "a later phase's open task is untouched" || fail "tick leaked into another phase"

echo ""
echo "source-level drift guard:"
# The bug was never ONE regex — it was eight, across five files, drifting apart over years. The fix
# is centralization; THIS is what stops it happening again. Any core file that writes a task-line
# regex (the escaped `- \[ \]` form) must ANCHOR it. An unanchored one is the defect, by definition.
SCAFFOLD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANCHORED_OPEN='^[[:space:]]*- \[ \] '
ANCHORED_TASK='^[[:space:]]*- \[[ xX]\] '
DRIFT=""
for f in "$SCAFFOLD_DIR"/scripts/*.sh "$SCAFFOLD_DIR"/.claude/lib/*.sh "$SCAFFOLD_DIR"/.claude/hooks/*.sh; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in test-*) continue ;; esac   # tests quote the bad pattern on purpose
  n=0
  while IFS= read -r line; do
    n=$((n+1))
    # Delete every ANCHORED task regex from the line, then see what task regex is left over. (A
    # single line can carry both — tick.sh's old next_t matched unanchored and stripped anchored,
    # which a naive "does the line contain an anchor?" check waved straight through.)
    rest="${line//"$ANCHORED_OPEN"/}"
    rest="${rest//"$ANCHORED_TASK"/}"
    case "$rest" in
      *'- \[ \]'*|*'- \[[ xX]\]'*) DRIFT="$DRIFT $(basename "$f"):$n" ;;
    esac
  done < "$f"
done
[ -z "$DRIFT" ] && pass "every task-line regex in core is anchored (no unanchored '- [ ]' match)" \
                || fail "unanchored task-line regex — the drift is back at:$DRIFT"

# Anchoring alone is not enough: eight ANCHORED hand-written copies would drift apart just as well.
# Exactly three files may spell a task regex out, and each has a reason:
#   _roadmap.sh      — it IS the definition (ROADMAP_OPEN_RE / ROADMAP_TASK_RE)
#   lint-roadmap.sh  — dependency-free by design; it must lint with no library available
#   session-start.sh — a hook; sources no libs, and only greps to DISPLAY open items
# Everything else sources _roadmap.sh and must use the constants. A new copy anywhere fails here.
COPIES=""
for f in "$SCAFFOLD_DIR"/scripts/*.sh "$SCAFFOLD_DIR"/.claude/lib/*.sh "$SCAFFOLD_DIR"/.claude/hooks/*.sh; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  case "$b" in test-*|_roadmap.sh|lint-roadmap.sh|session-start.sh) continue ;; esac
  grep -q -- '- \\\[' "$f" 2>/dev/null && COPIES="$COPIES $b"
done
[ -z "$COPIES" ] && pass "no core file hand-writes a task regex — they all use the shared constants" \
                 || fail "hand-written task regex (use \$ROADMAP_OPEN_RE / the lib functions):$COPIES"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All roadmap parser tests passed."; exit 0
else echo "$FAILS roadmap parser test(s) FAILED."; exit 1; fi
