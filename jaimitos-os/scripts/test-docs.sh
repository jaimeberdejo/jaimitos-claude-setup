#!/usr/bin/env bash
# test-docs.sh — keep the docs from silently desyncing from the repo:
#   1. every "<N> skills" count declared in README.md / skills/README.md matches reality
#      (total skill dirs, or total minus the global-only installer);
#   2. every shipped-file path cited in inline code in README.md / GUIDE.md exists
#      (scripts/, sandbox/, skills/, .claude/, .github/, toolkit-docs/, docs/dev/ — runtime
#      state files and target-project docs are out of scope: they don't exist in this repo
#      by design);
#   3. every "<N> shared/sourced lib(s)" count declared in README.md / GUIDE.md matches the real
#      .claude/lib/_*.sh count. `_eval-isolation.sh` was extracted in v2.5.0 and three separate
#      docs still said "three" a whole minor release later — exactly the rot check 1 already
#      prevents for skills. Counts are written as digits OR as English number words, so both forms
#      are recognized (a word form is what actually rotted).
# Runs from the wrapper repo when available; inside an installed project (no wrapper docs)
# it degrades to a no-op pass — install-smoke owns doc checks in that context.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$SCAFFOLD/.." && pwd)"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

echo "docs-vs-repo consistency tests"; echo ""

if [ ! -d "$ROOT/skills" ] || [ ! -f "$ROOT/README.md" ]; then
  echo "  - SKIPPED: no wrapper repo around this scaffold (installed project) — nothing to check."
  exit 0
fi

TOTAL=$(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
PORTABLE=$((TOTAL - 1))   # setup-jaimitos-os is global-only, never per-project

# 1 — declared "<N> skills" counts. Every such mention must be the total or the portable count.
BAD_COUNTS=""
for doc in "$ROOT/README.md" "$ROOT/skills/README.md"; do
  while IFS= read -r n; do
    [ "$n" = "$TOTAL" ] || [ "$n" = "$PORTABLE" ] || BAD_COUNTS="$BAD_COUNTS ${doc##*/}:$n"
  done < <(grep -oE '[0-9]+ (portable )?skills' "$doc" 2>/dev/null | grep -oE '^[0-9]+')
done
if [ -z "$BAD_COUNTS" ]; then
  pass "all '<N> skills' mentions in README.md + skills/README.md equal $TOTAL (total) or $PORTABLE (per-project)"
else
  fail "stale skill counts (real: $TOTAL total / $PORTABLE per-project):$BAD_COUNTS"
fi

# 2 — cited paths exist. Inline-code tokens that look like shipped paths, resolved against the
# repo root, the scaffold, or (for .claude/skills/*) the wrapper's skills/ source root.
MISSING=""
CANDS=$(grep -ohE '`[^` ]+`' "$ROOT/README.md" "$SCAFFOLD/toolkit-docs/GUIDE.md" 2>/dev/null \
  | tr -d '\140' | sort -u \
  | grep -E '^(scripts/|sandbox/|skills/|\.claude/|\.github/|toolkit-docs/|docs/dev/|jaimitos-os/|install\.sh$)' \
  | grep -vE '[<>*{}|]|\.\.\.|/$' \
  | grep -vE '^\.claude/\.')                       # .claude/.phase-base etc. = runtime state
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ -e "$ROOT/$p" ] || [ -e "$SCAFFOLD/$p" ]; then continue; fi
  case "$p" in
    .claude/skills/*) [ -e "$ROOT/skills/${p#.claude/skills/}" ] && continue ;;
  esac
  MISSING="$MISSING $p"
done <<< "$CANDS"
if [ -z "$MISSING" ]; then
  pass "every shipped-file path cited in README.md / GUIDE.md exists"
else
  fail "cited path(s) do not exist:$MISSING"
fi

# 3 — declared shared-lib counts, bound to `.claude/lib/_*.sh` (the ground truth).
# Accepts a digit or an English number word, since the docs use both ("4 shared libs",
# "four shared libs", "Four sourced libraries").
lib_count_of() {   # echo the numeric value of a declared count token; empty if not a number we know
  local w
  w=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$w" in
    ''|*[!0-9]*)
      case "$w" in
        one) printf '1' ;; two) printf '2' ;; three) printf '3' ;; four) printf '4' ;; five) printf '5' ;;
        six) printf '6' ;; seven) printf '7' ;; eight) printf '8' ;; nine) printf '9' ;; ten) printf '10' ;;
        *) printf '' ;;
      esac ;;
    *) printf '%s' "$w" ;;
  esac
}
LIBS=$(find "$SCAFFOLD/.claude/lib" -maxdepth 1 -type f -name '_*.sh' 2>/dev/null | wc -l | tr -d ' ')
BAD_LIBS=""
for doc in "$ROOT/README.md" "$SCAFFOLD/toolkit-docs/GUIDE.md"; do
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    [ "$(lib_count_of "$tok")" = "$LIBS" ] || BAD_LIBS="$BAD_LIBS ${doc##*/}:'$tok'"
  done < <(grep -ohiE '([0-9]+|one|two|three|four|five|six|seven|eight|nine|ten)[[:space:]]+(shared|sourced)[[:space:]]+(lib|libs|libraries)' "$doc" 2>/dev/null \
             | awk '{print $1}')
done
if [ -z "$BAD_LIBS" ]; then
  pass "all '<N> shared/sourced lib' mentions in README.md + GUIDE.md equal $LIBS (real .claude/lib/_*.sh count)"
else
  fail "stale shared-lib counts (real: $LIBS):$BAD_LIBS"
fi

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All docs consistency tests passed."; exit 0
else echo "$FAILS docs test(s) FAILED."; exit 1; fi
