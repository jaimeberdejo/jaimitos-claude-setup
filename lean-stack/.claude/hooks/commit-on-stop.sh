#!/usr/bin/env bash
# Stop hook — fires when Claude finishes responding.
# Checkpoints any changes to git so you always have an undo point.
# Honest output: only claims "checkpointed" when a commit actually happened.
#
# NOTE: this stages everything (git add -A) on purpose — a checkpoint is a
# whole-tree safety net, not a curated commit. Control/scratch files are kept
# out via .gitignore. If you want curated commits, make them yourself before
# the turn ends; this only fires when the tree is otherwise dirty.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || cd .

# Guard against infinite loops: if this Stop hook itself triggered the turn, bail.
ACTIVE=$(jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$ACTIVE" = "true" ] && exit 0

# Not a git repo? Nothing to checkpoint.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Detect ANY change, including untracked files (git diff alone misses untracked).
DIRTY=$(git status --porcelain 2>/dev/null)
if [ -z "$DIRTY" ]; then
  # Nothing changed — say nothing, don't pretend we checkpointed.
  exit 0
fi

# Record which files changed BEFORE committing, so ownership-nudge (next Stop
# hook) can still see them — after the commit the working tree is clean.
# cut -c4- takes the path field (porcelain is "XY <path>"); survives spaces & renames
# where awk '{print $2}' would mangle them.
git status --porcelain 2>/dev/null | cut -c4- > .claude/.last-changed 2>/dev/null || true

COUNT=$(printf '%s\n' "$DIRTY" | grep -c . )
git add -A 2>/dev/null

# Secret guard (SHARED with autopilot.sh via _secret-scan.sh): block auto-committing the
# common credential shapes it recognizes (AWS/Stripe/Google/GitHub/Slack/OpenAI tokens,
# PEM blocks, URLs with embedded user:password). Scans the STAGED set by filename AND
# content; on any hit — OR if the scan can't run / the lib is missing — fail CLOSED:
# unstage and skip the commit rather than committing unscanned.
# NOTE: this is not a full secret scanner; review diffs for novel secret formats.
SCAN_LIB=".claude/hooks/_secret-scan.sh"
if [ ! -f "$SCAN_LIB" ]; then
  git reset -q 2>/dev/null
  echo "⛔ SECRET GUARD — $SCAN_LIB missing; cannot scan. Auto-commit SKIPPED (fail-closed)."
  echo "   Restore the guard lib (re-run install.sh) or commit deliberately after reviewing."
  exit 0
fi
# shellcheck disable=SC1090
. "$SCAN_LIB"
FINDINGS=$(secret_scan_staged); SCAN_RC=$?
if [ "$SCAN_RC" -ne 0 ]; then
  git reset -q 2>/dev/null
  echo "⛔ SECRET GUARD — auto-commit ABORTED. Nothing was committed."
  printf '%s\n' "$FINDINGS"
  echo "   Handle manually: remove the file/line, add to .gitignore, or commit deliberately."
  exit 0
fi

if git commit -m "checkpoint: $COUNT file(s) @ $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1; then
  echo "✓ checkpointed $COUNT file(s). Run /wrap to update docs/STATE.md + tick docs/ROADMAP.md before /clear."
else
  echo "⚠ nothing committed (commit failed or nothing staged). Check 'git status'."
fi
exit 0
