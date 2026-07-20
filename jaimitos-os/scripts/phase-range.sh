#!/usr/bin/env bash
# phase-range.sh — print the ONE trusted phase window (read-only CLI over _phase-range.sh).
#
# Every consumer that must judge the SAME phase reads it from here (or the shared lib directly):
# the independent evaluator, /wrap, record-grade.sh, test-evidence.sh and tick.sh. It resolves the
# base with the shared precedence (TICK_BASE → .claude/.phase-anchor → .claude/.phase-base), validates
# it strict-ancestor, and prints:
#
#   Phase:  <## Phase N — heading>
#   Base:   <base sha>
#   Head:   <head sha>
#   Range:  <base>..<head>
#   Source: <where the base came from>
#
# Flags: --base | --head | --range print just that one value (for `git diff "$(phase-range.sh --base)"`).
# Exit: 0 on a resolved+validated window; 1 if it cannot be resolved (fail-closed); 3 if the anchor
# base-integrity check detects a narrowed window (supervised). It MUTATES NOTHING.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" 2>/dev/null || { echo "phase-range: ⛔ not a git repo" >&2; exit 1; }

WHICH="all"
case "${1:-}" in
  -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --base)  WHICH="base" ;;
  --head)  WHICH="head" ;;
  --range) WHICH="range" ;;
  "" ) : ;;
  *) echo "phase-range: unknown argument '$1' (try --help)" >&2; exit 2 ;;
esac

# Roadmap lib gives resolve_phase_range a first-open heading when no anchor names one.
[ -f .claude/lib/_roadmap.sh ]     && . .claude/lib/_roadmap.sh     2>/dev/null || true
[ -f .claude/lib/_phase-range.sh ] && . .claude/lib/_phase-range.sh 2>/dev/null || true
command -v resolve_phase_range >/dev/null 2>&1 || { echo "phase-range: ⛔ resolver unavailable (fail-closed)" >&2; exit 1; }

resolve_phase_range; rc=$?
if [ "$rc" != 0 ]; then
  echo "phase-range: ⛔ $PR_ERR" >&2
  exit "$rc"
fi

case "$WHICH" in
  base)  printf '%s\n' "$PR_BASE_SHA" ;;
  head)  printf '%s\n' "$PR_HEAD" ;;
  range) printf '%s\n' "$PR_RANGE" ;;
  all)
    printf 'Phase:  %s\n' "${PR_HEADING:-<unknown>}"
    printf 'Base:   %s\n' "$PR_BASE_SHA"
    printf 'Head:   %s\n' "$PR_HEAD"
    printf 'Range:  %s\n' "$PR_RANGE"
    printf 'Source: %s\n' "$PR_SOURCE"
    ;;
esac
exit 0
