#!/usr/bin/env bash
# PreToolUse hook — emergency stop for autonomous loops.
# `touch AGENT_STOP` in the repo root and Claude refuses all further tool calls.
# Your seatbelt for /goal and ralph-style runs.

set -uo pipefail
cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || cd .

if [ -f AGENT_STOP ]; then
  # Exit code 2 on PreToolUse blocks the tool call and feeds stderr back to Claude.
  echo "AGENT_STOP file present — halting. Remove it to resume." >&2
  exit 2
fi
exit 0
