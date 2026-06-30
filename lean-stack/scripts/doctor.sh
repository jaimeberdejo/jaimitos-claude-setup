#!/usr/bin/env bash
# doctor.sh — one-command health check for the lean-stack setup.
# Verifies the things autopilot.sh and the hooks silently depend on.
# Exit 0 = healthy, exit 1 = problems found.

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

PROBLEMS=0
ok()   { printf '  ✓ %s\n' "$1"; }
bad()  { printf '  ✗ %s\n' "$1"; PROBLEMS=$((PROBLEMS+1)); }
warn() { printf '  ! %s\n' "$1"; }

echo "lean-stack doctor"
echo ""

echo "Tooling:"
command -v claude  >/dev/null 2>&1 && ok "claude CLI on PATH" || bad "claude CLI not found"
command -v jq      >/dev/null 2>&1 && ok "jq installed (hooks need it)" || bad "jq not found"
command -v git     >/dev/null 2>&1 && ok "git installed" || bad "git not found"
command -v ruff    >/dev/null 2>&1 && ok "ruff available (Python format/lint)" || warn "ruff not found (Python formatting skipped)"
command -v node    >/dev/null 2>&1 && ok "node available (JS/TS tooling)"       || warn "node not found (JS/TS formatting skipped)"
echo ""

echo "Repo:"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && ok "inside a git repo" || bad "not a git repo (run 'git init')"
echo ""

echo "Scaffold files:"
for f in .claude/settings.json docs/SPEC.md docs/ROADMAP.md docs/STATE.md CLAUDE.md scripts/autopilot.sh; do
  [ -f "$f" ] && ok "$f" || bad "missing $f"
done
[ -d docs/plans ] && ok "docs/plans/ exists" || warn "docs/plans/ missing (/phase writes here)"
echo ""

echo "settings.json:"
if [ -f .claude/settings.json ]; then
  jq empty .claude/settings.json >/dev/null 2>&1 && ok "valid JSON" || bad "settings.json is not valid JSON"
  jq -e '.permissions.deny | length > 0' .claude/settings.json >/dev/null 2>&1 \
    && ok "permissions.deny present (secret-read protection)" \
    || warn "no permissions.deny — Claude can read .env/secrets. Add deny rules."
fi
echo ""

echo "Hooks executable:"
for h in .claude/hooks/*.sh scripts/*.sh; do
  [ -f "$h" ] || continue
  if [ -x "$h" ]; then ok "$h"; else bad "$h not executable (run: chmod +x $h)"; fi
done
echo ""

echo "Hook shell syntax:"
for h in .claude/hooks/*.sh scripts/*.sh; do
  [ -f "$h" ] || continue
  bash -n "$h" 2>/dev/null && ok "$h parses" || bad "$h has a syntax error"
done
echo ""

if [ "$PROBLEMS" -eq 0 ]; then
  echo "All good. Setup looks healthy."
  exit 0
else
  echo "$PROBLEMS problem(s) found. Fix the ✗ items above before an unattended run."
  exit 1
fi
