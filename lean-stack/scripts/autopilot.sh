#!/usr/bin/env bash
# autopilot.sh — fresh-context autonomous loop with guardrails.
#
# Runs roadmap phases one at a time, each in a FRESH claude process (so context
# never rots), grading each with an INDEPENDENT evaluator process before ticking.
# The SCRIPT is the sole roadmap-ticker — the builder never marks its own work done.
# State persists in docs/ + git between iterations.
#
# Usage:
#   bash scripts/autopilot.sh [COUNT] [--allow-dirty] [--worktree] [--pr]
#     COUNT can be:
#       N         run up to N phases   (e.g. 5  → "only 5")
#       N-M       run up to M phases, aiming for at least N  (e.g. 3-5 → "from 3 to 5")
#       all|max   run until the roadmap is empty or a guardrail trips (capped at 50 for safety)
#       (omitted) default 15
#     --worktree   run in an isolated git worktree on a fresh branch (recommended
#                  for overnight runs — a bad run can't touch your main checkout)
#     --pr         on finish, push the branch and open a PR with `gh` (implies safe
#                  review: nothing is ever pushed to your current branch)
# Stop:    touch AGENT_STOP
# Steer:   echo "use Decimal not float for money" > STEER.md
#
# Guardrails: preflight, max iterations, kill-switch, fresh context per loop,
# independent evaluator with STRICT verdict parsing, per-phase thrash cap, the
# script as sole ticker, commit checkpoints, optional worktree isolation + PR.
# Set a budget cap in your Claude Code / gateway config as the outer backstop.

set -uo pipefail

MAX_ITER=15
MIN_TARGET=0
UNBOUNDED=0
ALLOW_DIRTY=0
USE_WORKTREE=0
OPEN_PR=0
for arg in "$@"; do
  case "$arg" in
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --worktree)    USE_WORKTREE=1 ;;
    --pr)          OPEN_PR=1 ;;
    all|max|ALL|MAX) MAX_ITER=50; UNBOUNDED=1 ;;          # advance as much as you can
    [0-9]*-[0-9]*) MIN_TARGET="${arg%%-*}"; MAX_ITER="${arg##*-}" ;;  # range N-M
    [0-9]*)        MAX_ITER="$arg" ;;                     # exactly up to N
    *)             : ;;                                   # ignore unknown
  esac
done

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

# ----------------------------- preflight -----------------------------
fail() { echo "autopilot: PREFLIGHT FAILED — $1" >&2; exit 1; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git repository (run 'git init')."
command -v claude >/dev/null 2>&1 || fail "'claude' CLI not found on PATH."
command -v jq     >/dev/null 2>&1 || fail "'jq' not found (hooks need it)."
[ -f .claude/settings.json ] || fail "missing .claude/settings.json."
[ -f docs/ROADMAP.md ]       || fail "missing docs/ROADMAP.md."
[ -f docs/STATE.md ]         || fail "missing docs/STATE.md."

if [ "$ALLOW_DIRTY" -eq 0 ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  fail "working tree is dirty. Commit/stash first, or pass --allow-dirty."
fi
if [ "$OPEN_PR" -eq 1 ] && ! command -v gh >/dev/null 2>&1; then
  fail "--pr requested but 'gh' (GitHub CLI) is not installed."
fi
if ! grep -q "\- \[ \]" docs/ROADMAP.md 2>/dev/null; then
  echo "autopilot: roadmap has no open items. Nothing to do."; exit 0
fi

# ----------------------- optional worktree isolation -----------------------
BRANCH=""
if [ "$USE_WORKTREE" -eq 1 ]; then
  STAMP=$(date +%Y%m%d-%H%M%S)
  BRANCH="autopilot/$STAMP"
  WT_DIR="$(cd .. && pwd)/$(basename "$PWD")-autopilot-$STAMP"
  echo "autopilot: creating isolated worktree → $WT_DIR (branch $BRANCH)"
  git worktree add -b "$BRANCH" "$WT_DIR" HEAD >/dev/null 2>&1 || fail "could not create worktree."
  cd "$WT_DIR" || fail "could not enter worktree."
fi

chmod +x .claude/hooks/*.sh scripts/*.sh 2>/dev/null || true

if [ "$UNBOUNDED" -eq 1 ]; then
  echo "autopilot: advancing until the roadmap is empty (safety cap $MAX_ITER). touch AGENT_STOP to halt."
elif [ "$MIN_TARGET" -gt 0 ]; then
  echo "autopilot: aiming for $MIN_TARGET–$MAX_ITER phases (hard cap $MAX_ITER). touch AGENT_STOP to halt."
else
  echo "autopilot: up to $MAX_ITER iterations. touch AGENT_STOP to halt."
fi

# Tick every "- [ ]" line under the phase heading recorded in .claude/.phase-ready,
# up to the next "## " heading. Deterministic; the script owns roadmap state.
tick_phase() {
  local heading; heading=$(cat .claude/.phase-ready 2>/dev/null)
  [ -z "$heading" ] && { echo "autopilot: no .phase-ready heading — cannot tick."; return 1; }
  if ! grep -qF "$heading" docs/ROADMAP.md; then
    echo "autopilot: WARNING — phase heading not found verbatim in ROADMAP ('$heading'). Not ticking — check .claude/.phase-ready vs the roadmap heading."
    return 1
  fi
  local before after
  before=$(grep -c '\- \[ \]' docs/ROADMAP.md 2>/dev/null || echo 0)
  awk -v ph="$heading" '
    $0==ph { inphase=1; print; next }
    /^## / && inphase { inphase=0 }
    inphase { gsub(/- \[ \]/, "- [x]") }
    { print }
  ' docs/ROADMAP.md > docs/ROADMAP.md.tmp && mv docs/ROADMAP.md.tmp docs/ROADMAP.md
  after=$(grep -c '\- \[ \]' docs/ROADMAP.md 2>/dev/null || echo 0)
  rm -f .claude/.phase-ready
  if [ "$after" -ge "$before" ]; then
    echo "autopilot: WARNING — tick changed no items under '$heading' (maybe already ticked, or no '- [ ]' in that section)."
    return 1
  fi
  echo "autopilot: ticked phase → $heading ($((before - after)) item(s))"
}

PREV_OPEN_SIGNATURE=""
SAME_PHASE_FAILS=0
MAX_SAME_PHASE_FAILS=3

for i in $(seq 1 "$MAX_ITER"); do
  [ -f AGENT_STOP ] && { echo "autopilot: AGENT_STOP present — stopping at iteration $i."; break; }
  grep -q "\- \[ \]" docs/ROADMAP.md 2>/dev/null || { echo "autopilot: roadmap complete. Done."; break; }

  OPEN_SIGNATURE=$(grep -n "\- \[ \]" docs/ROADMAP.md 2>/dev/null | { md5 2>/dev/null || md5sum 2>/dev/null; })

  echo ""; echo "=== iteration $i / $MAX_ITER ==="

  # Builder: fresh context, builds ONE phase, does NOT tick the roadmap.
  if ! claude -p "/phase" --permission-mode acceptEdits 2>&1 | tee -a autopilot.log; then
    echo "autopilot: builder process exited non-zero — stopping." | tee -a autopilot.log; break
  fi

  # Independent grader: separate process, runs AS the evaluator (its system prompt +
  # no-edit-tools restriction). This is the sole gate for ticking.
  VERDICT=$(claude --agent evaluator -p "Grade the phase just completed." \
                   --permission-mode acceptEdits 2>/dev/null | tail -10)

  if [ -z "${VERDICT// /}" ]; then
    echo "autopilot: evaluator returned no output — treating as FAILURE, stopping." | tee -a autopilot.log; break
  fi
  echo "evaluator says: $VERDICT" | tee -a autopilot.log

  if printf '%s\n' "$VERDICT" | grep -q "NEEDS_WORK"; then
    printf '%s\n' "$VERDICT" > NEXT_FINDINGS.md
    echo "autopilot: phase needs work — findings written to NEXT_FINDINGS.md." | tee -a autopilot.log
    if [ "$OPEN_SIGNATURE" = "$PREV_OPEN_SIGNATURE" ]; then SAME_PHASE_FAILS=$((SAME_PHASE_FAILS+1)); else SAME_PHASE_FAILS=1; fi
    PREV_OPEN_SIGNATURE="$OPEN_SIGNATURE"
    if [ "$SAME_PHASE_FAILS" -ge "$MAX_SAME_PHASE_FAILS" ]; then
      echo "autopilot: same phase failed $SAME_PHASE_FAILS times — stopping to avoid thrash. See NEXT_FINDINGS.md." | tee -a autopilot.log; break
    fi
  elif printf '%s\n' "$VERDICT" | grep -q "PASS"; then
    # ONLY now — on an independent PASS — does the roadmap get ticked, by the script.
    tick_phase 2>&1 | tee -a autopilot.log
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      echo "autopilot: ticking failed (see warning above) — stopping rather than re-running the same phase." | tee -a autopilot.log
      break
    fi
    git add -A 2>/dev/null
    git commit -m "autopilot: phase passed independent grade (iteration $i)" >/dev/null 2>&1 || true
    rm -f NEXT_FINDINGS.md
    SAME_PHASE_FAILS=0; PREV_OPEN_SIGNATURE=""
  else
    echo "autopilot: verdict was neither PASS nor NEEDS_WORK — stopping (won't assume success)." | tee -a autopilot.log; break
  fi
done

# ----------------------------- finish / PR -----------------------------
if [ "$USE_WORKTREE" -eq 1 ] && [ "$OPEN_PR" -eq 1 ]; then
  echo "autopilot: pushing $BRANCH and opening a PR..."
  if git push -u origin "$BRANCH" >/dev/null 2>&1; then
    gh pr create --fill --title "autopilot: $BRANCH" 2>&1 | tee -a autopilot.log || echo "autopilot: gh pr create failed — open it manually."
  else
    echo "autopilot: git push failed (no remote / auth?). Branch $BRANCH is local; review and push manually."
  fi
elif [ "$USE_WORKTREE" -eq 1 ]; then
  echo "autopilot: done. Review branch $BRANCH in $PWD, then merge or 'git worktree remove' when finished."
fi

echo "autopilot: finished."
