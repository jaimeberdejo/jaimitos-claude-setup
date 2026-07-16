#!/usr/bin/env bash
# lint-enforcement.sh — deterministic STRUCTURE check for the optional enforcement ledger,
# docs/ENFORCEMENT.md. The ledger maps each material architectural/operational CLAIM to the mechanism
# that actually enforces it (or marks it explicitly advisory), so "the docs say a rule exists but nothing
# checks it" can't hide. Inert when there is no ledger (exit 0). Advisory by default; --strict fails.
#
# It checks STRUCTURE only — never whether the named mechanism truly enforces the claim (that is a human
# + evaluator judgement). The ledger is NOT a roadmap, does NOT tick anything, and does NOT grant
# permission; it must be updated additively and never regenerated from the current code graph (that would
# bless drift). This script only reads it.
#
# Canonical format (one table; header line then rows):
#   # Enforcement Ledger
#   Baseline commit: <sha>
#   Last reviewed: <date>
#
#   | ID | Claim | Source | Enforcement | Strength | Status | Trigger |
#   |---|---|---|---|---|---|---|
#   | ENF-001 | UI must not touch persistence | ADR-004 | dependency test | DETERMINISTIC | ACTIVE | every CI run |
#   | ENF-004 | Legacy adapter removed after migration | SPEC REQ-018 | deferred trigger | DEFERRED | DEFERRED | PHASE-08 completes |
#
# Strength ∈ { DETERMINISTIC, HOOK-ENFORCED, CI-ENFORCED, MODEL-DEPENDENT, HUMAN-DEPENDENT, ADVISORY,
#   DEFERRED } (short forms HOOK/CI/MODEL/HUMAN/STRUCTURAL and " + "-joined combinations are accepted).
# A DEFERRED row MUST carry a concrete Trigger (a real phase / event / repository condition), never blank.
#
# Usage: bash scripts/lint-enforcement.sh [--strict] [path-to-ledger]
set -uo pipefail
STRICT=0; FILE="docs/ENFORCEMENT.md"
for a in "$@"; do case "$a" in
  -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --strict) STRICT=1 ;;
  *) FILE="$a" ;;
esac; done
[ -f "$FILE" ] || { echo "lint-enforcement: no $FILE — nothing to lint."; exit 0; }

OUT=$(awk '
  function trim(s){ gsub(/^[[:space:]]+/,"",s); gsub(/[[:space:]]+$/,"",s); return s }
  function bad(m){ printf "  ! %s\n", m; miss++ }
  function warn(m){ printf "  ~ %s\n", m; warns++ }
  BEGIN{ miss=0; warns=0; intable=0; header=0; rows=0
         # allowed strength tokens (a Strength cell is one or more of these joined by " + ")
         split("DETERMINISTIC HOOK-ENFORCED CI-ENFORCED MODEL-DEPENDENT HUMAN-DEPENDENT ADVISORY DEFERRED HOOK CI MODEL HUMAN STRUCTURAL", tk, " ")
         for (i in tk) allow[tk[i]]=1 }
  /[Bb]aseline commit:/ { basel=1 }
  /[Ll]ast reviewed:/   { reviewed=1 }
  /^[[:space:]]*\|/ {
    line=$0
    if (!header && line ~ /ID/ && line ~ /Claim/ && line ~ /Strength/) { header=1; intable=1; next }
    # Separator row = a row built ONLY from pipes/dashes/colons/space. Anchored at BOTH ends: an
    # unanchored match (e.g. /\|[[:space:]]*-{2,}/) also matches a DATA row whose cell merely starts
    # with "--" (a CLI flag in a Claim), silently skipping it — the row is then never counted, so an
    # all-skipped ledger reports "no rows" + structure OK + exit 0 under --strict. Fail-open.
    if (intable && line ~ /^[[:space:]]*\|[|:[:space:]-]*$/) { next }
    if (!intable) next
    n=split(line, a, "|")
    id=trim(a[2]); claim=trim(a[3]); src=trim(a[4]); enf=trim(a[5]); str=trim(a[6]); status=trim(a[7]); trig=trim(a[8])
    if (id=="" && claim=="" && src=="") next   # blank/decorative row
    rows++
    if (id !~ /^ENF-[0-9][0-9][0-9]$/) bad("malformed or missing ledger id: \"" id "\" (want ENF-###)")
    else { if (id in seen) bad("duplicate ledger id: " id); seen[id]=1 }
    if (claim=="") bad(id ": empty Claim")
    if (src=="")   bad(id ": empty Source (a claim with no source is unverifiable)")
    if (enf=="")   bad(id ": empty Enforcement (map it to a mechanism or mark it ADVISORY)")
    # strength vocabulary: each " + "-joined part must be an allowed token
    if (str=="") bad(id ": empty Strength")
    else {
      m=split(str, parts, /[[:space:]]*\+[[:space:]]*/)
      for (j=1;j<=m;j++){ p=trim(parts[j]); if (!(p in allow)) bad(id ": unknown Strength token \"" p "\"") }
    }
    # deferred rows need a concrete trigger
    deferred = (status ~ /DEFERRED/ || str ~ /DEFERRED/)
    if (deferred) {
      if (trig=="" || trig=="-" || toupper(trig)=="TBD" || toupper(trig)=="NONE")
        bad(id ": DEFERRED but no concrete Trigger (a deferred claim must name a real phase/event/condition)")
    }
    # advisory honesty: a row cannot claim DETERMINISTIC strength while calling its own enforcement advisory
    if (str ~ /DETERMINISTIC/ && enf ~ /[Aa]dvisory/) bad(id ": Strength DETERMINISTIC but Enforcement says advisory")
    next
  }
  # Table ends at a non-blank line that is not a table row. Matched on "not a table row" rather than
  # /^[^|]/: an INDENTED table row starts with a space, so /^[^|]/ matched it and closed the table
  # after the first row — every later row then fell out at "if (!intable) next", unvalidated. The
  # `next` above keeps a data row from reaching this rule at all; this anchor is the second lock.
  !/^[[:space:]]*\|/ && intable && header && $0 !~ /^[[:space:]]*$/ { intable=0 }
  END{
    if (!header) bad("no ledger table found (need a | ID | Claim | ... | Strength | ... | header row)")
    if (header && rows==0) warn("ledger has a header but no rows")
    if (!basel)    warn("no \"Baseline commit:\" line (staleness cannot be judged without it)")
    if (!reviewed) warn("no \"Last reviewed:\" line")
    exit (miss>0 ? 1 : 0)
  }
' "$FILE")
rc=$?

if [ -n "$OUT" ]; then printf '%s\n' "$OUT"; fi
if [ "$rc" -eq 0 ]; then
  echo "lint-enforcement: ledger structure OK."
  exit 0
fi
if [ "$STRICT" -eq 1 ]; then echo "lint-enforcement: structural problems (--strict)."; exit 1; fi
echo "lint-enforcement: problems above (advisory; pass --strict to fail)."
exit 0
