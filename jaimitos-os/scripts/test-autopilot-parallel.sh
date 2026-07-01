#!/usr/bin/env bash
# test-autopilot-parallel.sh — behavioral tests for the /autopilot-parallel INTEGRATION pattern
# (documented in .claude/commands/autopilot-parallel.md): N phases built independently, merged
# ONE AT A TIME into a shared checkout, each re-graded/re-evidenced fresh against the POST-merge
# HEAD, then ticked through the REAL scripts/tick.sh — never a second/weaker tick path.
#
# This does NOT spawn real `claude`/Agent-tool processes (there is no bash-scriptable equivalent
# of the Agent tool's isolation:"worktree" — that half of the feature is prose a live model
# executes, verified separately via a live dogfood run, not here). What IS fully scriptable, and
# is exactly what this file exercises with the REAL scripts.tick.sh, is the part that actually
# gates completion: does ticking one phase after a merge behave correctly, does a later phase's
# high-stakes/supervised/conflict outcome leave EARLIER already-ticked phases alone, is grade/
# evidence correctly bound to the POST-merge HEAD (not the worktree's own, now-discarded HEAD),
# and is the grade file single-use so one phase's PASS can't be replayed to tick another.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TICK="$SCAFFOLD/scripts/tick.sh"
EVID="$SCAFFOLD/scripts/test-evidence.sh"
RG="$SCAFFOLD/scripts/record-grade.sh"
HS_LIB="$SCAFFOLD/.claude/lib/_high-stakes.sh"
SS_LIB="$SCAFFOLD/.claude/lib/_secret-scan.sh"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

for f in "$TICK" "$EVID" "$RG" "$HS_LIB" "$SS_LIB"; do
  [ -f "$f" ] || { echo "test: missing $f" >&2; exit 1; }
done
command -v jq  >/dev/null 2>&1 || { echo "test: jq required";  exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-parallel)"
cleanup() { rm -rf "$WORK" 2>/dev/null; }
trap cleanup EXIT

set_grade()    { printf 'run_id=%s\nverdict=%s\nno_tests_ok=%s\n' "$2" "$3" "${4:-0}" > "$REPO/.claude/.phase-grade"; }
set_evidence() { printf '%s\n' "$2" > "$REPO/.claude/.tick-evidence.json"; }
good_grade()   { set_grade "$1" "$2" PASS 0; }
good_evidence(){ set_evidence "$1" "{\"passed\":true,\"run_id\":\"$2\"}"; }
runtick()      { ( cd "$REPO" && bash scripts/tick.sh "$1" ) >"$WORK/out" 2>&1; echo $?; }
md5of()        { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
ticked_line()  { grep -qF -- "$2" "$1/docs/ROADMAP.md" 2>/dev/null; }  # e.g. ticked_line "$REPO" "- [x] a-task"

# mkbatchrepo: one repo, one PARALLEL_BASE commit, five phases (A/B independent, C high-stakes
# path, D Mode:supervised, E already-done) each pre-built on its own branch off PARALLEL_BASE —
# simulating what N isolated worktree builds would have produced, so the integration step below
# is exercised against the REAL scripts exactly as /autopilot-parallel's Step C describes.
mkbatchrepo() {
  REPO="$WORK/batch"; rm -rf "$REPO"
  mkdir -p "$REPO/.claude/lib" "$REPO/scripts" "$REPO/docs"
  cp "$TICK" "$REPO/scripts/tick.sh"
  cp "$HS_LIB" "$REPO/.claude/lib/_high-stakes.sh"
  cp "$SS_LIB" "$REPO/.claude/lib/_secret-scan.sh"
  cat > "$REPO/docs/ROADMAP.md" <<'MD'
## Phase A — Independent A
- [ ] a-task
Done when: src/a.py exists
Mode: loopable

## Phase B — Independent B
- [ ] b-task
Done when: src/b.py exists
Mode: loopable

## Phase C — Touches auth
- [ ] c-task
Done when: auth/login.py exists
Mode: loopable

## Phase D — Tagged supervised
- [ ] d-task
Done when: src/d.py exists
Mode: supervised

## Phase E — Already done
- [x] e-task
Done when: n/a
Mode: loopable
MD
  printf 'next: batch\n' > "$REPO/docs/STATE.md"
  cat > "$REPO/.gitignore" <<'GI'
NEXT_FINDINGS.md
.claude/.tick-evidence.json
.claude/.phase-base
.claude/.phase-ready
.claude/.phase-grade
GI
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config gc.auto 0 && git add -A && git commit -q -m init )
  PARALLEL_BASE=$(git -C "$REPO" rev-parse HEAD)

  # One branch per phase, each simulating an isolated worktree's finished build.
  mkbranch() { # mkbranch <branch> <path> <content>
    ( cd "$REPO" && git branch "$1" "$PARALLEL_BASE" -q \
        && git checkout -q "$1" && mkdir -p "$(dirname "$2")" && printf '%s\n' "$3" > "$2" \
        && git add -A && git commit -q -m "build $1" && git checkout -q master -q 2>/dev/null \
        || git checkout -q main )
  }
  mkbranch phaseA src/a.py 'def a(): return 1'
  mkbranch phaseB src/b.py 'def b(): return 1'
  mkbranch phaseC auth/login.py 'def login(): return True'
  mkbranch phaseD src/d.py 'def d(): return 1'
  mkbranch phaseA-secret src/secret_cfg.py 'AWS="AKIAIOSFODNN7EXAMPLE"'
}

# integrate <heading> <branch>: the exact Step C sequence from autopilot-parallel.md — merge,
# reconstruct .phase-base/.phase-ready bound to PARALLEL_BASE and the NEW post-merge HEAD, then
# tick with a grade/evidence pair the caller controls (good/bad per test).
integrate() {
  local heading="$1" branch="$2"
  ( cd "$REPO" && git merge --no-ff "$branch" -q -m "merge $branch" ) >"$WORK/merge-out" 2>&1
  MERGE_RC=$?
  [ "$MERGE_RC" -eq 0 ] || return "$MERGE_RC"
  printf '%s\n' "$heading" > "$REPO/.claude/.phase-ready"
  printf '%s\n' "$PARALLEL_BASE" > "$REPO/.claude/.phase-base"
  POST_HEAD=$(git -C "$REPO" rev-parse HEAD)
  return 0
}

echo "autopilot-parallel integration tests (real tick.sh, simulated worktree merges)"; echo ""

# T1 — Phase A merges cleanly; fresh grade+evidence bound to the POST-merge HEAD → ticks.
mkbatchrepo
integrate "## Phase A — Independent A" phaseA
good_grade "$REPO" "$POST_HEAD"; good_evidence "$REPO" "$POST_HEAD"
rc=$(runtick "## Phase A — Independent A")
{ [ "$rc" = 0 ] && ticked_line "$REPO" "- [x] a-task"; } \
  && pass "T1: clean merge + fresh post-merge grade/evidence → Phase A ticks" \
  || fail "T1: Phase A did not tick (rc=$rc)"
git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -q -m "tick A" >/dev/null 2>&1

# T2 — Phase B merges on top of A's tick; fresh grade at the NEW HEAD → ticks; A's tick survives.
integrate "## Phase B — Independent B" phaseB
good_grade "$REPO" "$POST_HEAD"; good_evidence "$REPO" "$POST_HEAD"
rc=$(runtick "## Phase B — Independent B")
{ [ "$rc" = 0 ] && ticked_line "$REPO" "- [x] b-task" && ticked_line "$REPO" "- [x] a-task"; } \
  && pass "T2: second phase ticks without disturbing the first phase's prior tick" \
  || fail "T2: sequential multi-phase tick mishandled (rc=$rc)"
git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -q -m "tick B" >/dev/null 2>&1
SNAPSHOT_AFTER_AB=$(md5of "$REPO/docs/ROADMAP.md")

# T3 — stale evidence: reuse an evidence file bound to a PRE-merge (worktree) HEAD, not the
# actual post-merge HEAD, when integrating Phase C → refused, and A/B's ticks stay intact.
integrate "## Phase C — Touches auth" phaseC
good_grade "$REPO" "$POST_HEAD"; set_evidence "$REPO" "{\"passed\":true,\"run_id\":\"deadbeefstaleworktree\"}"
rc=$(runtick "## Phase C — Touches auth")
{ [ "$rc" = 1 ] && ! ticked_line "$REPO" "- [x] c-task" && [ "$(md5of "$REPO/docs/ROADMAP.md")" = "$SNAPSHOT_AFTER_AB" ]; } \
  && pass "T3: evidence bound to worktree's own (stale) HEAD is refused post-merge" \
  || fail "T3: stale worktree evidence incorrectly accepted (rc=$rc)"
# clean up the aborted attempt's merge commit so the repo is back to "A,B ticked, C not merged"
git -C "$REPO" reset -q --hard HEAD~1 >/dev/null 2>&1

# T4 — high-stakes PATH (Phase C, auth/) with a CORRECT fresh grade/evidence → tick.sh refuses
# with exit 3 (supervised), Phase C stays unticked, but A/B remain ticked.
integrate "## Phase C — Touches auth" phaseC
good_grade "$REPO" "$POST_HEAD"; good_evidence "$REPO" "$POST_HEAD"
rc=$(runtick "## Phase C — Touches auth")
{ [ "$rc" = 3 ] && ! ticked_line "$REPO" "- [x] c-task" && ticked_line "$REPO" "- [x] a-task" && ticked_line "$REPO" "- [x] b-task"; } \
  && pass "T4: high-stakes phase in a batch refuses (exit 3) without disturbing sibling ticks" \
  || fail "T4: high-stakes-in-batch mishandled (rc=$rc)"
git -C "$REPO" reset -q --hard HEAD~1 >/dev/null 2>&1   # undo C's merge; it's meant to stay local per the design, but this repo is reused below

# T5 — Mode: supervised (Phase D) with a correct grade/evidence → exit 3, D stays unticked,
# A/B remain ticked (a supervised TAG, not a high-stakes path, still blocks only its own phase).
integrate "## Phase D — Tagged supervised" phaseD
good_grade "$REPO" "$POST_HEAD"; good_evidence "$REPO" "$POST_HEAD"
rc=$(runtick "## Phase D — Tagged supervised")
{ [ "$rc" = 3 ] && ! ticked_line "$REPO" "- [x] d-task" && ticked_line "$REPO" "- [x] a-task" && ticked_line "$REPO" "- [x] b-task"; } \
  && pass "T5: Mode: supervised phase in a batch refuses without disturbing sibling ticks" \
  || fail "T5: Mode:supervised-in-batch mishandled (rc=$rc)"
git -C "$REPO" reset -q --hard HEAD~1 >/dev/null 2>&1

# T6 — already-done phase (E) named in a batch: nothing to merge, tick refuses "no open item".
printf '## Phase E — Already done\n' > "$REPO/.claude/.phase-ready"
printf '%s\n' "$PARALLEL_BASE" > "$REPO/.claude/.phase-base"
CUR_HEAD=$(git -C "$REPO" rev-parse HEAD)
good_grade "$REPO" "$CUR_HEAD"; good_evidence "$REPO" "$CUR_HEAD"
rc=$(runtick "## Phase E — Already done")
[ "$rc" = 1 ] && pass "T6: already-done phase named in a batch refuses cleanly" \
  || fail "T6: already-done-in-batch mishandled (rc=$rc)"

# T7 — grade file is SINGLE-USE: after T2 ticked Phase B, its grade was deleted by tick.sh
# itself. Confirm a THIRD phase cannot be ticked by reconstructing only .phase-ready (heading)
# without a FRESH grade — i.e. one phase's PASS cannot be silently replayed onto another.
integrate "## Phase C — Touches auth" phaseC   # merge only; do NOT write a fresh grade
# (integrate() already wrote .phase-ready/.phase-base; deliberately skip good_grade/good_evidence)
rm -f "$REPO/.claude/.phase-grade" "$REPO/.claude/.tick-evidence.json"
rc=$(runtick "## Phase C — Touches auth")
[ "$rc" = 1 ] && grep -q "missing evaluator grade" "$WORK/out" \
  && pass "T7: no grade replay across phases — a fresh grade is mandatory per phase" \
  || fail "T7: grade-reuse-across-phases NOT blocked (rc=$rc)"
git -C "$REPO" reset -q --hard HEAD~1 >/dev/null 2>&1

# T8 — secret planted in an INDEPENDENT phase's branch (not just the high-stakes one) is caught
# by the scan over the full PARALLEL_BASE..HEAD range, not just the last commit.
integrate "## Phase A — Independent A" phaseA-secret
good_grade "$REPO" "$POST_HEAD"; good_evidence "$REPO" "$POST_HEAD"
before=$(md5of "$REPO/docs/ROADMAP.md")
rc=$(runtick "## Phase A — Independent A")
{ [ "$rc" = 1 ] && [ "$(md5of "$REPO/docs/ROADMAP.md")" = "$before" ]; } \
  && pass "T8: secret in a merged phase branch is caught over the integrated diff, refuses" \
  || fail "T8: secret-in-integrated-diff mishandled (rc=$rc)"
git -C "$REPO" reset -q --hard HEAD~1 >/dev/null 2>&1

echo ""
echo "merge-conflict tests (git-level; the 'present options to the user' step is prose, verified"
echo "separately via a live dogfood run, not scriptable here)"; echo ""

# T9 — two phases whose branches touch the SAME file with DIFFERENT content conflict on merge;
# `git merge --abort` restores a clean tree, and neither phase's roadmap line is touched.
mkbatchrepo
( cd "$REPO" && git branch confA "$PARALLEL_BASE" -q && git checkout -q confA \
    && mkdir -p shared && printf 'line-a\n' > shared/file.txt && git add -A && git commit -q -m confA \
    && git checkout -q master -q 2>/dev/null || git checkout -q main )
( cd "$REPO" && git branch confB "$PARALLEL_BASE" -q && git checkout -q confB \
    && mkdir -p shared && printf 'line-b\n' > shared/file.txt && git add -A && git commit -q -m confB \
    && git checkout -q master -q 2>/dev/null || git checkout -q main )
( cd "$REPO" && git merge --no-ff confA -q -m mA ) >/dev/null 2>&1
before_conflict=$(md5of "$REPO/docs/ROADMAP.md")
( cd "$REPO" && git merge --no-ff confB -q -m mB ) >"$WORK/conflict-out" 2>&1
CONFLICT_RC=$?
( cd "$REPO" && git merge --abort ) >/dev/null 2>&1
{ [ "$CONFLICT_RC" -ne 0 ] && [ "$(md5of "$REPO/docs/ROADMAP.md")" = "$before_conflict" ]; } \
  && pass "T9: same-file phases conflict on merge; abort leaves ROADMAP untouched, no phantom tick" \
  || fail "T9: conflict handling at the git level mishandled (rc=$CONFLICT_RC)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All autopilot-parallel integration tests passed."; exit 0
else echo "$FAILS autopilot-parallel test(s) FAILED."; echo "--- last tick output ---"; tail -n 20 "$WORK/out" 2>/dev/null; exit 1; fi
