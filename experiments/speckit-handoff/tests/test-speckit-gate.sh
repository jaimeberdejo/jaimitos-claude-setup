#!/usr/bin/env bash
# test-speckit-gate.sh — behavioral tests for the Spec Kit handoff gate + proposer.
#
# Runs the REAL scripts against the REAL fixture packs, in throwaway git repos. Where a claim is
# about compatibility with Jaimitos core, the test executes the UNMODIFIED core script — the real
# lint-roadmap.sh, the real _roadmap.sh, the real _high-stakes.sh, the real tick.sh. A copy would
# prove nothing: the whole point is that the fragment we generate is valid to the tools that ship.
#
# Exit codes under test (they mirror scripts/tick.sh on purpose):
#   0 importable · 1 refused (nothing written) · 2 usage error · 3 high-stakes → supervised
set -uo pipefail

EXP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$EXP/../.." && pwd)"
SCAFFOLD="$ROOT/jaimitos-os"
GATE="$EXP/bin/speckit-gate.sh"
PROPOSE="$EXP/bin/speckit-propose.sh"
FIX="$EXP/fixtures"

# The real core scripts. Every compatibility claim below goes through these.
LINT="$SCAFFOLD/scripts/lint-roadmap.sh"
TICK="$SCAFFOLD/scripts/tick.sh"
RM_LIB="$SCAFFOLD/.claude/lib/_roadmap.sh"
HS_LIB="$SCAFFOLD/.claude/lib/_high-stakes.sh"
SS_LIB="$SCAFFOLD/.claude/lib/_secret-scan.sh"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

for f in "$LINT" "$TICK" "$RM_LIB" "$HS_LIB"; do
  [ -f "$f" ] || { echo "test: missing core script $f" >&2; exit 1; }
done
command -v git >/dev/null 2>&1 || { echo "test: git required" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t speckit-gate)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# mkproject <name> — a throwaway Jaimitos project from fixtures/project-base, in git.
# Phase 1 is COMPLETE, Phase 2 is open, and the roadmap carries a legend line that MENTIONS the
# "- [ ]" notation (the exact prose v2.11.2 taught core not to treat as a task).
mkproject() {
  PROJ="$WORK/$1"; rm -rf "$PROJ"; mkdir -p "$PROJ"
  cp -R "$FIX/project-base/." "$PROJ/"
  ( cd "$PROJ" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A && git commit -qm init )
}
# Run the gate/proposer, capturing rc and output. $OUT holds the report dir.
run() { "$@" >"$WORK/out" 2>&1; echo $?; }
outof() { cat "$WORK/out"; }
md5of() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

echo "speckit handoff gate tests"; echo ""

# ---------------------------------------------------------------- pack shape (G1)
echo "G1 — pack shape:"
mkproject g1
for missing in spec.md plan.md tasks.md; do
  PK="$WORK/pack-$missing"; rm -rf "$PK"; cp -R "$FIX/A-complete" "$PK"
  rm -f "$PK/specs/001-widget-search/$missing"
  rc=$(run bash "$GATE" --pack "$PK" --feature 001-widget-search --project "$PROJ")
  [ "$rc" = 1 ] && pass "missing $missing → refuses (exit 1)" || fail "missing $missing not refused (rc=$rc)"
done

# ---------------------------------------------------------------- clarification (G2)
echo ""
echo "G2 — unresolved clarification:"
mkproject g2
rc=$(run bash "$GATE" --pack "$FIX/B-unresolved-clarification" --feature 001-widget-search --project "$PROJ")
[ "$rc" = 1 ] && pass "fixture B: [NEEDS CLARIFICATION] → refuses (exit 1)" || fail "fixture B not refused (rc=$rc)"
outof | grep -qE 'spec\.md:[0-9]+' \
  && pass "names the file:line of the unresolved clarification" || fail "did not cite file:line"

# ---------------------------------------------------------------- SC structure vs measurability
echo ""
echo "G3a — SC structure is a HARD gate:"
mkproject g3a
PK="$WORK/pack-dupsc"; rm -rf "$PK"; cp -R "$FIX/A-complete" "$PK"
printf -- '- **SC-001**: a second, duplicate success criterion.\n' >> "$PK/specs/001-widget-search/spec.md"
rc=$(run bash "$GATE" --pack "$PK" --feature 001-widget-search --project "$PROJ")
{ [ "$rc" = 1 ] && outof | grep -q 'SC-001'; } \
  && pass "duplicate SC ID → refuses, naming the ID" || fail "duplicate SC ID not refused (rc=$rc)"

PK="$WORK/pack-nosc"; rm -rf "$PK"; cp -R "$FIX/A-complete" "$PK"
grep -v '\*\*SC-' "$PK/specs/001-widget-search/spec.md" > "$PK/tmp" && mv "$PK/tmp" "$PK/specs/001-widget-search/spec.md"
rc=$(run bash "$GATE" --pack "$PK" --feature 001-widget-search --project "$PROJ")
[ "$rc" = 1 ] && pass "no success criteria at all → refuses" || fail "missing SCs not refused (rc=$rc)"

echo ""
echo "G3b — measurability is a WARNING, not a refusal:"
# The plan's first draft made this a hard gate. It cannot be one: "the operation is idempotent" is
# measurable with no digit in it, and "handles 100 users" has a digit and is useless. A gate people
# route around is worse than no gate — so this warns, flags for human review, and records a waiver.
mkproject g3b
rc=$(run bash "$PROPOSE" --pack "$FIX/C-non-measurable-sc" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff")
[ "$rc" = 0 ] && pass "fixture C: unmeasurable-looking SC → still imports (exit 0)" || fail "fixture C wrongly refused (rc=$rc)"
grep -q 'SC-001' "$PROJ/.speckit-handoff/HANDOFF.md" 2>/dev/null \
  && pass "HANDOFF.md flags the SC for human measurability review" || fail "SC not flagged for review"
grep -qi 'human review' "$PROJ/.speckit-handoff/HANDOFF.md" 2>/dev/null \
  && pass "HANDOFF.md carries a 'For human review' section" || fail "no human-review section"
# SC-003 ("the endpoint is idempotent") has no digit but IS measurable — it must be reported as a
# warning a human can waive, never as a hard failure. Proving the false positive exists is the point.
grep -q 'SC-003' "$PROJ/.speckit-handoff/HANDOFF.md" 2>/dev/null \
  && pass "the known false positive (idempotent, no digit) surfaces as a warning" \
  || fail "SC-003 false positive not surfaced — the heuristic's cost is being hidden"

# ---------------------------------------------------------------- happy path (A)
echo ""
echo "fixture A — complete pack:"
mkproject a
rc=$(run bash "$PROPOSE" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff")
[ "$rc" = 0 ] && pass "complete pack → imports (exit 0)" || fail "complete pack refused (rc=$rc)"
[ -f "$PROJ/.speckit-handoff/roadmap.append.md" ] && pass "writes roadmap.append.md" || fail "no fragment written"
[ -f "$PROJ/.speckit-handoff/HANDOFF.md" ]        && pass "writes HANDOFF.md"        || fail "no report written"

FRAG="$PROJ/.speckit-handoff/roadmap.append.md"

# ---------------------------------------------------------------- IDs survive (G6)
echo ""
echo "G6 — requirement IDs survive the handoff:"
missing=""
for id in FR-001 FR-002 FR-003 FR-004 SC-001 SC-002 SC-003; do
  grep -q -- "$id" "$FRAG" 2>/dev/null || missing="$missing $id"
done
[ -z "$missing" ] && pass "every FR/SC id from spec.md appears in the fragment" \
                  || fail "ids lost in the handoff:$missing"
grep -q 'Sources:' "$FRAG" && pass "each phase cites its Sources:" || fail "no Sources: line"
grep -q 'Requirements:' "$FRAG" && pass "each phase cites its Requirements:" || fail "no Requirements: line"

# ---------------------------------------------------------------- schema, via the REAL linter (G8)
echo ""
echo "G8 — the merged roadmap passes the UNMODIFIED core linter:"
cat "$PROJ/docs/ROADMAP.md" "$FRAG" > "$WORK/merged.md"
bash "$LINT" --strict "$WORK/merged.md" >/dev/null 2>&1
[ $? = 0 ] && pass "lint-roadmap.sh --strict accepts the merged roadmap" \
           || fail "the generated fragment is not roadmap-schema-valid"

# ---------------------------------------------------------------- parser agreement (G7 + v2.11.2)
echo ""
echo "G7 — the shared parser reads exactly the tasks we generated:"
# shellcheck disable=SC1090
. "$RM_LIB"
gen_tasks=$(grep -c '^- \[ \] ' "$FRAG" 2>/dev/null | tr -d ' ')
before=$(roadmap_open_total "$PROJ/docs/ROADMAP.md")
after=$(roadmap_open_total "$WORK/merged.md")
[ "$((after - before))" = "$gen_tasks" ] \
  && pass "roadmap_open_total sees exactly the $gen_tasks tasks the fragment adds (no phantom tasks)" \
  || fail "parser counts $((after - before)) new open tasks, fragment has $gen_tasks"
# Every proposed phase must have a Mode the REAL parser accepts.
badmode=""
while IFS= read -r h; do
  [ -n "$h" ] || continue
  m=$(roadmap_phase_mode "$WORK/merged.md" "$h" 2>/dev/null); mrc=$?
  { [ "$mrc" = 0 ] && [ -n "$m" ]; } || badmode="$badmode [$h]"
done < <(grep '^## Phase' "$FRAG")
[ -z "$badmode" ] && pass "every proposed phase has a Mode the real _roadmap.sh accepts" \
                  || fail "invalid Mode on:$badmode"

# ---------------------------------------------------------------- poison line (G7 hard gate)
echo ""
echo "G7 — a fragment cannot forge an open task out of prose:"
mkproject poison
POISON_FRAG="$WORK/poison.md"
{ printf '## Phase 9 — Poisoned\n'
  printf -- '- [ ] a real task\n'
  printf 'Done when: every - [ ] item is checked\n'   # a line CONTAINING the notation, unanchored
  printf 'Mode: loopable\n'; } > "$POISON_FRAG"
rc=$(run bash "$GATE" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --fragment "$POISON_FRAG")
[ "$rc" = 1 ] && pass "a fragment line containing '- [' that is not a task → refuses" \
              || fail "poison line accepted (rc=$rc) — generated text could forge an open task"

# ---------------------------------------------------------------- append-only (G4) + collision (G5)
echo ""
echo "G4/G5 — completed history is not mutable:"
mkproject e
rc=$(run bash "$PROPOSE" --pack "$FIX/E-completed-phase-conflict" --feature 003-browse-catalogue --project "$PROJ" --out "$PROJ/.speckit-handoff")
{ [ "$rc" = 1 ] && outof | grep -qi 'Phase 1'; } \
  && pass "fixture E: a phase that collides with COMPLETED Phase 1 → refuses, naming it" \
  || fail "fixture E did not refuse the completed-phase collision (rc=$rc)"
[ "$(md5of "$PROJ/docs/ROADMAP.md")" = "$(md5of "$FIX/project-base/docs/ROADMAP.md")" ] \
  && pass "docs/ROADMAP.md is byte-identical after the refusal" || fail "the roadmap was modified on refusal"

# A fragment that would REWRITE an existing block is unrepresentable: the output is an append
# fragment, so the current roadmap must be an exact byte PREFIX of the merged result.
mkproject prefix
rc=$(run bash "$PROPOSE" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff")
cat "$PROJ/docs/ROADMAP.md" "$PROJ/.speckit-handoff/roadmap.append.md" > "$WORK/m2.md"
sz=$(wc -c < "$PROJ/docs/ROADMAP.md" | tr -d ' ')
head -c "$sz" "$WORK/m2.md" | cmp -s - "$PROJ/docs/ROADMAP.md" \
  && pass "the current roadmap is an exact byte prefix of the merged result (append-only)" \
  || fail "the merge is not append-only — existing phases could be rewritten"

# ---------------------------------------------------------------- high-stakes (G9)
echo ""
echo "G9 — KNOWN high-stakes PATHS force supervised:"
mkproject d
rc=$(run bash "$PROPOSE" --pack "$FIX/D-high-stakes" --feature 002-account-recovery --project "$PROJ" --out "$PROJ/.speckit-handoff")
[ "$rc" = 3 ] && pass "fixture D: high-stakes paths → exit 3 (caller must NOT auto-apply)" \
              || fail "fixture D did not exit 3 (rc=$rc)"
if [ -f "$PROJ/.speckit-handoff/roadmap.append.md" ]; then
  unsup=$(grep -c '^Mode: loopable' "$PROJ/.speckit-handoff/roadmap.append.md" 2>/dev/null | tr -d ' ')
  sup=$(grep -c '^Mode: supervised' "$PROJ/.speckit-handoff/roadmap.append.md" 2>/dev/null | tr -d ' ')
  { [ "$unsup" = 0 ] && [ "$sup" -gt 0 ]; } \
    && pass "every proposed phase is Mode: supervised ($sup phases, 0 loopable)" \
    || fail "high-stakes pack produced $unsup loopable phase(s)"
else
  fail "exit 3 must still produce the fragment (for human review)"
fi
grep -qE 'src/auth/|migrations/' "$PROJ/.speckit-handoff/HANDOFF.md" 2>/dev/null \
  && pass "HANDOFF.md names the high-stakes path that triggered it" || fail "the triggering path is not named"

# ---------------------------------------------------------------- scope contradiction (F) — NOT a gate
echo ""
echo "fixture F — scope contradiction is SURFACED, never judged:"
# Deliberately NOT detected. Scope contradiction is semantic; a token-overlap heuristic would
# false-positive and false-negative, and a green test named detects_scope_contradiction would be
# exactly the overstated guarantee this repo punishes. The gate surfaces the inputs; a human judges.
mkproject f
rc=$(run bash "$PROPOSE" --pack "$FIX/F-scope-contradiction" --feature 004-social-login --project "$PROJ" --out "$PROJ/.speckit-handoff")
[ "$rc" = 0 ] && pass "fixture F: the gate does NOT pretend to detect a scope contradiction (exit 0)" \
              || fail "fixture F was refused (rc=$rc) — the gate is claiming judgement it does not have"
grep -q 'docs/SPEC.md' "$PROJ/.speckit-handoff/HANDOFF.md" 2>/dev/null \
  && pass "HANDOFF.md points the human at docs/SPEC.md to judge scope" || fail "docs/SPEC.md not surfaced"

# ---------------------------------------------------------------- the tick monopoly
echo ""
echo "the tick monopoly — importing creates no shortcut to 'done':"
mkproject tick
bash "$PROPOSE" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff" >/dev/null 2>&1
mkdir -p "$PROJ/scripts" "$PROJ/.claude/lib"
cp "$TICK" "$PROJ/scripts/tick.sh"
cp "$RM_LIB" "$HS_LIB" "$SS_LIB" "$PROJ/.claude/lib/"
cat "$PROJ/.speckit-handoff/roadmap.append.md" >> "$PROJ/docs/ROADMAP.md"
head=$(grep -m1 '^## Phase' "$PROJ/.speckit-handoff/roadmap.append.md")
( cd "$PROJ" && git add -A && git commit -qm "import" )
before=$(md5of "$PROJ/docs/ROADMAP.md")
rc=$( cd "$PROJ" && bash scripts/tick.sh "$head" >/dev/null 2>&1; echo $? )
{ [ "$rc" != 0 ] && [ "$before" = "$(md5of "$PROJ/docs/ROADMAP.md")" ]; } \
  && pass "the REAL tick.sh refuses an imported phase with no grade + no evidence (roadmap untouched)" \
  || fail "an imported phase ticked without an evaluator PASS (rc=$rc) — the import forged a shortcut"

# ---------------------------------------------------------------- no writes outside --out
echo ""
echo "the write boundary:"
mkproject nowrite
snap=$(md5of "$PROJ/docs/ROADMAP.md")
bash "$PROPOSE" --pack "$FIX/A-complete" --feature 001-widget-search --project "$PROJ" --out "$PROJ/.speckit-handoff" >/dev/null 2>&1
dirty=$( cd "$PROJ" && git status --porcelain | grep -v '^?? .speckit-handoff/' | tr -d ' \n' )
{ [ "$snap" = "$(md5of "$PROJ/docs/ROADMAP.md")" ] && [ -z "$dirty" ]; } \
  && pass "nothing outside --out is created or modified (docs/ROADMAP.md byte-identical)" \
  || fail "wrote outside --out: [$dirty]"

# ---------------------------------------------------------------- argument discipline
echo ""
echo "argument discipline (mirrors run-guard-tests.sh):"
rc=$(run bash "$GATE" --help);        [ "$rc" = 0 ] && pass "--help → 0"          || fail "--help not 0 (rc=$rc)"
rc=$(run bash "$GATE" --nonsense);    [ "$rc" = 2 ] && pass "unknown flag → 2"    || fail "unknown flag not 2 (rc=$rc)"
rc=$(run bash "$GATE");               [ "$rc" = 2 ] && pass "no --pack → 2"       || fail "missing --pack not 2 (rc=$rc)"
rc=$(run bash "$PROPOSE" --help);     [ "$rc" = 0 ] && pass "propose --help → 0"  || fail "propose --help not 0 (rc=$rc)"

# ---------------------------------------------------------------- bash 3.2
echo ""
echo "portability (CI asserts bash 3.2 on the macOS leg):"
BAD=""
for f in "$EXP"/bin/*.sh "$EXP"/tests/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" 2>/dev/null || BAD="$BAD $(basename "$f"):syntax"
  grep -qE '(declare -A|mapfile|readarray|\$\{[A-Za-z_]+\^\^\})' "$f" 2>/dev/null \
    && BAD="$BAD $(basename "$f"):bash4"
done
[ -z "$BAD" ] && pass "every experiment script is bash-3.2 safe" || fail "bash-4 constructs / syntax:$BAD"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All speckit gate tests passed."; exit 0
else echo "$FAILS speckit gate test(s) FAILED."; echo "--- last output ---"; tail -n 15 "$WORK/out" 2>/dev/null; exit 1; fi
