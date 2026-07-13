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
# skills/README.md is the authoritative catalog and README.md may restate the count; the other three
# docs deliberately carry NO count (v2.10.0 removed them — a count in five places is four places to
# forget). They are still scanned, so re-introducing one is a hard fail unless it happens to be right.
# Counts are written as digits OR as English number words — and the word form is the one that
# actually rotted ("Sixteen skills" sat in README.md through three releases because a digits-only
# regex never looked at it). Recognize both.
skill_count_of() {   # echo the numeric value of a count token; empty if it isn't one we know
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    [0-9]*)     printf '%s' "$1" ;;
    ten)        echo 10 ;; eleven)   echo 11 ;; twelve)    echo 12 ;; thirteen) echo 13 ;;
    fourteen)   echo 14 ;; fifteen)  echo 15 ;; sixteen)   echo 16 ;; seventeen) echo 17 ;;
    eighteen)   echo 18 ;; nineteen) echo 19 ;; twenty)    echo 20 ;; twenty-one) echo 21 ;;
    *)          printf '' ;;
  esac
}
BAD_COUNTS=""
for doc in "$ROOT/README.md" "$ROOT/skills/README.md" \
           "$ROOT/CONTRIBUTING.md" "$SCAFFOLD/toolkit-docs/GUIDE.md" "$SCAFFOLD/SCAFFOLD.md"; do
  [ -f "$doc" ] || continue
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    n="$(skill_count_of "$tok")"
    [ -n "$n" ] || continue                    # not a count token we recognize — nothing to check
    [ "$n" = "$TOTAL" ] || [ "$n" = "$PORTABLE" ] || BAD_COUNTS="$BAD_COUNTS ${doc##*/}:'$tok'"
  done < <(grep -oiE '([0-9]+|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|twenty-one) (portable |per-project )?skills' "$doc" 2>/dev/null \
             | awk '{print $1}')
done
if [ -z "$BAD_COUNTS" ]; then
  pass "every '<N> skills' mention (README, skills/README, CONTRIBUTING, GUIDE, SCAFFOLD) equals $TOTAL (total) or $PORTABLE (per-project)"
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
  | grep -vE '^\.claude/\.' \
  | grep -vxF '.claude/test-command')              # runtime state, out of scope: .claude/.phase-base etc. (dotfiles) plus the
                                                   # non-dotfile graded-command file sync.sh seeds from config (D1) — never in repo/scaffold
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
