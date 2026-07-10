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

# --- ignored-file blindness (finding H3) + sensitive-file guard (D4) --------------------------------
# git stash create + `ls-files --others --exclude-standard` both EXCLUDE ignored files, so an evaluator
# (or a test it runs) could create/modify an ignored fixture/cache/db/.env and the old snapshot saw
# nothing. We add a CHEAP, path-only ignored snapshot and a BOUNDED sensitive-file hash:
#   • `--directory` collapses a fully-ignored dir (node_modules/, .venv/) to ONE entry, so new fixture
#     dirs (tmp/, generated/) and root-level ignored files (a .db, .coverage) still appear but we never
#     walk a dependency tree. Newly-appeared ignored paths are then detectable + removable.
#   • Modifying a PRE-EXISTING ignored file can't be seen by a path diff (git never recorded its
#     content). We hash ONLY a small, sensitive allowlist of ignored files (.env/.pem/.netrc/…), taken
#     from the SAME collapsed listing, so a rogue grader rewriting a real .env is caught — WITHOUT
#     hashing caches or dependency trees. Arbitrary modification of every other pre-existing ignored
#     file remains structurally undetectable under this lean design (documented residual).
_eval_hash() { { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1" 2>/dev/null; } | cut -d' ' -f1; }
_eval_ignored_list() { git ls-files --others --ignored --exclude-standard --directory 2>/dev/null | sort; }
# from an ignored `--directory` listing on stdin, print entries whose basename is sensitive (skips
# collapsed dirs — trailing / — so we never descend into a node_modules/.venv the listing collapsed).
_eval_sensitive_filter() {
  local p b
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in */) continue ;; esac
    b=${p##*/}
    case "$b" in
      .env|.env.*|.netrc|*.pem|*.key|id_rsa*|credentials*.json|*.tfvars) printf '%s\n' "$p" ;;
    esac
  done
}
# echo "<sha>  <path>" for each pre-existing sensitive ignored file (input: an ignored --directory list).
_eval_sensitive_hashes() {
  local f
  _eval_sensitive_filter | while IFS= read -r f; do
    [ -f "$f" ] && printf '%s  %s\n' "$(_eval_hash "$f")" "$f"
  done
}

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
  EVAL_PRE_IGNORED=$(_eval_ignored_list)                                 # H3: ignored set (dirs collapsed)
  EVAL_PRE_SENSITIVE=$(printf '%s\n' "$EVAL_PRE_IGNORED" | _eval_sensitive_hashes)   # D4: sensitive-file hashes
  return 0
}

# _eval_new_ignored: paths present in the ignored set NOW but not at snapshot (created during grading).
_eval_new_ignored() {
  comm -13 <(printf '%s\n' "${EVAL_PRE_IGNORED:-}") <(_eval_ignored_list)
}
# _eval_tampered_sensitive: pre-existing sensitive ignored files whose hash changed since the snapshot
# (or that vanished). Echoes the offending paths.
_eval_tampered_sensitive() {
  local sha path now
  printf '%s\n' "${EVAL_PRE_SENSITIVE:-}" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    sha=${line%% *}; path=${line#*  }
    now=$( [ -f "$path" ] && _eval_hash "$path" || echo "MISSING" )
    [ "$now" != "$sha" ] && printf '%s\n' "$path"
  done
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
  # H3: remove IGNORED files/dirs the grader created during the run (only those that appeared since the
  # snapshot — never a blanket `git clean -fdx`, which would wipe the builder's node_modules/.venv and
  # break the post-grade evidence re-run). Preserving snapshot-time ignored files keeps deps intact.
  local new_ign
  new_ign=$(_eval_new_ignored)
  if [ -n "$new_ign" ]; then
    printf '%s\n' "$new_ign" | while IFS= read -r p; do [ -n "$p" ] && rm -rf -- "$p" 2>/dev/null || true; done
  fi
  # D4: a rewritten PRE-EXISTING sensitive ignored file (a real .env, *.pem, …) cannot be restored (git
  # never had its content) — so treat it as a hard STOP, not a silent cleanup.
  local tampered
  tampered=$(_eval_tampered_sensitive)
  if [ -n "$tampered" ]; then
    echo "eval-isolation: evaluator modified pre-existing SENSITIVE ignored file(s) — cannot restore, STOPPING:" >&2
    printf '%s\n' "$tampered" | sed 's/^/    /' >&2
    return 1
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
  # H3: ignored files/dirs the grader created (invisible to the untracked list above).
  local new_ign tampered
  new_ign=$(_eval_new_ignored)
  [ -n "$new_ign" ] && out="${out}$(printf '%s\n' "$new_ign" | sed 's/^/[created-ignored] /')"$'\n'
  # D4: a rewritten pre-existing sensitive ignored file.
  tampered=$(_eval_tampered_sensitive)
  [ -n "$tampered" ] && out="${out}$(printf '%s\n' "$tampered" | sed 's/^/[tampered-ignored] /')"$'\n'
  if [ -n "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
    printf '%s' "$out" | sed '/^[[:space:]]*$/d'
    return 1
  fi
  return 0
}

# Running directly = no-op (this file is a library, not a hook).
return 0 2>/dev/null || exit 0
