#!/usr/bin/env bash
# test-docs-invariants.sh — guard the "no prose ticking" contract in the shipped command docs.
# Completion marking must route through scripts/tick.sh; no command file may tell the model it
# can flip roadmap checkboxes by hand, and no doc may claim the in-session tick is ungated.
# Cheap grep assertions, no model needed — a regression guard for Phase 3.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAILS=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
assert_has()    { if grep -qF  "$2" "$ROOT/$1"; then ok "$3"; else bad "$3 (expected '$2' in $1)"; fi; }
assert_absent() { if grep -qiF "$2" "$ROOT/$1"; then bad "$3 (forbidden '$2' present in $1)"; else ok "$3"; fi; }

echo "docs invariants — completion marking routes through scripts/tick.sh"
echo ""
assert_has    ".claude/commands/wrap.md"      "scripts/tick.sh"   "wrap.md routes ticking through scripts/tick.sh"
assert_has    ".claude/commands/wrap.md"      "may NOT flip"      "wrap.md forbids flipping checkboxes by hand"
assert_absent ".claude/commands/wrap.md"      "deliberately"      "wrap.md has no '(or you, deliberately)' tick bypass"
assert_has    ".claude/commands/autopilot.md" "scripts/tick.sh"   "/autopilot routes ticking through scripts/tick.sh"
assert_has    ".claude/commands/autopilot-parallel.md" "scripts/tick.sh"   "/autopilot-parallel routes ticking through scripts/tick.sh"
assert_absent ".claude/commands/autopilot-parallel.md" "flip"     "/autopilot-parallel does not claim it can flip checkboxes by hand"
assert_has    "CLAUDE.md"                      "scripts/tick.sh"   "CLAUDE.md documents the single tick gate"
assert_absent "CLAUDE.md"                      "the tick is not"  "CLAUDE.md no longer claims the in-session tick is ungated"
assert_has    ".claude/commands/autopilot.md" "Check the next phase's \`Mode:\` line BEFORE building it" \
              "/autopilot checks Mode: supervised BEFORE building, not just at tick time"
assert_has    ".claude/commands/phase.md" "if ZERO headings match at all, STOP" \
              "/phase <heading> handles zero-match arguments explicitly (no silent fall-through)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All docs-invariant checks passed."; exit 0
else echo "$FAILS docs-invariant check(s) FAILED."; exit 1; fi
