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

# The signal VOCABULARY, one list per decision group. Explicit, not derived from the script: a
# derived list silently shrinks when a signal is dropped, which is exactly how deleting --deploy,
# --compat or --observability survived v2.14.0's green suite. The drift guard below closes the other
# direction — a NEW signal cannot ship untested.
SIG_STANDARDISH="--ambiguous --external-interface --db-migration --deploy --deps --observability --compat"
SIG_DEEP="--research --arch-unresolved --multi-service-deploy --brownfield"
SIG_ESCALATION="--auth --authz --secrets --payments --privacy --public-api --high-stakes-data --major-deps --irreversible --high-stakes --destructive-migration"
SIG_VALUED="--novelty --components --phases --files"   # boundary-tested separately, below
SIG_CONTROL="--select --reason --subject"              # control flags, not classification signals

echo ""
echo "Medium complexity lifts to STANDARD — every standardish signal, alone"
for f in $SIG_STANDARDISH; do rec STANDARD "$f"; done

echo ""
echo "Escalation signals prevent TINY (STANDARD floor) — every one, alone"
for f in $SIG_ESCALATION; do
  out="$(bash "$CW" "$f" 2>/dev/null | grep '^Recommended mode:')"
  case "$out" in
    "Recommended mode: STANDARD"|"Recommended mode: DEEP") pass "$f prevents TINY ($out)";;
    *) fail "$f did not prevent TINY: $out";;
  esac
done

echo ""
echo "Deep signals reach DEEP — every one, alone"
for f in $SIG_DEEP; do rec DEEP "$f"; done
rec DEEP --destructive-migration --research   # escalation + deep

echo ""
echo "Numeric thresholds are pinned ON the boundary, in both directions"
# v2.14.0 tested --files at 9 (stays TINY) and never at 10, so raising the threshold to 100 survived.
# A threshold tested only on the passing side is not tested.
rec TINY     --files 9
rec STANDARD --files 10
rec TINY     --components 2
rec STANDARD --components 3
rec DEEP     --components 5
rec TINY     --phases 1
rec STANDARD --phases 2
rec DEEP     --phases 4
rec TINY     --novelty low
rec STANDARD --novelty medium
rec DEEP     --novelty high

echo ""
echo "Coverage drift guard — every signal classify-work accepts has an expectation above"
# Mirrors run-guard-tests.sh's TESTS[] drift guard: the failure it prevents is a signal added to the
# recommender that no test ever exercises, which is how 4 of 11 went unasserted.
KNOWN=" $SIG_STANDARDISH $SIG_DEEP $SIG_ESCALATION $SIG_VALUED $SIG_CONTROL "
UNCOVERED=""
for f in $(grep -oE '^[[:space:]]+--[a-z-]+\)' "$CW" | tr -d ' )' | sort -u); do
  case "$KNOWN" in *" $f "*) ;; *) UNCOVERED="$UNCOVERED $f" ;; esac
done
[ -z "$UNCOVERED" ] && pass "every signal flag classify-work accepts is covered by a tier expectation" \
                    || fail "classify-work accepts signals no test covers:$UNCOVERED — add an expectation, or list it as a control flag"

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
echo "An override with NO reason still warns (the other half of 'an override is recorded')"
# v2.14.0 tested override WITH a reason and the escalation-override warning, never the missing-reason
# case — so replacing that guardrail with `if false` survived. "You may override, but not invisibly"
# loses half its enforcement silently. Note what this does NOT prove: the warning goes to stderr and
# exits 0, and nothing checks the reason ever reached docs/SPEC.md. That half is human-dependent, and
# AUTHORING.md now says so rather than calling the whole row Deterministic.
ERR="$(bash "$CW" --subject x --select DEEP 2>&1 1>/dev/null)"
printf '%s\n' "$ERR" | grep -q "override with no --reason" \
  && pass "a reasonless override warns on stderr" \
  || fail "a reasonless override printed no warning (the guardrail is unenforced)"
bash "$CW" --subject x --select DEEP >/dev/null 2>&1 \
  && pass "a reasonless override still exits 0 (warns, never blocks)" \
  || fail "a reasonless override blocked (should warn, not block)"

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
echo "Regression (v2.15.0) — a value-taking flag with no value must fail, not spin"
# `shift 2` with one arg left is a POSIX no-op that RETURNS 1; without `set -e` the while loop never
# advances and burns a CPU forever (rc=137 under a watchdog). --reason/--subject had no validator to
# die on the empty value first, so they hung. A watchdog is mandatory: a hang test that hangs is useless.
watchdog() {  # watchdog <secs> <cmd...> ; echoes the rc, or 137 if it had to be killed
  local secs="$1"; shift
  ( "$@" >/dev/null 2>&1 & p=$!
    ( sleep "$secs" >/dev/null 2>&1; kill -9 $p 2>/dev/null ) & w=$!
    wait $p 2>/dev/null; rc=$?; kill $w 2>/dev/null; exit $rc ) 2>/dev/null
  echo $?
}
for flag in --reason --subject --components --phases --files --novelty --select; do
  rc=$(watchdog 5 bash "$CW" "$flag")
  case "$rc" in
    2)        pass "$flag with no value → exit 2 (fail-closed, no hang)" ;;
    137|124)  fail "$flag with no value HUNG (rc=$rc) — shift 2 no-op spin" ;;
    *)        fail "$flag with no value → rc=$rc (want 2)" ;;
  esac
done

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All classify-work.sh tests passed."; exit 0
else echo "$FAILS classify-work.sh test(s) FAILED."; exit 1; fi
