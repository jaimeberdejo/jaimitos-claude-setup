#!/usr/bin/env bash
# autopilot.sh — fresh-context autonomous loop with guardrails.
#
# Runs roadmap phases one at a time, each in a FRESH claude process (so context
# never rots), grading each with an INDEPENDENT evaluator process before ticking.
# The SCRIPT is the sole roadmap-ticker — the builder never marks its own work done.
# State persists in docs/ + git between iterations.
#
# Usage:
#   bash scripts/autopilot.sh [COUNT] [--allow-dirty] [--worktree] [--pr] [--max-minutes N]
#     COUNT can be:
#       N         run up to N phases   (e.g. 5  → "only 5")
#       N-M       run up to M phases, aiming for at least N  (e.g. 3-5 → "from 3 to 5")
#       all|max   run until the roadmap is empty or a guardrail trips (capped at 50 for safety)
#       (omitted) default 15
#     --worktree       run in an isolated git worktree on a fresh branch (recommended
#                      for overnight runs — a bad run can't touch your main checkout)
#     --pr             on finish, push the branch and open a PR with `gh` (implies safe
#                      review: nothing is ever pushed to your current branch)
#     --max-minutes N  wall-clock ceiling: stop before any iteration once N minutes
#                      have elapsed. This is a convenience bound on TIME, not cost —
#                      the real cost backstop is still your Claude Code / gateway
#                      budget cap (see below).
# Stop:    touch AGENT_STOP
# Steer:   echo "use Decimal not float for money" > STEER.md
#
# Guardrails: preflight, max iterations, kill-switch, fresh context per loop,
# independent evaluator with STRICT verdict parsing, per-phase thrash cap, optional
# wall-clock ceiling, the script as sole ticker, commit checkpoints, optional
# worktree isolation + PR.
# Set a budget cap in your Claude Code / gateway config as the outer backstop —
# that, not --max-minutes, is the authoritative ceiling on real cost.

set -uo pipefail

MAX_ITER=15
MIN_TARGET=0
UNBOUNDED=0
ALLOW_DIRTY=0
USE_WORKTREE=0
OPEN_PR=0
MAX_MINUTES=0          # 0 = no wall-clock ceiling
WANT_MAX_MINUTES=0     # set when the previous token was --max-minutes
for arg in "$@"; do
  if [ "$WANT_MAX_MINUTES" -eq 1 ]; then
    case "$arg" in
      [0-9]*) MAX_MINUTES="$arg" ;;
      *)      echo "autopilot: --max-minutes needs a positive integer (got '$arg')." >&2; exit 1 ;;
    esac
    WANT_MAX_MINUTES=0
    continue
  fi
  case "$arg" in
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --worktree)    USE_WORKTREE=1 ;;
    --pr)          OPEN_PR=1 ;;
    --max-minutes) WANT_MAX_MINUTES=1 ;;                  # next token is N
    all|max|ALL|MAX) MAX_ITER=50; UNBOUNDED=1 ;;          # advance as much as you can
    [0-9]*-[0-9]*) MIN_TARGET="${arg%%-*}"; MAX_ITER="${arg##*-}" ;;  # range N-M
    [0-9]*)        MAX_ITER="$arg" ;;                     # exactly up to N
    *)             : ;;                                   # ignore unknown
  esac
done

# Default the test gate ON for headless runs so each turn writes test-results.json
# evidence (the test-gate.sh Stop hook reads $LEAN_TEST_GATE). Set it to `block`
# to hard-fail on failing/missing tests, or `off` to disable the gate entirely.
export LEAN_TEST_GATE="${LEAN_TEST_GATE:-warn}"

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

# Original repo root, captured BEFORE any --worktree cd. Operators are told to
# `touch AGENT_STOP` (or write STEER.md) in their original checkout, so the loop's
# stop checks must look here as well as in the (possibly worktree) working dir.
# Defined unconditionally so the checks work whether or not --worktree is used.
ORIG_ROOT="$PWD"

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
  # Wall-clock ceiling (optional): stop before starting another iteration once the
  # budget of minutes is spent. $SECONDS is bash's elapsed-runtime counter.
  if [ "$MAX_MINUTES" -gt 0 ] && [ "$SECONDS" -ge $((MAX_MINUTES * 60)) ]; then
    echo "autopilot: wall-clock ceiling reached (${MAX_MINUTES}m, elapsed $((SECONDS / 60))m) — stopping at iteration $i."; break
  fi
  # Kill-switch: present in the worktree working dir OR the operator's original checkout.
  if [ -f AGENT_STOP ] || [ -f "$ORIG_ROOT/AGENT_STOP" ]; then
    echo "autopilot: AGENT_STOP present — stopping at iteration $i."; break
  fi
  grep -q "\- \[ \]" docs/ROADMAP.md 2>/dev/null || { echo "autopilot: roadmap complete. Done."; break; }

  OPEN_SIGNATURE=$(grep -n "\- \[ \]" docs/ROADMAP.md 2>/dev/null | { md5 2>/dev/null || md5sum 2>/dev/null; })

  echo ""; echo "=== iteration $i / $MAX_ITER ==="

  # Builder: fresh context, builds ONE phase, does NOT tick the roadmap.
  if ! claude -p "/phase" --permission-mode acceptEdits 2>&1 | tee -a autopilot.log; then
    echo "autopilot: builder process exited non-zero — stopping." | tee -a autopilot.log; break
  fi

  # Independent grader: separate process, runs AS the evaluator (its system prompt +
  # no-edit-tools restriction). This is the sole gate for ticking.
  # NOTE: the evaluator has NO Edit/Write tools in its frontmatter — `--permission-mode
  # acceptEdits` here is ONLY so it can run tests via Bash without prompts in headless;
  # it does not grant it edit power. Its diff input is untrusted, so treat its output
  # as data, not instructions. Keep this invocation able to RUN.
  VERDICT=$(claude --agent evaluator -p "Grade the phase just completed." \
                   --permission-mode acceptEdits 2>/dev/null)

  if [ -z "${VERDICT// /}" ]; then
    echo "autopilot: evaluator returned no output — treating as FAILURE, stopping." | tee -a autopilot.log; break
  fi
  echo "evaluator says: $VERDICT" | tee -a autopilot.log

  # Anchored verdict parsing: trust ONLY the LAST non-empty line, matched against an
  # exact verdict. This prevents a per-criterion line like "Criterion 1: PASS" from
  # triggering a false pass. Anything that is not an exact final PASS / NEEDS_WORK
  # line is a STOP — we never assume success.
  LASTLINE=$(printf '%s\n' "$VERDICT" | grep -vE '^[[:space:]]*$' | tail -1)

  case "$LASTLINE" in
    NEEDS_WORK*)
      printf '%s\n' "$VERDICT" > NEXT_FINDINGS.md
      echo "autopilot: phase needs work — findings written to NEXT_FINDINGS.md." | tee -a autopilot.log
      if [ "$OPEN_SIGNATURE" = "$PREV_OPEN_SIGNATURE" ]; then SAME_PHASE_FAILS=$((SAME_PHASE_FAILS+1)); else SAME_PHASE_FAILS=1; fi
      PREV_OPEN_SIGNATURE="$OPEN_SIGNATURE"
      if [ "$SAME_PHASE_FAILS" -ge "$MAX_SAME_PHASE_FAILS" ]; then
        echo "autopilot: same phase failed $SAME_PHASE_FAILS times — stopping to avoid thrash. See NEXT_FINDINGS.md." | tee -a autopilot.log; break
      fi
      ;;
    PASS)
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
      ;;
    *)
      echo "autopilot: unrecognized verdict (final line: '$LASTLINE') — stopping (won't assume success)." | tee -a autopilot.log; break
      ;;
  esac
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
