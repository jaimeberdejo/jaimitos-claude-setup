#!/usr/bin/env bash
# close-milestone.sh — archive a COMPLETED roadmap and scaffold the next one, but REFUSE to
# close while any work or unresolved finding remains. This is the deterministic replacement for
# the old milestone prose ("ask whether to proceed anyway") — there is NO bypass flag by design.
#
# Refuses (exit 1) when:
#   - docs/ROADMAP.md has any open "- [ ]" item, OR
#   - NEXT_FINDINGS.md exists (an unresolved evaluator finding), OR
#   - docs/ROADMAP.md has no phases at all (nothing to close — also makes re-runs safe).
# On success: git mv docs/ROADMAP.md -> docs/archive/ROADMAP-<label>.md (label = --name arg,
# else a VERSION file, else the latest git tag, else the UTC date), write a fresh empty
# docs/ROADMAP.md, and reset the docs/STATE.md auto-block to point at the next scope.
#
# Usage: bash scripts/close-milestone.sh [--name <label>]
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1
ROADMAP="docs/ROADMAP.md"
STATE="docs/STATE.md"

NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    -h|--help)
      echo "usage: close-milestone.sh [--name <label>]"
      echo "  Archive a COMPLETED roadmap and scaffold the next. Refuses while any open item or an"
      echo "  unresolved NEXT_FINDINGS.md remains — no bypass by design."
      exit 0 ;;
    *) echo "close-milestone: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

refuse() { echo "close-milestone: REFUSED — $1" >&2; exit 1; }

# Shared roadmap parser — the SAME first-open-heading + Mode classification tick.sh uses, via one
# library instead of a hand-copied awk block. Sourced best-effort: close-milestone refuses on ANY
# open item regardless of Mode, so if the lib were somehow absent the classification just degrades to
# a generic message (never a wrong "safe to close").
[ -f .claude/lib/_roadmap.sh ] && . .claude/lib/_roadmap.sh 2>/dev/null || true

[ -f "$ROADMAP" ] || refuse "no $ROADMAP to close."
# Anchored to actual list-item lines (start of line, optional leading whitespace) — a plain
# substring grep also matches the roadmap skill's own instructional legend line
# ("> `- [ ]` = todo, `- [x]` = done. ..."), which is permanently present at the top of every
# roadmap it generates and would otherwise ALWAYS false-positive as "open items remain."
grep -qE '^[[:space:]]*- \[[ xX]\] ' "$ROADMAP" 2>/dev/null || refuse "no phases in $ROADMAP — nothing to close."
# Open items remain → classify the FIRST open phase so the refusal is actionable, not a flat "open
# items remain". Three cases: (a) a supervised phase awaiting explicit human approval (name it +
# point at tick.sh --supervised-approved — the new v2.4.0 path so a supervised phase is no longer a
# dead end), (b) an unresolved evaluator finding (NEXT_FINDINGS.md) gating it, (c) plain unfinished
# work. The heading + Mode classification come from the shared _roadmap.sh parser.
if grep -qE '^[[:space:]]*- \[ \] ' "$ROADMAP" 2>/dev/null; then
  if command -v roadmap_first_open_heading >/dev/null 2>&1; then
    first_open=$(roadmap_first_open_heading "$ROADMAP" 2>/dev/null || true)
    first_mode=$(roadmap_phase_mode "$ROADMAP" "$first_open" 2>/dev/null || true)
  else
    first_open=$(awk '/^## /{h=$0} /^[[:space:]]*- \[ \] /{if(h!=""){print h; exit}}' "$ROADMAP")
    first_mode=""
  fi
  case "$first_mode" in
    supervised)
      echo "close-milestone: the first open phase is SUPERVISED and awaiting human approval:" >&2
      echo "close-milestone:   ${first_open#\#\# }" >&2
      echo "close-milestone:   approve + tick it with:" >&2
      echo "close-milestone:     bash scripts/tick.sh --supervised-approved \"$first_open\" --note \"<why it's safe>\"" >&2
      refuse "a supervised phase is unticked — approve it (command above), then close." ;;
    *)
      if [ -f NEXT_FINDINGS.md ]; then
        echo "close-milestone: an unresolved evaluator finding (NEXT_FINDINGS.md) is blocking the first open phase:" >&2
        echo "close-milestone:   ${first_open#\#\# }" >&2
        refuse "resolve NEXT_FINDINGS.md and finish the open phase, then close."
      else
        echo "close-milestone: the first open phase still has unfinished work:" >&2
        echo "close-milestone:   ${first_open#\#\# }" >&2
        refuse "open items remain in $ROADMAP — finish or remove them first."
      fi ;;
  esac
fi
[ -f NEXT_FINDINGS.md ] && refuse "NEXT_FINDINGS.md exists (an unresolved evaluator finding) — resolve it first."

# Non-fatal notice: surface open '## Ownership gaps' entries in docs/STATE.md (skipped/incomplete
# teach-backs are recorded there) so they don't silently accumulate across milestones. This never
# blocks the close — plain echo to stderr, no exit — and section-absent is treated exactly like
# section-empty: the scaffold ships with no '## Ownership gaps' heading by default.
if [ -f "$STATE" ] && grep -qx '## Ownership gaps' "$STATE" 2>/dev/null; then
  open_gaps=$(awk '
    $0=="## Ownership gaps" { inphase=1; next }
    /^## / && inphase { inphase=0 }
    inphase && /^[[:space:]]*-[[:space:]]*[^[:space:]]/ { c++ }
    END { print c+0 }
  ' "$STATE")
  [ "${open_gaps:-0}" -gt 0 ] && echo "close-milestone: NOTE — docs/STATE.md has open '## Ownership gaps' entries; carrying them into the next milestone unresolved." >&2
fi

# Non-fatal notice: architectural drift across the milestone.
# Per-PHASE review structurally cannot see this. The evaluator grades a phase diff, so ten
# individually-clean phases can still compose into a pass-through layer, and nobody is looking at
# the whole. The milestone boundary is the only place that view exists — so surface it here.
# NEVER blocks the close (same contract as the Ownership-gaps notice above): a stale map is a
# prompt to run `mapme`, not a reason to trap a finished milestone.
#
# "This milestone" = since the previous close (the commit that created the newest
# docs/archive/ROADMAP-*.md). Scoping it that way means the notice fires when a WHOLE milestone was
# built without ever refreshing the map — not on every close, which would be noise nobody reads.
# Fail-open throughout: a shallow clone or an odd history yields no notice, never a false alarm.
ARCH="docs/ARCHITECTURE.md"
ms_start=$(git log -1 --format=%H -- docs/archive 2>/dev/null || true)
RANGE="${ms_start:+$ms_start..}HEAD"
# Code = anything outside docs/. A docs-only milestone has nothing to re-map.
code_commits=$(git log --oneline "$RANGE" -- . ':(exclude)docs' 2>/dev/null | wc -l | tr -d ' ')
if [ "${code_commits:-0}" -gt 0 ]; then
  if [ ! -f "$ARCH" ]; then
    echo "close-milestone: NOTE — no $ARCH, but $code_commits code commit(s) landed this milestone. Run the \`mapme\` skill (it also flags architectural friction: shallow modules, pass-through layers, leaky seams)." >&2
  else
    arch_touched=$(git log --oneline "$RANGE" -- "$ARCH" 2>/dev/null | wc -l | tr -d ' ')
    [ "${arch_touched:-0}" -eq 0 ] && \
      echo "close-milestone: NOTE — $ARCH was not refreshed during this milestone ($code_commits code commit(s) since the last close). Run the \`mapme\` skill; carry any Strong friction findings into the next roadmap." >&2
  fi
fi

# Pick the archive label.
if [ -z "$NAME" ]; then
  if [ -f VERSION ]; then
    NAME=$(tr -d '[:space:]' < VERSION)
  elif NAME=$(git describe --tags --abbrev=0 2>/dev/null) && [ -n "$NAME" ]; then
    :
  fi
fi
[ -z "$NAME" ] && NAME=$(date -u +%Y%m%d 2>/dev/null || echo milestone)

mkdir -p docs/archive
DEST="docs/archive/ROADMAP-$NAME.md"
# Never clobber existing history — suffix if a same-named archive already exists.
[ -e "$DEST" ] && DEST="docs/archive/ROADMAP-$NAME-$(date -u +%H%M%S 2>/dev/null || echo dup).md"
git mv "$ROADMAP" "$DEST" 2>/dev/null || mv "$ROADMAP" "$DEST"

cat > "$ROADMAP" <<'MD'
# Roadmap

<!--
Author phases here (use the `roadmap` skill, or the `milestone` skill Mode A). Each phase is:
a "## Phase N — <goal>" heading, one unchecked checkbox line per task, a "Done when:" line with
an observable/machine-checkable condition, and a "Mode: loopable | supervised" line.
See docs/archive/ for the previous milestone's phases as examples.
-->
MD

# Reset the STATE auto-block (if present) to point at authoring the next scope.
if [ -f "$STATE" ] && grep -qF '<!-- lean:auto:begin -->' "$STATE"; then
  awk -v d="$NAME" '
    /<!-- lean:auto:begin -->/ {
      print
      print "_Auto-generated by scripts/tick.sh on each roadmap tick — do not edit between these markers._"
      print ""
      print "- Milestone " d " closed. Author the next scope, then plan its first phase."
      skip=1; next
    }
    /<!-- lean:auto:end -->/ { print; skip=0; next }
    !skip { print }
  ' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
fi

echo "close-milestone: ✓ archived $ROADMAP → $DEST; fresh roadmap created. Author the next scope (roadmap skill)."
