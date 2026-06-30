#!/usr/bin/env bash
# Mid-run steering. Wired to BOTH UserPromptSubmit and PreToolUse so guidance
# written to STEER.md is picked up whether you're between prompts OR mid-tool-run.
#
# Both UserPromptSubmit and PreToolUse support hookSpecificOutput.additionalContext,
# and the docs do NOT guarantee plain-stdout injection on PreToolUse — so we emit
# the JSON additionalContext form for BOTH events (keyed to the actual event name).
# This makes "write STEER.md to redirect a running loop" work reliably either way.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || cd .

# Hot path: this hook fires on EVERY PreToolUse. Bail before touching stdin/jq when
# there's nothing to steer (the overwhelmingly common case).
[ -f STEER.md ] || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "UserPromptSubmit"' 2>/dev/null)

STEER_TEXT="=== OPERATOR STEERING (act on this now) ===
$(cat STEER.md)
=========================================="
rm -f STEER.md

# Emit JSON additionalContext keyed to whichever event fired (works for both).
jq -n --arg ev "$EVENT" --arg ctx "$STEER_TEXT" \
  '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}' 2>/dev/null \
  || printf '%s\n' "$STEER_TEXT"   # fallback if jq missing
exit 0
