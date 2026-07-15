#!/usr/bin/env bash
# speckit-converge.sh — REPORT-ONLY convergence between a Spec Kit feature pack and the Jaimitos
# roadmap that imported it. It reads; it writes ONE report under --out; it changes nothing else.
#
# "Report-only" means NO STATE MUTATION. It does NOT mean "every run succeeds" — the first draft of
# the plan had it exit 0 always, which makes it useless in a pipeline. The exit code is the finding:
#
#   0  no blocking convergence gaps
#   1  gaps or drift found (a requirement unbuilt, or an id the spec no longer has)
#   2  usage / malformed input
#   3  a stale/frozen conflict a human must resolve (spec text moved under a COMPLETED phase)
#
# --informational forces exit 0 (a caller that wants the report without a failing status).
#
# What structurally stops it ticking: it cannot write .claude/.phase-grade (only record-grade.sh
# does, from a real evaluator PASS) or .claude/.tick-evidence.json bound to HEAD (only
# test-evidence.sh does). Without both, scripts/tick.sh refuses. And it does NOT append to the
# pack's tasks.md — the upstream /speckit-converge behaviour we deliberately rejected.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
. "$HERE/_speckit-lib.sh"

# The SHARED core parser (v2.11.2). roadmap_open_count is how we tell a completed phase from an open
# one, and it must be the SAME definition tick.sh uses — a phase is "complete" here exactly when it
# is complete to the gate. Sourced after arg-parsing, once we know the project. Prefer the project's
# copy; fall back to the toolkit's.
find_roadmap_lib() {
  local proj="$1" p
  for p in "$proj/.claude/lib/_roadmap.sh" \
           "$(cd "$HERE/../../.." 2>/dev/null && pwd)/jaimitos-os/.claude/lib/_roadmap.sh"; do
    [ -f "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

usage() {
  cat <<'EOF'
usage: speckit-converge.sh --pack <dir> --feature <NNN-slug> --project <dir> [--out <dir>] [--informational]

  Reports coverage, drift, and frozen conflicts between a Spec Kit feature pack and the Jaimitos
  roadmap that imported it. Writes ONE report to <out>/CONVERGENCE.md and mutates nothing else.

exit: 0 clean · 1 gaps/drift · 2 usage · 3 frozen conflict (human review) · (--informational forces 0)
EOF
}

PACK=""; FEATURE=""; PROJECT=""; OUT=""; INFORMATIONAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pack)          PACK="${2:-}";    shift 2 || exit 2 ;;
    --feature)       FEATURE="${2:-}"; shift 2 || exit 2 ;;
    --project)       PROJECT="${2:-}"; shift 2 || exit 2 ;;
    --out)           OUT="${2:-}";     shift 2 || exit 2 ;;
    --informational) INFORMATIONAL=1;  shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "speckit-converge: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
[ -n "$PACK" ] && [ -n "$FEATURE" ] && [ -n "$PROJECT" ] || { echo "speckit-converge: --pack, --feature and --project are required (try --help)" >&2; exit 2; }
FDIR=$(sk_feature_dir "$PACK" "$FEATURE") || { echo "speckit-converge: no feature directory: $PACK/specs/$FEATURE" >&2; exit 2; }
ROADMAP="$PROJECT/docs/ROADMAP.md"
[ -f "$FDIR/spec.md" ] || { echo "speckit-converge: no spec.md in the pack" >&2; exit 2; }
[ -f "$ROADMAP" ]      || { echo "speckit-converge: no docs/ROADMAP.md in the project" >&2; exit 2; }
[ -n "$OUT" ] || OUT="$PROJECT/.speckit-handoff"

RM_LIB=$(find_roadmap_lib "$PROJECT") || { echo "speckit-converge: cannot find _roadmap.sh — cannot tell a completed phase from an open one (fail-closed)." >&2; exit 2; }
# shellcheck disable=SC1090
. "$RM_LIB"

# --- read (never write) the two sides ----------------------------------------------------------
SPEC_IDS=$(printf '%s\n%s\n' "$(sk_ids "$FDIR/spec.md" FR)" "$(sk_ids "$FDIR/spec.md" SC)" | grep -E '.' | sort -u)
# Requirement ids the roadmap NAMES (in any "- FR-###"/"- SC-###" line under any phase).
ROADMAP_IDS=$(grep -oE '\b(FR|SC)-[0-9]{3}\b' "$ROADMAP" 2>/dev/null | sort -u)

# COVERED: in both. MISSING: in the spec, absent from the roadmap (unbuilt requirement).
# DRIFT: on the roadmap, absent from the spec (the spec moved after import).
COVERED=$(comm -12 <(printf '%s\n' "$SPEC_IDS") <(printf '%s\n' "$ROADMAP_IDS"))
MISSING=$(comm -23 <(printf '%s\n' "$SPEC_IDS") <(printf '%s\n' "$ROADMAP_IDS"))
DRIFT=$(comm -13 <(printf '%s\n' "$SPEC_IDS") <(printf '%s\n' "$ROADMAP_IDS"))

# --- FROZEN: a COMPLETED phase whose SPEC changed since import ----------------------------------
# Frozen means the spec MOVED under finished work. That is decided by the SPEC's content hash at
# import time (stamped as `spec.md@<hash>` on the Sources: line), NOT by whether the roadmap's
# requirement label still matches the spec text. The label is deliberately allowed to be a short
# paraphrase — the id is the stable key. (The dogfood caught the earlier label-vs-text version
# crying wolf on every paraphrase.) If no phase carries an import baseline, frozen is UNCHECKED,
# and we say so rather than guessing.
FROZEN=""; FROZEN_UNCHECKED=0
while IFS= read -r h; do
  [ -n "$h" ] || continue
  open=$(roadmap_open_count "$ROADMAP" "$h")
  [ "$open" = 0 ] || continue                   # phase still open — not frozen, just in progress
  block=$(PH="$h" awk '$0==ENVIRON["PH"]{inp=1;next} /^## /&&inp{inp=0} inp' "$ROADMAP")
  # The import baseline for this phase: `specs/.../spec.md@<hash>` on its Sources: line.
  base_hash=$(printf '%s\n' "$block" | grep -m1 -oE 'spec\.md@[0-9a-f]+' | sed 's/.*@//')
  if [ -z "$base_hash" ]; then FROZEN_UNCHECKED=1; continue; fi
  now_hash=$(sk_hash "$FDIR/spec.md")
  [ "$base_hash" = "$now_hash" ] && continue    # spec unchanged since import — nothing frozen
  # The spec changed. Only the ids on THIS completed phase are affected.
  ids=$(printf '%s\n' "$block" | grep -oE '\b(FR|SC)-[0-9]{3}\b' | sort -u)
  for id in $ids; do
    # Report only ids whose CURRENT spec text still exists (a removed id is DRIFT, handled above).
    [ -n "$(sk_req_text "$FDIR/spec.md" "$id")" ] && FROZEN="$FROZEN $id"
  done
done < <(sk_phase_headings "$ROADMAP")

# --- NEW upstream tasks: T### in tasks.md that no roadmap phase carries -------------------------
NEW_TASKS=""
if [ -f "$FDIR/tasks.md" ]; then
  while IFS= read -r tline; do
    tid=$(printf '%s' "$tline" | grep -oE '\bT[0-9]{3}\b' | head -1)
    [ -n "$tid" ] || continue
    grep -q "\b$tid\b" "$ROADMAP" 2>/dev/null || NEW_TASKS="$NEW_TASKS $tid"
  done < <(grep -E '^[[:space:]]*- \[[ xX]\] ' "$FDIR/tasks.md")
fi

# --- write the report, and ONLY the report -----------------------------------------------------
mkdir -p "$OUT" || { echo "speckit-converge: cannot create $OUT" >&2; exit 2; }
count() { printf '%s' "$1" | grep -cE '.' ; }
list()  { if [ -n "$1" ]; then printf '%s\n' "$1" | sed 's/^/- /'; else printf '_none_\n'; fi; }

{
  printf '# Convergence — %s\n\n' "$(sk_title "$FDIR/spec.md")"
  printf 'Pack `%s/specs/%s` against `docs/ROADMAP.md`. **This is a report. Nothing was changed.**\n\n' "$PACK" "$FEATURE"

  printf '## Coverage\n\nRequirements the roadmap accounts for:\n\n'; list "$COVERED"; printf '\n'

  printf '## Missing — a requirement with no phase\n\n'
  printf 'In `spec.md`, absent from every roadmap phase. This is unplanned work:\n\n'; list "$MISSING"
  printf '\n> To close a gap, propose it with `import-speckit` and let a human append it. A missing\n'
  printf '> requirement is a phase nobody has planned — not a task to pick up here.\n\n'

  printf '## Drift — an id the spec no longer has\n\n'
  printf 'Named on the roadmap, gone from `spec.md` (the spec moved after import):\n\n'; list "$DRIFT"; printf '\n'

  printf '## Frozen — a completed phase whose spec changed since import\n\n'
  if [ -n "$FROZEN" ]; then
    printf 'The `spec.md` content hash differs from the one stamped at import (`spec.md@<hash>` on the\n'
    printf 'Sources: line), and these ids sit on a COMPLETED phase:\n\n'
    for id in $FROZEN; do printf -- '- `%s`\n' "$id"; done
    printf '\n> Report-only cannot rewrite a completed phase, and must not. A human decides whether the\n'
    printf '> spec change warrants a NEW phase or is already satisfied.\n\n'
  elif [ "$FROZEN_UNCHECKED" = 1 ]; then
    printf '_UNCHECKED — a completed phase carries no import baseline (`spec.md@<hash>` on its Sources:\n'
    printf 'line), so a spec change under it cannot be detected. Re-import through `import-speckit` to\n'
    printf 'stamp one._\n\n'
  else
    printf '_none — every completed phase''s spec is unchanged since import._\n\n'
  fi

  printf '## New upstream tasks\n\n'
  printf '`T###` tasks in `tasks.md` with no counterpart on the roadmap:\n\n'
  if [ -n "$NEW_TASKS" ]; then for t in $NEW_TASKS; do printf -- '- `%s`\n' "$t"; done; else printf '_none_\n'; fi
  printf '\n'

  printf '## What this report cannot do\n\n'
  printf -- '- It cannot tick a phase. Only `scripts/tick.sh` writes `- [x]`, on an evaluator PASS plus green\n'
  printf '  evidence bound to HEAD — neither of which this tool can produce.\n'
  printf -- '- It cannot reopen a completed phase, weaken a requirement, or edit code.\n'
  printf -- '- It did not touch `tasks.md`. (Upstream `/speckit-converge` appends tasks there; this does not.)\n'
} > "$OUT/CONVERGENCE.md"

# --- verdict -----------------------------------------------------------------------------------
NM=$(count "$MISSING"); ND=$(count "$DRIFT")
echo "speckit-converge: wrote $OUT/CONVERGENCE.md  (covered=$(count "$COVERED") missing=$NM drift=$ND frozen=$(printf '%s' "$FROZEN" | wc -w | tr -d ' '))"

if [ "$INFORMATIONAL" = 1 ]; then exit 0; fi
[ -n "$FROZEN" ] && exit 3                      # a human must look — outranks a plain gap
{ [ "$NM" -gt 0 ] || [ "$ND" -gt 0 ]; } && exit 1
exit 0
