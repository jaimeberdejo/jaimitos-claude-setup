#!/usr/bin/env bash
# check-uat.sh — validate the optional, lightweight user-acceptance ledger (docs/UAT.md) and report
# whether any BLOCKING item would block a release. There is ONE canonical UAT artifact; it is tier-
# dependent (TINY omits it; STANDARD uses it when human acceptance differs from automated tests;
# DEEP / high-stakes use it when human acceptance is relevant). UAT may block a release, but it NEVER
# bypasses the evaluator, the evidence gate, or scripts/tick.sh — it is an additional human gate, not a
# replacement for any of them. Inert when there is no ledger (exit 0). Advisory by default; --strict fails
# when a blocking item is FAILED/BLOCKED, or a DEFERRED item lacks its justification.
#
# Canonical entry format (one block per acceptance item):
#   Baseline commit: <sha>
#   Environment: <where it was exercised>
#
#   - UAT-001
#     Requirement: AC-004
#     Status: PASSED           (NOT_TESTED | PASSED | FAILED | BLOCKED | DEFERRED)
#     Expected: ...
#     Actual: ...
#     Evidence: ...
#     Blocking: YES            (YES | NO)
#   - UAT-002
#     Requirement: AC-006
#     Status: DEFERRED
#     Reason: ...              (a DEFERRED item MUST record Reason + Risk + Resolution + release impact)
#     Risk: ...
#     Resolution: ...
#     Blocking: NO
#
# Usage: bash scripts/check-uat.sh [--strict] [path-to-uat]
set -uo pipefail
STRICT=0; FILE="docs/UAT.md"
for a in "$@"; do case "$a" in
  -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --strict) STRICT=1 ;;
  *) FILE="$a" ;;
esac; done
[ -f "$FILE" ] || { echo "check-uat: no $FILE — nothing to check."; exit 0; }

OUT=$(awk '
  function trim(s){ gsub(/^[[:space:]]+/,"",s); gsub(/[[:space:]]+$/,"",s); return s }
  function bad(m){ printf "  ! %s\n", m; miss++ }
  function warn(m){ printf "  ~ %s\n", m; warns++ }
  function flush(   ok) {
    if (cur=="") return
    if (status=="") bad(cur ": no Status")
    else if (status !~ /^(NOT_TESTED|PASSED|FAILED|BLOCKED|DEFERRED)$/) bad(cur ": invalid Status \"" status "\"")
    if (blocking!="" && blocking !~ /^(YES|NO)$/) bad(cur ": invalid Blocking \"" blocking "\" (YES|NO)")
    # a DEFERRED item must be justified
    if (status=="DEFERRED" && !(has_reason && has_risk && has_resolution))
      bad(cur ": DEFERRED but missing justification (needs Reason + Risk + Resolution)")
    # a BLOCKING item that is FAILED or BLOCKED blocks the release
    if (blocking=="YES" && (status=="FAILED" || status=="BLOCKED"))
      bad(cur ": Blocking=YES and Status=" status " — this blocks the release")
    cur=""; status=""; blocking=""; has_reason=0; has_risk=0; has_resolution=0
  }
  /[Bb]aseline commit:/ { basel=1 }
  /^[[:space:]]*-[[:space:]]*UAT/ {
    flush()
    id=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",id); n=split(id, ta, /[[:space:]]/); id=ta[1]
    if (id !~ /^UAT-[0-9]+$/) bad("malformed UAT id: \"" id "\" (want UAT-###)")
    else { if (id in seen) bad("duplicate UAT id: " id); seen[id]=1 }
    cur=id; nitems++; next
  }
  cur!="" && /^[[:space:]]*Status:/       { s=$0; sub(/^[[:space:]]*Status:[[:space:]]*/,"",s); status=trim(s); next }
  cur!="" && /^[[:space:]]*Blocking:/     { s=$0; sub(/^[[:space:]]*Blocking:[[:space:]]*/,"",s); blocking=toupper(trim(s)); next }
  cur!="" && /^[[:space:]]*Reason:/       { has_reason=1; next }
  cur!="" && /^[[:space:]]*Risk:/         { has_risk=1; next }
  cur!="" && /^[[:space:]]*Resolution:/   { has_resolution=1; next }
  END {
    flush()
    if (nitems==0) warn("UAT ledger has no UAT-### items")
    if (!basel)    warn("no \"Baseline commit:\" line (UAT results are not bound to a commit)")
    exit (miss>0 ? 1 : 0)
  }
' "$FILE")
rc=$?

[ -n "$OUT" ] && printf '%s\n' "$OUT"
if [ "$rc" -eq 0 ]; then
  echo "check-uat: no blocking acceptance failures."
  exit 0
fi
if [ "$STRICT" -eq 1 ]; then echo "check-uat: blocking acceptance failures (--strict) — release is blocked."; exit 1; fi
echo "check-uat: problems above (advisory; pass --strict to block a release)."
exit 0
