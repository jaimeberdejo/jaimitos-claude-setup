#!/usr/bin/env bash
# test-hooks.sh — feed each hook the kind of JSON Claude Code sends on stdin
# and confirm it runs without error. This is a smoke test, not a behavior spec:
# it catches the "hook crashes / aborts early" class of bug (the kind that
# silently broke ownership-nudge and session-start before).
#
# Run from the repo root: bash scripts/test-hooks.sh

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
export CLAUDE_PROJECT_DIR="$PWD"

FAILS=0
run() {
  local name="$1" script="$2" json="$3"
  if printf '%s' "$json" | bash "$script" >/dev/null 2>&1; then
    printf '  ✓ %s\n' "$name"
  else
    printf '  ✗ %s (exit %d)\n' "$name" "$?"
    FAILS=$((FAILS+1))
  fi
}

echo "hook smoke tests"
echo ""

run "SessionStart"            .claude/hooks/session-start.sh   '{"hook_event_name":"SessionStart","source":"startup"}'
run "UserPromptSubmit/steer"  .claude/hooks/steer.sh           '{"hook_event_name":"UserPromptSubmit","prompt":"hi"}'
run "PreToolUse/steer"        .claude/hooks/steer.sh           '{"hook_event_name":"PreToolUse","tool_name":"Edit"}'
run "PreToolUse/kill-switch"  .claude/hooks/kill-switch.sh     '{"hook_event_name":"PreToolUse","tool_name":"Bash"}'
run "PostToolUse/format"      .claude/hooks/format-on-edit.sh  '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"/nonexistent.py"}}'
run "Stop/test-gate(off)"     .claude/hooks/test-gate.sh       '{"hook_event_name":"Stop","stop_hook_active":false}'
run "Stop/commit"             .claude/hooks/commit-on-stop.sh  '{"hook_event_name":"Stop","stop_hook_active":true}'
run "Stop/ownership"          .claude/hooks/ownership-nudge.sh '{"hook_event_name":"Stop","stop_hook_active":true}'

echo ""
# Verify kill-switch actually blocks (exit 2) when AGENT_STOP exists.
touch AGENT_STOP
if printf '%s' '{"hook_event_name":"PreToolUse"}' | bash .claude/hooks/kill-switch.sh >/dev/null 2>&1; then
  printf '  ✗ kill-switch did NOT block with AGENT_STOP present\n'; FAILS=$((FAILS+1))
else
  printf '  ✓ kill-switch blocks (exit 2) when AGENT_STOP present\n'
fi
rm -f AGENT_STOP

# Verify kill-switch FAILS CLOSED even when CLAUDE_PROJECT_DIR is unset.
# Under `set -u`, an unset var must NOT abort the hook before the AGENT_STOP check.
(
  unset CLAUDE_PROJECT_DIR
  touch AGENT_STOP
  printf '%s' '{"hook_event_name":"PreToolUse"}' | bash .claude/hooks/kill-switch.sh >/dev/null 2>&1
  rc=$?
  rm -f AGENT_STOP
  exit "$rc"
)
if [ "$?" -eq 2 ]; then
  printf '  ✓ kill-switch fails closed (exit 2) when CLAUDE_PROJECT_DIR unset\n'
else
  printf '  ✗ kill-switch did NOT fail closed with CLAUDE_PROJECT_DIR unset\n'; FAILS=$((FAILS+1))
fi

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All hook smoke tests passed."; exit 0
else echo "$FAILS hook test(s) failed."; exit 1; fi
