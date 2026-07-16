#!/usr/bin/env bash
# test-evidence-schema.sh — the v2.14.0 evidence schema (schema_version 2) produced by test-evidence.sh.
# Proves: a green run emits schema_version 2 with the v1 fields intact (so tick.sh still reads it) plus
# evidence_id / requirement refs / classification / timestamps; content_hash is genuinely recomputable
# (an edited field breaks it); a red run records passed:false (a summary can NEVER override the exit
# status); a secret in the output is redacted out of the bounded summary; and a no-tests run stays v2.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID="$SCAFFOLD/scripts/test-evidence.sh"
TC="$SCAFFOLD/.claude/lib/_test-cmd.sh"
for f in "$EVID" "$TC"; do [ -f "$f" ] || { echo "test: missing $f" >&2; exit 1; }; done
command -v jq >/dev/null 2>&1 || { echo "test: jq required"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
hashof() { { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | cut -d' ' -f1; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-evsch)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
REPO=""; HEAD=""; ev=""
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO/.claude/lib" "$REPO/scripts"
  cp "$EVID" "$REPO/scripts/test-evidence.sh"; cp "$TC" "$REPO/.claude/lib/_test-cmd.sh"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && printf '.claude/.tick-evidence.json\n' > .gitignore && echo x > f && git add -A && git commit -qm base ) >/dev/null 2>&1
  HEAD=$(git -C "$REPO" rev-parse HEAD); ev="$REPO/.claude/.tick-evidence.json"
}

echo "evidence schema v2 tests"; echo ""

echo "A green run emits schema_version 2 with v1 fields intact + the new fields"
mkrepo green
( cd "$REPO" && LEAN_TEST_CMD=true EVIDENCE_ID=EVIDENCE-1.1 LEAN_EVIDENCE_REQUIREMENTS="REQ-001, AC-002" bash scripts/test-evidence.sh >/dev/null 2>&1 )
[ "$(jq -r .schema_version "$ev")" = 2 ]        && pass "schema_version is 2"                        || fail "schema_version wrong: $(jq -r .schema_version "$ev")"
[ "$(jq -r .passed "$ev")" = true ]             && pass "passed:true (v1 field kept)"                || fail "passed wrong"
[ "$(jq -r .run_id "$ev")" = "$HEAD" ]          && pass "run_id == HEAD (v1 field kept)"             || fail "run_id wrong"
[ "$(jq -r .evidence_id "$ev")" = "EVIDENCE-1.1" ] && pass "evidence_id from env"                    || fail "evidence_id wrong"
[ "$(jq -r '.requirements | join(",")' "$ev")" = "REQ-001,AC-002" ] && pass "requirement refs recorded" || fail "requirements wrong: $(jq -c .requirements "$ev")"
[ "$(jq -r .classification "$ev")" = deterministic ] && pass "classification deterministic"          || fail "classification wrong"
[ "$(jq -r '.started_at != null and .finished_at != null' "$ev")" = true ] && pass "timestamps present" || fail "timestamps missing"

echo ""
echo "content_hash is recomputable, and an edited field breaks it (tamper-evident)"
STORED=$(jq -r .content_hash "$ev")
RECOMP=$(jq -cS 'del(.content_hash)' "$ev" | hashof)
[ "$STORED" = "$RECOMP" ] && pass "content_hash recomputes from the canonical object" || fail "hash not recomputable (stored=$STORED recomp=$RECOMP)"
TAMPER=$(jq -c '.passed=false' "$ev" | jq -cS 'del(.content_hash)' | hashof)
[ "$STORED" != "$TAMPER" ] && pass "flipping .passed changes the recomputed hash (edit detectable)" || fail "hash did not change on tamper"

echo ""
echo "A red run records passed:false — a summary can never override the real exit status"
mkrepo red
( cd "$REPO" && TEST_EVIDENCE_RETRIES=0 LEAN_TEST_CMD='sh -c "echo the-suite-says-everything-is-fine; exit 1"' bash scripts/test-evidence.sh >/dev/null 2>&1 ); erc=$?
[ "$erc" = 1 ]                          && pass "red suite → exit 1"                         || fail "red exit wrong: $erc"
[ "$(jq -r .passed "$ev")" = false ]   && pass "passed:false despite a reassuring summary"  || fail "red passed wrong: $(jq -r .passed "$ev")"
[ "$(jq -r .schema_version "$ev")" = 2 ] && pass "red evidence is still schema 2"           || fail "red schema wrong"

echo ""
echo "A secret in the output is redacted out of the bounded summary"
mkrepo secret
( cd "$REPO" && LEAN_TEST_CMD='printf "run complete AKIAIOSFODNN7EXAMPLEabcdefghijklmnop1234567\n"' bash scripts/test-evidence.sh >/dev/null 2>&1 )
[ "$(jq -r .redacted "$ev")" = true ] && pass "redacted:true when a secret-shaped token appears" || fail "redacted flag wrong"
SUM=$(jq -r .summary "$ev")
printf '%s' "$SUM" | grep -q "REDACTED"   && pass "summary shows ***REDACTED***"        || fail "summary not redacted: $SUM"
printf '%s' "$SUM" | grep -q "AKIAIOSF"   && fail "the secret leaked into the summary"  || pass "the raw secret is absent from the summary"

echo ""
echo "A no-tests run stays schema 2 with passed:null"
mkrepo notests
( cd "$REPO" && bash scripts/test-evidence.sh --allow-no-tests >/dev/null 2>&1 ); erc=$?
{ [ "$erc" = 0 ] && [ "$(jq -r .passed "$ev")" = null ] && [ "$(jq -r .schema_version "$ev")" = 2 ]; } \
  && pass "no-tests → exit 0, passed:null, schema 2" || fail "no-tests case wrong (rc=$erc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All evidence-schema tests passed."; exit 0
else echo "$FAILS evidence-schema test(s) FAILED."; exit 1; fi
