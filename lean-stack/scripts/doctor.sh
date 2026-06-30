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
[ -f .claude/.lean-stack-version ] && echo "lean-stack version: $(cat .claude/.lean-stack-version)"
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

echo "Agents, commands, rules:"
[ -f .claude/agents/evaluator.md ] && ok ".claude/agents/evaluator.md" || bad "missing .claude/agents/evaluator.md (independent grader)"
for c in resume wrap phase autopilot; do
  [ -f ".claude/commands/$c.md" ] && ok ".claude/commands/$c.md" || bad "missing .claude/commands/$c.md"
done
[ -f .claude/rules/high-stakes.md ] && ok ".claude/rules/high-stakes.md" || bad "missing .claude/rules/high-stakes.md"
echo ""

echo "Hook files present:"
for h in session-start steer kill-switch format-on-edit test-gate commit-on-stop ownership-nudge; do
  [ -f ".claude/hooks/$h.sh" ] && ok ".claude/hooks/$h.sh" || bad "missing .claude/hooks/$h.sh"
done
# Shared guard libraries — sourced by commit-on-stop.sh and autopilot.sh. If absent,
# the secret-scan and high-stakes gates silently disable, so treat as hard failures.
for lib in _secret-scan _high-stakes; do
  [ -f ".claude/hooks/$lib.sh" ] && ok ".claude/hooks/$lib.sh (shared guard lib)" || bad "missing .claude/hooks/$lib.sh (secret/high-stakes gate disabled without it)"
done
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

echo "CLAUDE.md placeholders:"
if [ -f CLAUDE.md ]; then
  # Any unresolved <...> token is a placeholder, not just the piped command form —
  # catches '<NAME>', '<pytest -q | npm test>', etc. Report the offending lines.
  PH_LINES=$(grep -nE '<[^>]+>' CLAUDE.md 2>/dev/null)
  if [ -n "$PH_LINES" ]; then
    warn "un-substituted <...> placeholder(s) in CLAUDE.md — fill them in with your real values:"
    printf '%s\n' "$PH_LINES" | sed 's/^/      /'
  else
    ok "no <...> placeholders left in CLAUDE.md"
  fi
fi
echo ""

if [ "$PROBLEMS" -eq 0 ]; then
  echo "All good. Setup looks healthy."
  exit 0
else
  echo "$PROBLEMS problem(s) found. Fix the ✗ items above before an unattended run."
  exit 1
fi
