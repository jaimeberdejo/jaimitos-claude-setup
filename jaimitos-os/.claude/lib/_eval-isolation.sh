#!/usr/bin/env bash
# _eval-isolation.sh — SHARED evaluator-isolation library (sourced, not a hook).
#
# The evaluator has Bash (to re-run tests/typecheck/lint) but no Edit/Write tools. Bash is enough
# to mutate the tree anyway (`>`, `sed -i`, `tee`), and nothing watches the working tree DURING a
# grade — so a *complacent* grader (re-runs the suite, a test writes a fixture, the fixture makes
# the grade pass) can contaminate the tree it is grading. This lib is how both run modes stop that.
#
# Two run modes, two restore strategies, ONE snapshot:
#   • headless scripts/autopilot.sh — throwaway worktree, tracked tree guaranteed clean before
#     grading → eval_restore() DESTRUCTIVELY reverts any evaluator change. Safe because the
#     worktree is disposable.
#   • interactive /phase — the user's LIVE checkout, possibly with uncommitted WIP → we must NOT
#     `git reset --hard` it. eval_changed_files() DETECTS what the evaluator touched and names it;
#     the caller REFUSES to advance and asks the human (who is present) to clean up. Non-destructive.
#
# Provides (all operate on the CURRENT working tree / repo root):
#   eval_snapshot            capture pre-grade state into EVAL_PRE_* globals; 0 ok, non-0 fail-closed
#   eval_restore             DESTRUCTIVE headless cleanup (byte-compatible with the old inline one)
#   eval_changed_files       NON-DESTRUCTIVE detection for interactive; prints touched files, rc 1 if any
#
# Sourcing only defines the functions; running this file directly is a harmless no-op.

# eval_snapshot: record the tree state the grader must not alter.
#   EVAL_PRE_UNTRACKED  — sorted untracked (non-ignored) paths at snapshot time
#   EVAL_PRE_SNAP       — `git stash create` ref; EMPTY iff the tracked tree is clean. This does
#                         NOT touch the working tree (stash create only writes objects).
#   EVAL_PRE_GRADE_HEAD — HEAD, so a commit the grader sneaks in is detectable (reset --hard HEAD
#                         reverts working-tree edits, not commits).
# Returns 0 on success. Returns 1 (FAIL-CLOSED) if this isn't a git repo / HEAD can't be read —
# the caller MUST then skip grading: better not to grade than to grade without the safety net.
eval_snapshot() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "eval-isolation: not a git repo — cannot snapshot the tree (fail-closed, evaluator not run)" >&2
    return 1
  }
  EVAL_PRE_GRADE_HEAD=$(git rev-parse HEAD 2>/dev/null) || {
    echo "eval-isolation: no HEAD — cannot snapshot (fail-closed, evaluator not run)" >&2
    return 1
  }
  EVAL_PRE_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | sort)
  EVAL_PRE_SNAP=$(git stash create 2>/dev/null)
  return 0
}

# eval_restore: DESTRUCTIVE post-grade cleanup for the HEADLESS/throwaway-worktree path. Byte-for-
# byte the behavior autopilot.sh's former inline cleanup_eval_changes had (kept identical so the
# existing autopilot tests still pass). Requires the tracked tree to have been clean pre-grade
# (EVAL_PRE_SNAP empty); if it was dirty we can't tell builder from grader changes → STOP.
# Returns 0 = tree restored to the pre-grade state; 1 = ambiguous/failed (caller must NOT tick).
eval_restore() {
  if [ -n "$EVAL_PRE_SNAP" ]; then
    echo "eval-isolation: tracked tree was dirty before grading — can't isolate evaluator changes (ambiguous). STOPPING." >&2
    return 1
  fi
  local now_head new post post2
  now_head=$(git rev-parse HEAD 2>/dev/null)
  # A commit by the grader is a contract violation: undo it and STOP.
  if [ -n "$EVAL_PRE_GRADE_HEAD" ] && [ "$now_head" != "$EVAL_PRE_GRADE_HEAD" ]; then
    git reset -q --hard "$EVAL_PRE_GRADE_HEAD" 2>/dev/null || true
    echo "eval-isolation: evaluator COMMITTED during grading (HEAD moved $EVAL_PRE_GRADE_HEAD → $now_head) — reverted and STOPPING (grader must not alter the tree)." >&2
    return 1
  fi
  git reset -q --hard HEAD 2>/dev/null || true          # revert tracked edits (tree was clean → safe)
  post=$(git ls-files --others --exclude-standard 2>/dev/null | sort)
  new=$(comm -13 <(printf '%s\n' "$EVAL_PRE_UNTRACKED") <(printf '%s\n' "$post"))
  if [ -n "$new" ]; then
    printf '%s\n' "$new" | while IFS= read -r f; do [ -n "$f" ] && rm -f -- "$f"; done
  fi
  if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "eval-isolation: could not restore tracked tree after grading — STOPPING." >&2; return 1
  fi
  post2=$(git ls-files --others --exclude-standard 2>/dev/null | sort)
  if [ "$post2" != "$EVAL_PRE_UNTRACKED" ]; then
    echo "eval-isolation: untracked file set differs from pre-grade after cleanup — STOPPING." >&2; return 1
  fi
  return 0
}

# eval_changed_files: NON-DESTRUCTIVE detection for the INTERACTIVE /phase path. Names exactly what
# the evaluator touched since eval_snapshot, WITHOUT altering the tree (a human is present and must
# be able to clean up without guessing). Works even if the tree started dirty (user WIP appears in
# both snapshots and cancels out). Prints, one per line:
#   [committed] <old>→<new>     the grader committed (HEAD moved)
#   [modified]  <path>          a tracked file changed since the snapshot
#   [created]   <path>          a new untracked file appeared since the snapshot
# Returns 1 if it printed anything (the grader wrote), 0 if the tree is untouched.
eval_changed_files() {
  local now_head now_snap pre_ref now_ref tracked post new out=""
  now_head=$(git rev-parse HEAD 2>/dev/null)
  if [ -n "$EVAL_PRE_GRADE_HEAD" ] && [ "$now_head" != "$EVAL_PRE_GRADE_HEAD" ]; then
    out="${out}[committed] ${EVAL_PRE_GRADE_HEAD}→${now_head}"$'\n'
  fi
  # Tracked modifications: compare the snapshot's tracked state to a fresh one. `git stash create`
  # is empty when the tree is clean, so fall back to HEAD in that case. Diffing the two refs' trees
  # cancels any pre-existing WIP, leaving only what changed between snapshot and now.
  now_snap=$(git stash create 2>/dev/null)
  pre_ref="${EVAL_PRE_SNAP:-$EVAL_PRE_GRADE_HEAD}"
  now_ref="${now_snap:-$now_head}"
  tracked=$(git diff --name-only "$pre_ref" "$now_ref" 2>/dev/null)
  [ -n "$tracked" ] && out="${out}$(printf '%s\n' "$tracked" | sed 's/^/[modified] /')"$'\n'
  # Untracked files created since the snapshot (set difference on the path lists).
  post=$(git ls-files --others --exclude-standard 2>/dev/null | sort)
  new=$(comm -13 <(printf '%s\n' "$EVAL_PRE_UNTRACKED") <(printf '%s\n' "$post"))
  [ -n "$new" ] && out="${out}$(printf '%s\n' "$new" | sed 's/^/[created] /')"$'\n'
  if [ -n "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
    printf '%s' "$out" | sed '/^[[:space:]]*$/d'
    return 1
  fi
  return 0
}

# Running directly = no-op (this file is a library, not a hook).
return 0 2>/dev/null || exit 0
