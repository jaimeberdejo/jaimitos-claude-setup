#!/usr/bin/env bash
# test-models.sh — behavioral tests for scripts/models.sh, the deterministic get/set for
# which model each /phase stage uses. Regression guard for the frontmatter-mutation contract:
# exact insert-vs-replace-vs-remove behavior, all=/explicit-override precedence, validation
# refuses BEFORE touching any file, and the body below frontmatter is never touched.

set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS="$SCAFFOLD/scripts/models.sh"
[ -f "$MODELS" ] || { echo "test: cannot find models.sh at $MODELS" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-models)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
REPO="$WORK/proj"; mkdir -p "$REPO/.claude/agents"
cd "$REPO" || exit 1
git init -q && git config user.email t@t.t && git config user.name t

all_bodies() {
  cat .claude/agents/researcher.md .claude/agents/planner.md .claude/agents/executor.md .claude/agents/evaluator.md 2>/dev/null
}

write_fixture() {
  cat > .claude/agents/researcher.md <<'EOF'
---
name: researcher
description: test fixture
tools: Read, Glob, Grep, WebFetch, WebSearch
---
body unchanged marker RESEARCHER
EOF
  cat > .claude/agents/planner.md <<'EOF'
---
name: planner
description: test fixture
tools: Read, Glob, Grep, Write
---
body unchanged marker PLANNER
EOF
  cat > .claude/agents/executor.md <<'EOF'
---
name: executor
description: test fixture
tools: Read, Write, Edit, Bash, Glob, Grep
---
body unchanged marker EXECUTOR
EOF
  cat > .claude/agents/evaluator.md <<'EOF'
---
name: evaluator
description: test fixture
tools: Read, Glob, Grep, Bash
model: sonnet
---
body unchanged marker EVALUATOR
EOF
  git add -A >/dev/null 2>&1 && git commit -q -m fixture --allow-empty
}

echo "models.sh tests"; echo ""

echo "Default show: research/plan/exec inherit, eval sonnet"
write_fixture
OUT=$(bash "$MODELS")
echo "$OUT" | grep -qE '^research: *\(inherits session model\)$' && pass "research inherits by default" || fail "research default wrong: $OUT"
echo "$OUT" | grep -qE '^plan: *\(inherits session model\)$'     && pass "plan inherits by default"     || fail "plan default wrong"
echo "$OUT" | grep -qE '^exec: *\(inherits session model\)$'     && pass "exec inherits by default"     || fail "exec default wrong"
echo "$OUT" | grep -qE '^eval: *sonnet$'                          && pass "eval defaults to sonnet"      || fail "eval default wrong"

echo ""
echo "exec=opus inserts exactly one model: line"
write_fixture
bash "$MODELS" exec=opus >/dev/null
[ "$(grep -c '^model:' .claude/agents/executor.md)" -eq 1 ] && pass "exactly one model: line after insert" || fail "wrong number of model: lines"
grep -q '^model: opus$' .claude/agents/executor.md && pass "model: opus present" || fail "model: opus not found"

echo ""
echo "Updating exec replaces the existing line, never duplicates it"
bash "$MODELS" exec=sonnet >/dev/null
[ "$(grep -c '^model:' .claude/agents/executor.md)" -eq 1 ] && pass "still exactly one model: line after update" || fail "update duplicated the model: line"
grep -q '^model: sonnet$' .claude/agents/executor.md && pass "model: line updated to sonnet" || fail "update did not take effect"

echo ""
echo "all=haiku exec=sonnet: exec ends up sonnet, the other three end up haiku"
write_fixture
bash "$MODELS" all=haiku exec=sonnet >/dev/null
grep -q '^model: sonnet$' .claude/agents/executor.md   && pass "exec (explicit) = sonnet"    || fail "exec did not win over all="
grep -q '^model: haiku$'  .claude/agents/researcher.md && pass "research (via all=) = haiku" || fail "research not set by all="
grep -q '^model: haiku$'  .claude/agents/planner.md    && pass "plan (via all=) = haiku"     || fail "plan not set by all="
grep -q '^model: haiku$'  .claude/agents/evaluator.md  && pass "eval (via all=) = haiku"     || fail "eval not set by all="

echo ""
echo "reset restores each role to ITS OWN shipped default (not the same value for all four)"
bash "$MODELS" reset >/dev/null
grep -qE '^model:' .claude/agents/researcher.md       && fail "researcher still has a model: line after reset" || pass "researcher reset to inherit"
grep -qE '^model:' .claude/agents/planner.md          && fail "planner still has a model: line after reset"    || pass "planner reset to inherit"
grep -qE '^model:' .claude/agents/executor.md         && fail "executor still has a model: line after reset"   || pass "executor reset to inherit"
grep -q '^model: sonnet$' .claude/agents/evaluator.md && pass "evaluator reset to its own default (sonnet)"    || fail "evaluator not reset to sonnet"

echo ""
echo "Invalid key refuses, touches nothing"
write_fixture
BEFORE=$(all_bodies)
bash "$MODELS" bogus=opus >/dev/null 2>&1 && fail "invalid key did not exit nonzero" || pass "invalid key exits nonzero"
AFTER=$(all_bodies)
[ "$BEFORE" = "$AFTER" ] && pass "invalid key left all 4 files untouched" || fail "invalid key modified a file"

echo ""
echo "Empty value refuses, touches nothing"
BEFORE=$(all_bodies)
bash "$MODELS" exec= >/dev/null 2>&1 && fail "empty value did not exit nonzero" || pass "empty value exits nonzero"
AFTER=$(all_bodies)
[ "$BEFORE" = "$AFTER" ] && pass "empty value left all 4 files untouched" || fail "empty value modified a file"

echo ""
echo "Malformed value (embedded ':') refuses without modifying files"
BEFORE=$(all_bodies)
bash "$MODELS" exec="bad:value" >/dev/null 2>&1 && fail "malformed value did not exit nonzero" || pass "malformed value exits nonzero"
AFTER=$(all_bodies)
[ "$BEFORE" = "$AFTER" ] && pass "malformed value left all 4 files untouched" || fail "malformed value modified a file"

echo ""
echo "Batch validation is atomic: one bad pair blocks the WHOLE batch, including the good pairs"
BEFORE=$(cat .claude/agents/planner.md)
bash "$MODELS" plan=opus exec="bad value" >/dev/null 2>&1
AFTER=$(cat .claude/agents/planner.md)
[ "$BEFORE" = "$AFTER" ] && pass "good pair in a bad batch was NOT applied" || fail "batch was partially applied"

echo ""
echo "Body below frontmatter, and other frontmatter fields, remain byte-identical after a set"
write_fixture
bash "$MODELS" exec=opus >/dev/null
grep -q "body unchanged marker EXECUTOR" .claude/agents/executor.md && pass "executor body untouched" || fail "executor body was altered"
grep -q "^name: executor$" .claude/agents/executor.md && pass "executor's other frontmatter fields untouched" || fail "other frontmatter fields altered"

echo ""
echo "settings.json is never touched, if present"
printf '{"permissions":{"deny":[]}}\n' > .claude/settings.json
BEFORE=$(cat .claude/settings.json)
bash "$MODELS" exec=opus >/dev/null
AFTER=$(cat .claude/settings.json)
[ "$BEFORE" = "$AFTER" ] && pass "settings.json byte-identical after a set" || fail "settings.json was modified"
rm -f .claude/settings.json

echo ""
echo "Duplicate pre-existing model: lines are refused, not silently picked from"
write_fixture
cat > .claude/agents/executor.md <<'EOF'
---
name: executor
description: corrupted fixture with two model: lines
tools: Read
model: opus
model: sonnet
---
body
EOF
bash "$MODELS" exec=haiku >/dev/null 2>&1 && fail "did not refuse a corrupted (duplicate model:) file" || pass "refuses when a role file already has duplicate model: lines"

echo ""
echo "CLAUDE_CODE_SUBAGENT_MODEL warning appears in the no-arg report only when set"
write_fixture
OUT=$(CLAUDE_CODE_SUBAGENT_MODEL=haiku bash "$MODELS")
echo "$OUT" | grep -q "CLAUDE_CODE_SUBAGENT_MODEL=haiku" && pass "warns when CLAUDE_CODE_SUBAGENT_MODEL is set" || fail "no warning shown"
OUT2=$(bash "$MODELS")
echo "$OUT2" | grep -q "CLAUDE_CODE_SUBAGENT_MODEL" && fail "warns even when the env var is unset" || pass "no warning when the env var is unset"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All models.sh tests passed."; exit 0
else echo "$FAILS models.sh test(s) FAILED."; exit 1; fi
