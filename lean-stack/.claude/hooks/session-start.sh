#!/usr/bin/env bash
# SessionStart hook — re-injects project state into Claude's context.
# stdout from SessionStart IS added to the context window (one of only
# a few events for which that is true), so this is the "never forget" mechanism.
# Fires on: startup, resume, clear, compact.
#
# NOTE: deliberately NOT using `set -e`. A SIGPIPE from `head` closing a pipe
# early (see the ARCHITECTURE sed|head below) would otherwise abort the hook
# and silently drop everything after it. We want best-effort, print-what-we-can.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 0

echo "=== PROJECT STATE (auto-injected) ==="

# Previous evaluator findings take priority — address these before new work.
if [ -f NEXT_FINDINGS.md ]; then
  echo "--- ⚠ Previous evaluator findings (address before selecting new roadmap work) ---"
  cat NEXT_FINDINGS.md
  echo ""
fi

if [ -f docs/STATE.md ]; then
  echo "--- docs/STATE.md ---"
  cat docs/STATE.md
fi

if [ -f docs/ARCHITECTURE.md ]; then
  echo ""
  echo "--- docs/ARCHITECTURE.md (overview only) ---"
  # Print just the overview + entry points, not the whole map, to stay lean.
  # `cat | sed | head` keeps SIGPIPE contained to a subshell so it can't abort us.
  { sed -n '1,/^## Module map/p' docs/ARCHITECTURE.md | head -40; } 2>/dev/null || true
  echo "(run the mapme skill to regenerate the full map)"
fi

if [ -f docs/ROADMAP.md ]; then
  echo ""
  echo "--- Open roadmap items ---"
  grep -n "\- \[ \]" docs/ROADMAP.md 2>/dev/null | head -20 || echo "(none — roadmap complete or empty)"
fi

echo ""
echo "--- Recent commits ---"
git log --oneline -8 2>/dev/null || echo "(no git history yet)"

echo ""
echo "=== Read docs/SPEC.md if you need the full intent. One feature per session. ==="
