#!/usr/bin/env bash
# test-speckit-converge.sh — the report-only convergence check.
#
# "Report-only" means NO STATE MUTATION. It does NOT mean "every run succeeds": the first draft of
# the plan had it exit 0 always, which makes it useless as a signal. So it carries a meaningful
# exit code, and the tests pin every one of them — AND prove it writes nothing but its report.
#
#   0  no blocking convergence gaps
#   1  gaps or drift found
#   2  usage / malformed input
#   3  a stale/frozen conflict a human must resolve
#   --informational forces 0 (a caller that wants the report without a failing status)
set -uo pipefail

EXP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONV="$EXP/bin/speckit-converge.sh"
FIX="$EXP/fixtures"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
command -v git >/dev/null 2>&1 || { echo "test: git required" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t speckit-conv)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
md5of() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

# mkproject <name> — a Jaimitos project whose roadmap already IMPORTED fixture A (all its FR/SC on
# one phase), so coverage is complete. Individual tests then perturb it to create gaps/drift.
mkproject() {
  PROJ="$WORK/$1"; rm -rf "$PROJ"; mkdir -p "$PROJ/docs"
  cp -R "$FIX/project-base/." "$PROJ/"
  cat >> "$PROJ/docs/ROADMAP.md" <<'EOF'

## Phase 3 — Widget Search
- [ ] T002 implement search_widgets(query, limit) in src/search/query.py
Sources: specs/001-widget-search/spec.md specs/001-widget-search/plan.md
Requirements:
- FR-001 — System MUST return widgets whose name contains the query, case-insensitively.
- FR-002 — System MUST order results by relevance, most relevant first.
- FR-003 — System MUST show an empty state, echoing the query, when nothing matches.
- FR-004 — System MUST expose search at `GET /widgets?q=<query>`.
- SC-001 — p95 search latency is under 200 ms against the 10k-widget fixture.
- SC-002 — A user finds a known widget in under 10 seconds from the home page.
- SC-003 — Searching a term with no matches returns HTTP 200 and 0 results, never a 404.
Done when: the search tests are green
Mode: loopable
EOF
  ( cd "$PROJ" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
}
run() { "$@" >"$WORK/out" 2>&1; echo $?; }
outof() { cat "$WORK/out"; }

echo "speckit convergence (report-only) tests"; echo ""

# ---------------------------------------------------------------- full coverage → 0
echo "exit codes are meaningful (not always-0):"
mkproject clean
rc=$(run bash "$CONV" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff")
[ "$rc" = 0 ] && pass "every FR/SC on the roadmap → exit 0 (no gaps)" || { fail "full coverage not 0 (rc=$rc)"; outof | sed 's/^/      /'; }

# ---------------------------------------------------------------- a gap → 1
mkproject gap
# Drop FR-004 from the roadmap phase: the spec requires it, the roadmap no longer names it.
grep -v 'FR-004' "$PROJ/docs/ROADMAP.md" > "$PROJ/docs/ROADMAP.tmp" && mv "$PROJ/docs/ROADMAP.tmp" "$PROJ/docs/ROADMAP.md"
( cd "$PROJ" && git commit -aqm "drop FR-004" )
rc=$(run bash "$CONV" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff")
{ [ "$rc" = 1 ] && grep -q 'FR-004' "$PROJ/.speckit-handoff/CONVERGENCE.md"; } \
  && pass "a spec requirement absent from the roadmap → exit 1, reported as a gap" || fail "gap not caught (rc=$rc)"

# ---------------------------------------------------------------- drift → 1
mkproject drift
# The roadmap names an id the spec no longer has (spec moved after import).
sed -i.bak 's/FR-002 — System MUST order/FR-099 — System MUST order/' "$PROJ/docs/ROADMAP.md"; rm -f "$PROJ"/docs/*.bak
( cd "$PROJ" && git commit -aqm "rename to FR-099" )
rc=$(run bash "$CONV" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff")
{ [ "$rc" = 1 ] && grep -q 'FR-099' "$PROJ/.speckit-handoff/CONVERGENCE.md"; } \
  && pass "an id on the roadmap that the spec no longer has → exit 1, reported as drift" || fail "drift not caught (rc=$rc)"

# ---------------------------------------------------------------- frozen conflict → 3
echo ""
echo "a completed phase whose spec text moved → exit 3 (human review):"
mkproject frozen
# Mark the imported phase COMPLETE, then change the spec text underneath it.
sed -i.bak 's/- \[ \] T002/- [x] T002/' "$PROJ/docs/ROADMAP.md"; rm -f "$PROJ"/docs/*.bak
PACK="$WORK/pack-moved"; rm -rf "$PACK"; cp -R "$FIX/A-complete" "$PACK"
sed -i.bak 's/most relevant first/by popularity, most popular first/' "$PACK/specs/001-widget-search/spec.md"; rm -f "$PACK"/specs/001-widget-search/*.bak
( cd "$PROJ" && git commit -aqm "complete phase 3" )
rc=$(run bash "$CONV" --pack "$PACK" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff")
{ [ "$rc" = 3 ] && grep -qi 'frozen\|completed' "$PROJ/.speckit-handoff/CONVERGENCE.md"; } \
  && pass "spec text changed under a COMPLETED phase → exit 3 (frozen; a human must look)" \
  || { fail "frozen conflict not exit 3 (rc=$rc)"; outof | sed 's/^/      /'; }

# ---------------------------------------------------------------- --informational forces 0
echo ""
echo "--informational:"
mkproject info
grep -v 'FR-004' "$PROJ/docs/ROADMAP.md" > "$PROJ/docs/ROADMAP.tmp" && mv "$PROJ/docs/ROADMAP.tmp" "$PROJ/docs/ROADMAP.md"
( cd "$PROJ" && git commit -aqm gap )
rc=$(run bash "$CONV" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff" --informational)
{ [ "$rc" = 0 ] && grep -q 'FR-004' "$PROJ/.speckit-handoff/CONVERGENCE.md"; } \
  && pass "a gap with --informational → still reports it, but exit 0" || fail "--informational did not force 0 (rc=$rc)"

# ---------------------------------------------------------------- report-only: it MUTATES NOTHING
echo ""
echo "report-only means no state mutation (proved, not asserted):"
mkproject nowrite
before_r=$(md5of "$PROJ/docs/ROADMAP.md"); before_s=$(md5of "$PROJ/docs/STATE.md")
run bash "$CONV" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff" >/dev/null
dirty=$( cd "$PROJ" && git status --porcelain | grep -v '^?? .speckit-handoff/' | tr -d ' \n' )
{ [ "$before_r" = "$(md5of "$PROJ/docs/ROADMAP.md")" ] && [ "$before_s" = "$(md5of "$PROJ/docs/STATE.md")" ] && [ -z "$dirty" ]; } \
  && pass "docs/ROADMAP.md + docs/STATE.md byte-identical; nothing changed outside --out" \
  || fail "convergence mutated project state: [$dirty]"
# It also does not append to tasks.md (the upstream converge behaviour we explicitly rejected).
[ "$(md5of "$FIX/A-complete/specs/001-widget-search/tasks.md")" ] # exists
run bash "$CONV" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff" >/dev/null
git -C "$FIX/../.." diff --quiet -- experiments/speckit-handoff/fixtures 2>/dev/null \
  && pass "the feature pack's tasks.md is untouched (no upstream-style task append)" \
  || fail "convergence wrote into the feature pack"

# ---------------------------------------------------------------- argument discipline
echo ""
echo "argument discipline:"
rc=$(bash "$CONV" --help >/dev/null 2>&1; echo $?);     [ "$rc" = 0 ] && pass "--help → 0"       || fail "--help not 0 (rc=$rc)"
rc=$(bash "$CONV" --nonsense >/dev/null 2>&1; echo $?); [ "$rc" = 2 ] && pass "unknown flag → 2" || fail "unknown flag not 2 (rc=$rc)"
rc=$(bash "$CONV" >/dev/null 2>&1; echo $?);            [ "$rc" = 2 ] && pass "missing args → 2" || fail "missing args not 2 (rc=$rc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All convergence tests passed."; exit 0
else echo "$FAILS convergence test(s) FAILED."; echo "--- last output ---"; tail -n 15 "$WORK/out" 2>/dev/null; exit 1; fi
