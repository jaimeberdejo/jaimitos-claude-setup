#!/usr/bin/env bash
# PostToolUse hook (matcher: Write|Edit|MultiEdit)
# Auto-formats and lints the file Claude just touched. Deterministic, runs
# outside the context window, ~zero token cost. This is your "verify" discipline
# without asking Claude to remember anything.
#
# Best-effort: if a formatter isn't installed it is skipped silently — formatting
# should never block or error a turn.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || cd .

# Claude Code passes hook input as JSON on stdin; pull the edited file path.
FILE=$(jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[ -z "${FILE:-}" ] && exit 0
[ ! -f "$FILE" ] && exit 0

case "$FILE" in
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      ruff format "$FILE" >/dev/null 2>&1 || true
      ruff check --fix "$FILE" >/dev/null 2>&1 || true
    fi
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    # Use the project-local binaries via npx; --no-install means we only run them
    # if the project actually depends on them (no surprise global mutations).
    npx --no-install prettier --write "$FILE" >/dev/null 2>&1 || true
    npx --no-install eslint --fix "$FILE" >/dev/null 2>&1 || true
    ;;
esac
exit 0
