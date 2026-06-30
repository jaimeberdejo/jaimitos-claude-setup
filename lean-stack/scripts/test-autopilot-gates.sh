#!/usr/bin/env bash
# test-autopilot-gates.sh — behavioral regression tests for autopilot.sh's safety gates.
#
# These run the REAL scripts/autopilot.sh in a throwaway git repo with a STUBBED `claude`
# (and `gh`) on PATH, so we assert actual control-flow behavior — not just that the source
# contains certain strings. Guards the P0 fix: a high-stakes phase must NEVER be pushed,
# even with --pr.
#
# Exit 0 = all gates behave correctly, exit 1 = a gate regressed.

set -uo pipefail

# Resolve the scaffold root (this script lives in <scaffold>/scripts/).
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTOPILOT="$SCAFFOLD/scripts/autopilot.sh"
HS_LIB="$SCAFFOLD/.claude/hooks/_high-stakes.sh"
SS_LIB="$SCAFFOLD/.claude/hooks/_secret-scan.sh"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

[ -f "$AUTOPILOT" ] || { echo "test: cannot find autopilot.sh at $AUTOPILOT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test: jq required (autopilot preflight needs it)"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

# --- build a throwaway project that looks like an installed lean-stack repo ---
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack)"
cleanup() { rm -rf "$WORK" 2>/dev/null; git worktree prune 2>/dev/null; }
trap cleanup EXIT

REPO="$WORK/proj"
mkdir -p "$REPO/.claude/hooks" "$REPO/scripts" "$REPO/docs"
cp "$AUTOPILOT" "$REPO/scripts/autopilot.sh"
cp "$HS_LIB" "$REPO/.claude/hooks/_high-stakes.sh"
cp "$SS_LIB" "$REPO/.claude/hooks/_secret-scan.sh"
printf '{ "permissions": { "deny": ["Read(.env)"] } }\n' > "$REPO/.claude/settings.json"
printf '## Phase 1 — Login\n\n- [ ] Build the login flow\n' > "$REPO/docs/ROADMAP.md"
printf 'next: build login\n' > "$REPO/docs/STATE.md"

( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
    && git add -A && git commit -q -m init )

# --- stubs on PATH: a fake `claude` (builder + evaluator) and a fake `gh` ---
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
# Evaluator invocation carries --agent; everything else is the builder.
for a in "$@"; do
  if [ "$a" = "--agent" ]; then echo "PASS"; exit 0; fi
done
# Builder: record the phase refs the way /phase would, then write+commit a HIGH-STAKES file.
git rev-parse HEAD > .claude/.phase-base 2>/dev/null
printf '## Phase 1 — Login\n' > .claude/.phase-ready
mkdir -p auth
echo "def login(): return True" > auth/login.py
git add -A 2>/dev/null
git commit -q -m "build: auth/login.py" 2>/dev/null
exit 0
STUB
# `gh` must exist (so --pr preflight passes) and must SHOUT if ever called for a PR.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
echo "STUB-GH-INVOKED: $*"
exit 0
STUB
chmod +x "$BIN/claude" "$BIN/gh"

echo "autopilot gate tests"
echo ""

# ============================================================================
# Test 1 (P0): a high-stakes phase with --pr must NOT push and must NOT open a PR.
# ============================================================================
OUT="$WORK/run1.out"
( cd "$REPO" && PATH="$BIN:$PATH" bash scripts/autopilot.sh 1 --pr >"$OUT" 2>&1 )

if grep -q "HIGH-STAKES paths changed" "$OUT"; then
  pass "high-stakes gate fired on auth/ phase"
else
  fail "high-stakes gate did NOT fire (auth/login.py should match)"
fi

if grep -q "stays LOCAL" "$OUT"; then
  pass "branch reported as staying local"
else
  fail "no 'stays LOCAL' message — finish block may have pushed"
fi

if grep -qE "pushing .* and opening a PR|STUB-GH-INVOKED" "$OUT"; then
  fail "PUSH/PR PATH WAS ENTERED on a high-stakes phase (P0 REGRESSION)"
else
  pass "no push / no gh pr create on a high-stakes phase (P0 holds)"
fi

# The roadmap must remain unticked (high-stakes work is never auto-ticked).
if grep -q '\- \[ \] Build the login flow' "$REPO/docs/ROADMAP.md"; then
  pass "roadmap left unticked for the high-stakes phase"
else
  fail "roadmap was ticked despite the high-stakes gate"
fi

echo ""
if [ "$FAILS" -eq 0 ]; then
  echo "All autopilot gate tests passed."
  exit 0
else
  echo "$FAILS gate test(s) FAILED."
  # Surface the run output to debug.
  echo "--- last run output ---"; tail -n 30 "$OUT" 2>/dev/null
  exit 1
fi
