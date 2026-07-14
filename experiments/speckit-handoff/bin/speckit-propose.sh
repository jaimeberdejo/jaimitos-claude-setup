#!/usr/bin/env bash
# speckit-propose.sh — render a Spec Kit feature pack as a Jaimitos roadmap FRAGMENT + a report.
#
# It PROPOSES. It never edits docs/ROADMAP.md — a human appends the fragment, deliberately:
#     cat .speckit-handoff/roadmap.append.md >> docs/ROADMAP.md
#
# Everything it emits is unchecked "- [ ]" tasks. There is no path from here to "done": that still
# requires an evaluator PASS and green test evidence bound to HEAD, and only scripts/tick.sh can
# write "- [x]".
#
# Flow: gate the PACK → render the fragment → gate the FRAGMENT → write. Same gate both times.
#
# Exit: 0 proposed · 1 refused (nothing written) · 2 usage · 3 high-stakes (supervised; do NOT auto-apply)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
. "$HERE/_speckit-lib.sh"
GATE="$HERE/speckit-gate.sh"

usage() {
  cat <<'EOF'
usage: speckit-propose.sh --pack <dir> --feature <NNN-slug> [--project <dir>] [--out <dir>]

  Writes <out>/roadmap.append.md (the fragment) and <out>/HANDOFF.md (the report).
  Default --out is <project>/.speckit-handoff. Nothing outside <out> is ever written.

exit: 0 proposed · 1 refused · 2 usage · 3 high-stakes (supervised; do NOT auto-apply)
EOF
}

PACK=""; FEATURE=""; PROJECT="."; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pack)    PACK="${2:-}";    shift 2 || exit 2 ;;
    --feature) FEATURE="${2:-}"; shift 2 || exit 2 ;;
    --project) PROJECT="${2:-}"; shift 2 || exit 2 ;;
    --out)     OUT="${2:-}";     shift 2 || exit 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "speckit-propose: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
[ -n "$PACK" ] && [ -n "$FEATURE" ] || { echo "speckit-propose: --pack and --feature are required (try --help)" >&2; exit 2; }
[ -n "$OUT" ] || OUT="$PROJECT/.speckit-handoff"

# ---- 1. gate the PACK. Exit 1 → stop; nothing is written. -------------------------------------
bash "$GATE" --pack "$PACK" --feature "$FEATURE" --project "$PROJECT"
PACK_RC=$?
HIGH_STAKES=0
case "$PACK_RC" in
  0) : ;;                    # clean
  3) HIGH_STAKES=1 ;;        # high-stakes: still propose, but supervised, and exit 3 at the end
  *) exit "$PACK_RC" ;;      # 1 refused / 2 usage — propagate verbatim, write nothing
esac

FDIR=$(sk_feature_dir "$PACK" "$FEATURE")
ROADMAP="$PROJECT/docs/ROADMAP.md"
[ -f "$ROADMAP" ] || { echo "speckit-propose: no $ROADMAP" >&2; exit 1; }

TITLE=$(sk_title "$FDIR/spec.md")
NUM=$(sk_next_phase_num "$ROADMAP")
MODE=loopable; [ "$HIGH_STAKES" = 1 ] && MODE=supervised
FR_IDS=$(sk_ids "$FDIR/spec.md" FR)
SC_IDS=$(sk_ids "$FDIR/spec.md" SC)

# ---- 2. render the fragment -------------------------------------------------------------------
# ONE phase per feature is the mechanical default, and that is a deliberate limitation, stated in
# the report rather than papered over: Spec Kit does not link a requirement to a task, so there is
# no way to attribute FR/SC ids to a SUBSET of the work without guessing. A proposer that split the
# feature and then guessed the attribution would hand the evaluator requirements the phase was never
# meant to satisfy, and every phase would fail traceability for a reason nobody introduced.
# Sizing is judgement: the `import-speckit` skill regroups, and re-gates what it produces.
TMPD=$(mktemp -d 2>/dev/null || mktemp -d -t sk-frag)
trap 'rm -rf "$TMPD" 2>/dev/null' EXIT
FRAG="$TMPD/roadmap.append.md"

{
  printf '\n## Phase %s — %s\n' "$NUM" "$TITLE"
  sk_tasks "$FDIR/tasks.md" | while IFS= read -r t; do
    [ -n "$t" ] || continue
    printf -- '- [ ] %s\n' "$t"
  done
  printf 'Sources:'
  for f in spec.md plan.md tasks.md; do printf ' specs/%s/%s' "$FEATURE" "$f"; done
  [ -d "$FDIR/contracts" ] && printf ' specs/%s/contracts/' "$FEATURE"
  printf '\n'
  printf 'Requirements:\n'
  for id in $FR_IDS $SC_IDS; do
    printf -- '- %s — %s\n' "$id" "$(sk_req_text "$FDIR/spec.md" "$id")"
  done
  # "Done when:" must be non-empty (the linter proves that) and observable (it cannot). The default
  # cites the success criteria by id; a human or the import-speckit skill sharpens the wording.
  printf 'Done when: every success criterion holds — %s (see specs/%s/spec.md) — and the test suite is green\n' \
    "$(printf '%s' "$SC_IDS" | tr '\n' ',' | sed -e 's/,$//' -e 's/,/, /g')" "$FEATURE"
  printf 'Mode: %s\n' "$MODE"
} > "$FRAG"

# ---- 3. gate the FRAGMENT — the same gate, no bypass -------------------------------------------
bash "$GATE" --pack "$PACK" --feature "$FEATURE" --project "$PROJECT" --fragment "$FRAG" >/dev/null 2>"$TMPD/gate.err"
FRAG_RC=$?
if [ "$FRAG_RC" = 1 ]; then
  cat "$TMPD/gate.err" >&2

  exit 1
fi

# ---- 4. write, and ONLY under --out -----------------------------------------------------------
mkdir -p "$OUT" || { rm -rf "$TMPD"; echo "speckit-propose: cannot create $OUT" >&2; exit 1; }
cp "$FRAG" "$OUT/roadmap.append.md"

UNMEASURED=""
for id in $SC_IDS; do
  sk_measurable "$(sk_req_text "$FDIR/spec.md" "$id")" || UNMEASURED="$UNMEASURED $id"
done
HS_PATHS=$(grep -A99 'HIGH-STAKES paths' "$TMPD/gate.err" 2>/dev/null | grep -E '^  [^ ]' | sed 's/^  //' || true)

{
  printf '# Handoff — %s\n\n' "$TITLE"
  printf 'Pack: `%s/specs/%s`\n' "$PACK" "$FEATURE"
  printf 'Proposed: **Phase %s — %s** (`Mode: %s`)\n\n' "$NUM" "$TITLE" "$MODE"
  printf 'Apply it deliberately — this tool does not touch your roadmap:\n\n'
  printf '```\ncat %s/roadmap.append.md >> docs/ROADMAP.md\n```\n\n' "$OUT"

  printf '## Requirements carried across\n\n'
  for id in $FR_IDS $SC_IDS; do
    printf -- '- `%s` — %s\n' "$id" "$(sk_req_text "$FDIR/spec.md" "$id")"
  done
  printf '\n'

  printf '## For human review\n\n'
  printf 'These are the things this tool deliberately does NOT decide. It surfaces the inputs; you judge.\n\n'

  printf '### Scope — does this contradict the milestone?\n\n'
  printf 'Read `docs/SPEC.md` (especially **Non-goals**) against the requirements above. A feature pack\n'
  printf 'knows nothing about your milestone scope, and this gate does not attempt to judge semantics:\n'
  printf 'a token-overlap heuristic would be wrong in both directions, and a green "no contradiction"\n'
  printf 'would be a guarantee nobody can honour.\n\n'

  if [ -n "$UNMEASURED" ]; then
    printf '### Measurability — confirm or waive\n\n'
    printf 'These success criteria carry no numeric or comparator signal:\n\n'
    for id in $UNMEASURED; do
      printf -- '- [ ] `%s` — %s\n' "$id" "$(sk_req_text "$FDIR/spec.md" "$id")"
    done
    printf '\n**The check is a heuristic and it is wrong in both directions.** "The operation is\n'
    printf 'idempotent" is perfectly measurable and has no digit in it; "handles 100 users" has one and\n'
    printf 'says nothing. So this warns rather than refusing. Waive what is fine; sharpen what is not.\n\n'
  else
    printf '### Measurability\n\nEvery success criterion carries a numeric or comparator signal. (That it *looks*\n'
    printf 'measurable is all this check can tell you.)\n\n'
  fi

  if [ "$HIGH_STAKES" = 1 ]; then
    printf '### High-stakes — supervised, and a human must approve\n\n'
    printf 'The pack names paths the **real** `_high-stakes.sh` classifies as high-stakes:\n\n'
    printf '%s\n' "$HS_PATHS" | sed 's/^/- `/;s/$/`/'
    printf '\nThe phase is `Mode: supervised`, so `scripts/tick.sh` will refuse to auto-tick it. Note this\n'
    printf 'gate matches **paths, not intentions**: high-stakes work described only in prose ("purge the\n'
    printf 'audit log") will not be caught here. That classification is yours.\n\n'
  fi

  printf '### Sizing\n\n'
  printf 'This is **one phase for the whole feature**, on purpose. Spec Kit does not link a requirement\n'
  printf 'to a task, so splitting the feature would mean guessing which FR/SC each slice owes — and the\n'
  printf 'evaluator would then hold a phase to requirements it was never meant to satisfy. If the feature\n'
  printf 'is too big for one phase (it probably is), regroup it with the `import-speckit` skill, which\n'
  printf 'attributes the requirements itself and re-runs this same gate on what it produces.\n\n'

  printf '## What this import cannot do\n\n'
  printf -- '- It cannot mark anything done. Every task above is `- [ ]`. Only `scripts/tick.sh` writes `- [x]`,\n'
  printf '  and only on an evaluator `PASS` plus green test evidence bound to `HEAD`.\n'
  printf -- '- It cannot rewrite history. The output is an append fragment; there is no whole-roadmap output.\n'
  printf -- '- `specs/%s/tasks.md` is **not** the queue. `docs/ROADMAP.md` is.\n' "$FEATURE"
} > "$OUT/HANDOFF.md"



echo "speckit-propose: wrote $OUT/roadmap.append.md and $OUT/HANDOFF.md"
[ "$HIGH_STAKES" = 1 ] && { echo "speckit-propose: HIGH-STAKES — supervised. Do NOT auto-apply; a human must approve." >&2; exit 3; }
exit 0
