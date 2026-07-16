#!/usr/bin/env bash
# trace-requirements.sh — a traceability report generated FROM the canonical artifacts (docs/SPEC.md +
# docs/ROADMAP.md), never a hand-maintained spreadsheet. It runs two complementary checks via the shared
# _requirements.sh validator:
#   - requirements_lint     (STRUCTURE): a referenced id that does not resolve, a malformed id, a duplicate.
#   - requirements_orphans  (COVERAGE):  a REQ/OBJ defined and active in the spec that no phase plans.
# Report-only by default. --strict fails on STRUCTURAL problems (an unresolved reference is a real error);
# orphans stay advisory, because deferring or not-yet-scheduling an approved requirement is legitimate and
# a build-blocker there would just punish honest planning. Inert when the project defines no ids.
#
# Usage: bash scripts/trace-requirements.sh [--strict] [--roadmap <path>] [--spec <path>]
set -uo pipefail
STRICT=0; ROAD="docs/ROADMAP.md"; SPEC=""
while [ "$#" -gt 0 ]; do case "$1" in
  -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --strict) STRICT=1; shift ;;
  --roadmap) ROAD="${2:-}"; shift 2 ;;
  --spec) SPEC="${2:-}"; shift 2 ;;
  *) echo "trace-requirements: unknown argument: $1 (see --help)" >&2; exit 2 ;;
esac; done

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.claude/lib" 2>/dev/null && pwd)" || LIB=""
if [ -n "$LIB" ] && [ -f "$LIB/_requirements.sh" ]; then . "$LIB/_requirements.sh" 2>/dev/null || true; fi
command -v requirements_lint >/dev/null 2>&1 || { echo "trace-requirements: requirement validator not found — nothing to trace."; exit 0; }
[ -f "$ROAD" ] || { echo "trace-requirements: no $ROAD — nothing to trace."; exit 0; }

echo "Requirement traceability report — $ROAD"
echo ""

echo "## Structure (referenced ids resolve; ids well-formed and unique)"
LOUT=$(requirements_lint "$ROAD" ${SPEC:+"$SPEC"}); LRC=$?
if [ -n "$LOUT" ]; then printf '%s\n' "$LOUT"; else echo "  ✓ no structural problems"; fi
echo ""

echo "## Coverage (approved requirements that no phase plans)"
OOUT=$(requirements_orphans "$ROAD" ${SPEC:+"$SPEC"})
if [ -n "$OOUT" ]; then printf '%s\n' "$OOUT"; else echo "  ✓ every active requirement is planned by a phase"; fi
echo ""

if [ "$LRC" -ne 0 ]; then
  if [ "$STRICT" -eq 1 ]; then echo "trace-requirements: structural problems (--strict)."; exit 1; fi
  echo "trace-requirements: structural problems above (advisory; pass --strict to fail)."
  exit 0
fi
echo "trace-requirements: structure clean$( [ -n "$OOUT" ] && printf ' (orphans are advisory)' )."
exit 0
