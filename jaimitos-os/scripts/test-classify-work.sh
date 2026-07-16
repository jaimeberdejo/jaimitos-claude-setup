#!/usr/bin/env bash
# test-classify-work.sh — behavioral tests for scripts/classify-work.sh, the tier recommender.
# Proves: small local work stays TINY; escalation signals prevent TINY; deep signals reach DEEP;
# an override is recorded and warned; skipped ceremony is explicit; the recommendation is
# reproducible; and a typo/bad value fails closed (exit 2) instead of silently misclassifying.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CW="$SCAFFOLD/scripts/classify-work.sh"
[ -f "$CW" ] || { echo "test: cannot find classify-work.sh at $CW" >&2; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

# rec <expected> <flags...> — assert the Recommended mode line
rec() {
  local want="$1"; shift
  local out; out="$(bash "$CW" "$@" 2>/dev/null)"
  if printf '%s\n' "$out" | grep -qxF "Recommended mode: $want"; then
    pass "recommends $want for: $*"
  else
    fail "expected $want for '$*', got: $(printf '%s\n' "$out" | grep '^Recommended mode:')"
  fi
}

echo "classify-work.sh tests"; echo ""

echo "Small/local work stays TINY (no escalation, no complexity signals)"
rec TINY --subject "fix a typo"
rec TINY --components 1 --files 2
rec TINY --components 2 --files 9 --novelty low

echo ""
echo "Medium complexity lifts to STANDARD"
rec STANDARD --components 3
rec STANDARD --external-interface
rec STANDARD --db-migration
rec STANDARD --deps
rec STANDARD --novelty medium
rec STANDARD --phases 2
rec STANDARD --ambiguous

echo ""
echo "Escalation signals prevent TINY (STANDARD floor)"
for f in --auth --authz --secrets --payments --privacy --public-api --high-stakes-data --major-deps --irreversible --high-stakes; do
  out="$(bash "$CW" "$f" 2>/dev/null | grep '^Recommended mode:')"
  case "$out" in
    "Recommended mode: STANDARD"|"Recommended mode: DEEP") pass "$f prevents TINY ($out)";;
    *) fail "$f did not prevent TINY: $out";;
  esac
done

echo ""
echo "Deep signals reach DEEP"
rec DEEP --research
rec DEEP --arch-unresolved
rec DEEP --novelty high
rec DEEP --multi-service-deploy
rec DEEP --components 5
rec DEEP --phases 4
rec DEEP --brownfield
rec DEEP --destructive-migration --research   # escalation + deep

echo ""
echo "Selection defaults to the recommendation; override is recorded"
OUT="$(bash "$CW" --auth 2>/dev/null)"
printf '%s\n' "$OUT" | grep -qxF "Selected mode: STANDARD" && pass "selected defaults to recommendation" || fail "selected did not default"
printf '%s\n' "$OUT" | grep -qxF "User override: NO"       && pass "no override by default"              || fail "override wrongly YES"

OUT="$(bash "$CW" --subject x --select DEEP --reason 'operator wants full depth' 2>/dev/null)"
printf '%s\n' "$OUT" | grep -qxF "Selected mode: DEEP"                        && pass "explicit selection honored"   || fail "selection not honored"
printf '%s\n' "$OUT" | grep -q  "User override: YES — operator wants full depth" && pass "override + reason recorded" || fail "override reason not recorded"

echo ""
echo "Skipped ceremony is explicit per tier"
bash "$CW" --subject x 2>/dev/null | grep -q "no PLAN_CHECK unless" && pass "TINY names the ceremony it skips" || fail "TINY skipped-ceremony not explicit"
bash "$CW" --research 2>/dev/null | grep -q "nothing skipped by tier" && pass "DEEP skips nothing by tier" || fail "DEEP skipped-ceremony wrong"

echo ""
echo "Overriding TINY past an escalation signal warns loudly (stderr) but does not block"
ERR="$(bash "$CW" --auth --select TINY 2>&1 1>/dev/null)"
printf '%s\n' "$ERR" | grep -q "TINY selected despite an escalation signal" && pass "escalation-override warning printed" || fail "no escalation-override warning"
bash "$CW" --auth --select TINY >/dev/null 2>&1 && pass "override still exits 0 (human may override)" || fail "override blocked (should warn, not block)"

echo ""
echo "Recommendation is reproducible (same flags → identical output)"
A="$(bash "$CW" --components 3 --external-interface --novelty medium 2>/dev/null)"
B="$(bash "$CW" --components 3 --external-interface --novelty medium 2>/dev/null)"
[ "$A" = "$B" ] && pass "identical flags produce identical output" || fail "output not reproducible"

echo ""
echo "Bad input fails closed (exit 2), never a silent misclassification"
bash "$CW" --bogus >/dev/null 2>&1 && fail "unknown flag exited 0" || { [ "$?" -eq 2 ] && pass "unknown flag exits 2" || fail "unknown flag wrong exit code"; }
bash "$CW" --novelty huge >/dev/null 2>&1 && fail "bad --novelty exited 0" || pass "bad --novelty value refused"
bash "$CW" --components ten >/dev/null 2>&1 && fail "non-integer --components exited 0" || pass "non-integer --components refused"
bash "$CW" --select MEGA >/dev/null 2>&1 && fail "bad --select exited 0" || pass "bad --select value refused"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All classify-work.sh tests passed."; exit 0
else echo "$FAILS classify-work.sh test(s) FAILED."; exit 1; fi
