#!/usr/bin/env bash
# test-eval-isolation.sh — the shared evaluator-isolation lib (.claude/lib/_eval-isolation.sh).
# Covers BOTH strategies: eval_restore (DESTRUCTIVE, headless) and eval_changed_files
# (NON-DESTRUCTIVE detection, interactive /phase), plus eval_snapshot's fail-closed contract.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$SCAFFOLD/.claude/lib/_eval-isolation.sh"
[ -f "$LIB" ] || { echo "test: missing $LIB" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-evaliso)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# mkrepo: a throwaway repo with one committed tracked file; cd's the shell into it and sources the lib.
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && mkdir -p src && printf 'ORIGINAL\n' > src/widget.py && git add -A && git commit -qm init )
  cd "$REPO" || exit 1
  # shellcheck disable=SC1090
  . "$LIB"
}

echo "eval-isolation lib tests"; echo ""

# 1 — eval_restore (headless): a grader that EDITS a tracked file is reverted to the pre-grade state.
mkrepo t1
eval_snapshot || fail "t1: eval_snapshot failed on a clean repo"
printf 'TAMPERED_BY_EVALUATOR\n' > src/widget.py           # simulate the grader editing the tree
if eval_restore; then
  [ "$(cat src/widget.py)" = "ORIGINAL" ] \
    && pass "eval_restore reverts a grader's tracked edit to the pre-grade state" \
    || fail "eval_restore did not revert the tracked edit"
else
  fail "eval_restore returned non-zero on a clean-start repo"
fi

# 2 — eval_restore removes an untracked file the grader created, but keeps a pre-existing one.
mkrepo t2
printf 'user note\n' > preexisting.txt                     # user's untracked file, present BEFORE grading
eval_snapshot
printf 'x\n' > grader_created.py                           # grader creates a new untracked file
eval_restore >/dev/null 2>&1
{ [ ! -e grader_created.py ] && [ -e preexisting.txt ]; } \
  && pass "eval_restore deletes grader-created untracked files, keeps pre-existing ones" \
  || fail "eval_restore mishandled untracked files"

# 3 — eval_restore detects (and reverts) a COMMIT the grader sneaks in, and STOPS.
mkrepo t3
eval_snapshot
BEFORE=$(git rev-parse HEAD)
printf 'sneak\n' > src/widget.py && git add -A >/dev/null 2>&1 && git commit -qm "evaluator sneak commit"
out=$(eval_restore 2>&1); rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "evaluator COMMITTED during grading" \
  && [ "$(git rev-parse HEAD)" = "$BEFORE" ]; } \
  && pass "eval_restore detects a grader commit, reverts HEAD, and returns non-zero (STOP)" \
  || fail "eval_restore did not handle a grader commit (rc=$rc)"

# 4 — eval_snapshot is fail-closed OUTSIDE a git repo (caller must then skip grading).
NOGIT="$WORK/nogit"; mkdir -p "$NOGIT"; cd "$NOGIT" || exit 1
# shellcheck disable=SC1090
. "$LIB"
eval_snapshot >/dev/null 2>&1 && fail "eval_snapshot succeeded outside a git repo (should fail-closed)" \
  || pass "eval_snapshot fail-closed outside a git repo"

# 5 — eval_changed_files (interactive): names the EXACT tracked edit + untracked creation, returns 1,
# and does NOT mutate the tree (the grader's changes are still present for the human to clean up).
mkrepo t5
eval_snapshot
printf 'TAMPERED\n' > src/widget.py                        # grader modifies a tracked file
printf 'y\n' > grader_new.py                               # grader creates an untracked file
out=$(eval_changed_files); rc=$?
{ [ "$rc" -eq 1 ] \
  && printf '%s\n' "$out" | grep -q '\[modified\] src/widget.py' \
  && printf '%s\n' "$out" | grep -q '\[created\] grader_new.py' \
  && [ "$(cat src/widget.py)" = "TAMPERED" ] && [ -e grader_new.py ]; } \
  && pass "eval_changed_files names the exact files, returns 1, and leaves the tree UNTOUCHED (non-destructive)" \
  || fail "eval_changed_files detection/non-destructiveness broken (rc=$rc): $out"

# 6 — eval_changed_files is silent + returns 0 when the grader touched nothing.
mkrepo t6
eval_snapshot
out=$(eval_changed_files); rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$out" ]; } \
  && pass "eval_changed_files: clean grade → empty output, return 0" \
  || fail "eval_changed_files false-positived on a clean grade (rc=$rc): $out"

# 7 — eval_changed_files works with a DIRTY start (user WIP): pre-existing WIP is NOT reported,
# only what the grader changed on top of it is.
mkrepo t7
printf 'USER_WIP\n' > src/widget.py                        # uncommitted user WIP BEFORE grading
printf 'wip note\n' > user_wip.txt                         # untracked user WIP
eval_snapshot
printf 'y\n' > grader_new.py                               # grader adds a NEW untracked file
out=$(eval_changed_files); rc=$?
{ [ "$rc" -eq 1 ] \
  && printf '%s\n' "$out" | grep -q '\[created\] grader_new.py' \
  && ! printf '%s\n' "$out" | grep -q 'user_wip.txt' \
  && ! printf '%s\n' "$out" | grep -q 'widget.py'; } \
  && pass "eval_changed_files with a dirty start reports only the grader's change, not the user's WIP" \
  || fail "eval_changed_files leaked user WIP into the report (rc=$rc): $out"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All eval-isolation tests passed."; exit 0
else echo "$FAILS eval-isolation test(s) FAILED."; exit 1; fi
