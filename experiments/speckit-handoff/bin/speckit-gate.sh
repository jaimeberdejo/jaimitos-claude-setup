#!/usr/bin/env bash
# speckit-gate.sh — THE deterministic, fail-closed gate for a Spec Kit → Jaimitos handoff.
#
# It validates a feature PACK, and optionally a roadmap FRAGMENT against a PROJECT. It never edits
# docs/ROADMAP.md — it has no code path that writes one. speckit-propose.sh renders the default
# fragment; a model may render a better one; BOTH go through this same gate. One gate, many callers
# — the pattern scripts/tick.sh established.
#
# Exit codes mirror scripts/tick.sh on purpose:
#   0  importable
#   1  REFUSED — a hard gate failed. Nothing written. The caller stops.
#   2  usage error (unknown flag, missing --pack). -h/--help is 0.
#   3  HIGH-STAKES — known high-stakes PATHS are in the pack. A fragment may still be produced, but
#      every phase is forced to Mode: supervised and THE CALLER MUST NOT AUTO-APPLY IT.
#
# What this gate does NOT do, and never claims to (see the README's Guarantee|Enforcement table):
#   - judge whether a success criterion is genuinely MEASURABLE (heuristic; warns, never refuses)
#   - judge whether a feature CONTRADICTS docs/SPEC.md (semantic; surfaced for a human)
#   - classify high-stakes INTENT that has no path yet (it matches paths, not intentions)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
. "$HERE/_speckit-lib.sh"

usage() {
  cat <<'EOF'
usage: speckit-gate.sh --pack <dir> --feature <NNN-slug> [--project <dir>] [--fragment <file>]

  --pack     <dir>        a Spec Kit project root (the one containing specs/)
  --feature  <NNN-slug>   the feature directory under specs/
  --project  <dir>        a Jaimitos project (needs docs/ROADMAP.md). Default: cwd
  --fragment <file>       a roadmap fragment to validate against the project

exit: 0 importable · 1 refused · 2 usage · 3 high-stakes (supervised; do NOT auto-apply)
EOF
}

PACK=""; FEATURE=""; PROJECT="."; FRAGMENT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pack)     PACK="${2:-}";     shift 2 || exit 2 ;;
    --feature)  FEATURE="${2:-}";  shift 2 || exit 2 ;;
    --project)  PROJECT="${2:-}";  shift 2 || exit 2 ;;
    --fragment) FRAGMENT="${2:-}"; shift 2 || exit 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "speckit-gate: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
[ -n "$PACK" ] && [ -n "$FEATURE" ] || { echo "speckit-gate: --pack and --feature are required (try --help)" >&2; usage >&2; exit 2; }

refuse() { echo "speckit-gate: REFUSED — $1" >&2; exit 1; }

ROADMAP="$PROJECT/docs/ROADMAP.md"

# ---- G1 — pack shape -------------------------------------------------------------------------
FDIR=$(sk_feature_dir "$PACK" "$FEATURE") || refuse "no feature directory: $PACK/specs/$FEATURE"
for f in spec.md plan.md tasks.md; do
  [ -f "$FDIR/$f" ] || refuse "the feature pack is incomplete — $FEATURE/$f is missing. Run the Spec Kit command that produces it before handing off."
done

# ---- G2 — unresolved clarification -----------------------------------------------------------
CLAR=$(sk_clarifications "$FDIR")
if [ -n "$CLAR" ]; then
  echo "speckit-gate: the feature pack still has unresolved clarifications:" >&2
  printf '%s\n' "$CLAR" | sed 's/^/  /' >&2
  refuse "run /speckit-clarify and resolve every [NEEDS CLARIFICATION] before handing off. An ambiguity imported into the roadmap becomes an ambiguity a builder guesses at."
fi

# ---- G3a — success-criterion STRUCTURE (a hard gate) -----------------------------------------
SC_IDS=$(sk_ids "$FDIR/spec.md" SC)
[ -n "$SC_IDS" ] || refuse "spec.md declares no success criteria (**SC-###**). Without a measurable outcome there is nothing for a 'Done when:' to point at."
SC_DUPES=$(sk_dupe_ids "$FDIR/spec.md" SC)
[ -z "$SC_DUPES" ] || refuse "duplicate success-criterion id(s): $(echo "$SC_DUPES" | tr '\n' ' ')— an id must identify exactly one criterion, or traceability is meaningless."

# ---- G6 — functional-requirement ids ---------------------------------------------------------
FR_IDS=$(sk_ids "$FDIR/spec.md" FR)
[ -n "$FR_IDS" ] || refuse "spec.md declares no functional requirements (**FR-###**)."
FR_DUPES=$(sk_dupe_ids "$FDIR/spec.md" FR)
[ -z "$FR_DUPES" ] || refuse "duplicate functional-requirement id(s): $(echo "$FR_DUPES" | tr '\n' ' ')"

# ---- G3b — measurability (a WARNING; see the header) -----------------------------------------
UNMEASURED=""
for id in $SC_IDS; do
  txt=$(sk_req_text "$FDIR/spec.md" "$id")
  sk_measurable "$txt" || UNMEASURED="$UNMEASURED $id"
done

# ---- tasks -----------------------------------------------------------------------------------
TASKS=$(sk_tasks "$FDIR/tasks.md")
[ -n "$TASKS" ] || refuse "tasks.md has no tasks. Run /speckit-tasks before handing off."

# ---- G9 — KNOWN high-stakes PATHS (via the REAL _high-stakes.sh) ------------------------------
# We do not re-implement path classification. We source the library that ships and gates tick.sh,
# from inside the project (its allowlist path is relative), so the classification here is the same
# classification the completion gate will apply later.
HS_HITS=""; HS_RC=1
HS_LIB="$PROJECT/.claude/lib/_high-stakes.sh"
[ -f "$HS_LIB" ] || HS_LIB="$(cd "$HERE/../../.." 2>/dev/null && pwd)/jaimitos-os/.claude/lib/_high-stakes.sh"
if [ -f "$HS_LIB" ]; then
  PATHS=$(sk_paths "$FDIR")
  HS_HITS=$( cd "$PROJECT" 2>/dev/null || exit 1
             # shellcheck disable=SC1090
             . "$HS_LIB" 2>/dev/null || exit 1
             high_stakes_match "$PATHS" )
  HS_RC=$?
  # rc 2 is a CONFIGURATION ERROR (the regex does not compile). Never treat it as "clean".
  [ "$HS_RC" = 2 ] && refuse "the high-stakes regex does not compile — fail-closed. Fix .claude/lib/_high-stakes.sh."
else
  refuse "cannot find .claude/lib/_high-stakes.sh — refusing to classify high-stakes work without the library that actually gates it (fail-closed)."
fi

# ---- fragment gates (only when a fragment is supplied) ----------------------------------------
if [ -n "$FRAGMENT" ]; then
  [ -f "$FRAGMENT" ] || refuse "no such fragment: $FRAGMENT"
  [ -f "$ROADMAP" ]  || refuse "no docs/ROADMAP.md in $PROJECT — nothing to append to."

  # G7 — a fragment may not forge an open task out of prose. Core (v2.11.2) no longer miscounts a
  # line that merely CONTAINS "- [ ]", but generated text should not produce one at all: it would
  # read as a task to a human and as prose to the parser. Defense in depth, not the fix.
  POISON=$(grep -n -- '- \[' "$FRAGMENT" 2>/dev/null | grep -vE ':- \[ \] ' || true)
  if [ -n "$POISON" ]; then
    echo "speckit-gate: fragment line(s) contain the task notation without being a task:" >&2
    printf '%s\n' "$POISON" | sed 's/^/  /' >&2
    refuse "a generated line that merely mentions '- [ ]' reads as a task to a human. Rewrite it."
  fi

  # G5 — the same WORK must not be imported twice, whatever it is numbered. An exact-heading check
  # is not enough: "## Phase 3 — Browse the Widget Catalogue" is the already-COMPLETED
  # "## Phase 1 — Browse the widget catalogue" under a new number.
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    if grep -qxF -- "$h" "$ROADMAP" 2>/dev/null; then
      refuse "the roadmap already has this exact phase heading: $h"
    fi
    existing=$(sk_matching_phase "$ROADMAP" "$h") && {
      open=$(PH="$existing" awk '
        $0==ENVIRON["PH"] {inphase=1; next}
        /^## / && inphase {inphase=0}
        inphase && /^[[:space:]]*- \[ \] / {c++}
        END {print c+0}' "$ROADMAP")
      state="still open"; [ "$open" = 0 ] && state="already COMPLETE"
      echo "speckit-gate: this feature is already on the roadmap ($state):" >&2
      echo "  proposed: $h" >&2
      echo "  existing: $existing" >&2
      refuse "importing it again would duplicate work the roadmap already owns. Completed history is not re-importable."
    }
  done < <(grep '^## Phase' "$FRAGMENT")

  # G4 — append-only, structurally. The output is a FRAGMENT, so the current roadmap must be an
  # exact byte PREFIX of the merged result. There is no code path here that rewrites an existing
  # block — not because we check for it, but because we never emit a whole roadmap.
  MERGED=$(mktemp 2>/dev/null || echo "/tmp/sk-merged.$$")
  cat "$ROADMAP" "$FRAGMENT" > "$MERGED"
  SZ=$(wc -c < "$ROADMAP" | tr -d ' ')
  head -c "$SZ" "$MERGED" | cmp -s - "$ROADMAP" || { rm -f "$MERGED"; refuse "the merge is not append-only — refusing (this should be impossible; the fragment is malformed)."; }

  # G8 — schema, judged by the UNMODIFIED core linter. Not our copy of its rules: the linter itself.
  LINT="$PROJECT/scripts/lint-roadmap.sh"
  [ -f "$LINT" ] || LINT="$(cd "$HERE/../../.." 2>/dev/null && pwd)/jaimitos-os/scripts/lint-roadmap.sh"
  if [ -f "$LINT" ]; then
    if ! bash "$LINT" --strict "$MERGED" >/dev/null 2>&1; then
      echo "speckit-gate: the merged roadmap fails the core linter:" >&2
      bash "$LINT" --strict "$MERGED" 2>&1 | sed 's/^/  /' >&2
      rm -f "$MERGED"
      refuse "the fragment is not roadmap-schema-valid."
    fi
  else
    rm -f "$MERGED"
    refuse "cannot find scripts/lint-roadmap.sh — refusing to claim schema validity without the linter that defines it (fail-closed)."
  fi
  rm -f "$MERGED"
fi

# ---- verdict ---------------------------------------------------------------------------------
# Warnings go to stderr so a caller can still consume a clean stdout.
[ -n "$UNMEASURED" ] && {
  sk_warn "success criteria with no numeric/comparator signal:$UNMEASURED"
  sk_warn "  a human must confirm each is measurable. This check is a heuristic — 'the operation is"
  sk_warn "  idempotent' is measurable and has no digit in it. It warns; it never refuses."
}
if [ "$HS_RC" = 0 ]; then
  echo "speckit-gate: HIGH-STAKES paths in this feature:" >&2
  printf '%s\n' "$HS_HITS" | sed 's/^/  /' >&2
  echo "speckit-gate: every proposed phase must be Mode: supervised, and a human must approve the import." >&2
  exit 3
fi
exit 0
