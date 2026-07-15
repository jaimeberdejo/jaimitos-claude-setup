#!/usr/bin/env bash
# test-preset-real-cli.sh — the LIVE tier. Network required. Opt-in: SPECKIT_LIVE=1.
#
# WHY THIS EXISTS. The preset is the single most fragile artifact in this experiment (REJECT
# criterion R2): it is the only sanctioned way to neuter /speckit-implement, its schema is not a
# contract, and upstream ships several releases a day. Reading preset.yml and concluding "Spec Kit
# will honour this" is not evidence — it is a guess with a YAML file next to it.
#
# So this installs the PINNED CLI, initialises a throwaway project, applies the preset, and asks the
# real thing what it actually generated.
#
# It also answers the question that gates everything else (dogfood step 0, REJECT criterion R7):
#   does `specify init` touch anything Jaimitos owns?
# Source-reading says no — --force merges, and the Claude integration writes only into speckit-*
# subdirs. That is a claim. This is the check.
#
# Exit: 0 pass · 1 fail · 2 usage/unavailable
set -uo pipefail

SPECKIT_REF="${SPECKIT_REF:-v0.12.13}"
SPECKIT_REPO="git+https://github.com/github/spec-kit.git"

EXP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FP="$EXP/bin/speckit-footprint.sh"
MANIFEST="$EXP/footprint/speckit-0.12.13.json"
PRESET="$EXP/preset/jaimitos-handoff"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
skip() { printf '  · SKIPPED: %s\n' "$1"; }

echo "speckit preset — LIVE tier (pinned $SPECKIT_REF)"; echo ""

if ! command -v uvx >/dev/null 2>&1; then
  echo "  ⛔ uvx not found. The live tier cannot run, and it must NOT be reported as passing:"
  echo "     the preset is untested until this runs. Install uv (https://docs.astral.sh/uv/)."
  exit 2
fi

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t speckit-live)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
PROJ="$WORK/proj"; mkdir -p "$PROJ"

sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 || sha256sum "$1" | cut -d' ' -f1; }

# --- a Jaimitos project, as install.sh leaves it ------------------------------------------------
mkdir -p "$PROJ/.claude/skills/tdd" "$PROJ/.claude/skills/roadmap" "$PROJ/docs"
printf -- '---\nname: tdd\ndescription: TDD discipline.\n---\n'         > "$PROJ/.claude/skills/tdd/SKILL.md"
printf -- '---\nname: roadmap\ndescription: Roadmap discipline.\n---\n' > "$PROJ/.claude/skills/roadmap/SKILL.md"
printf '# Roadmap\n\n## Phase 1 — x\n- [ ] a\nDone when: x\nMode: loopable\n' > "$PROJ/docs/ROADMAP.md"
printf '# State\n' > "$PROJ/docs/STATE.md"
printf '# Spec\n' > "$PROJ/docs/SPEC.md"
printf '# Project\n' > "$PROJ/CLAUDE.md"
: > "$PROJ/.claude/.jaimitos-manifest"
for f in .claude/skills/tdd/SKILL.md .claude/skills/roadmap/SKILL.md; do
  printf '%s  %s\n' "$(sha "$PROJ/$f")" "$f" >> "$PROJ/.claude/.jaimitos-manifest"
done
( cd "$PROJ" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )

# --- R7 — does `specify init` touch anything we own? --------------------------------------------
echo "R7 — the install footprint:"
bash "$FP" --project "$PROJ" --manifest "$MANIFEST" --snapshot "$WORK/baseline" >/dev/null 2>&1

# `specify init --here` initialises the CURRENT directory — so we MUST run it from inside $PROJ.
# (The first version ran it from the test's cwd, initialised the wrong tree, and then "found" the
# project's manifest missing and its skills absent. Both live failures were this one bug.)
if ! ( cd "$PROJ" && uvx --from "${SPECKIT_REPO}@${SPECKIT_REF}" specify init --here --force --integration claude ) \
        >"$WORK/init.log" 2>&1; then
  echo "  ⛔ \`specify init\` failed. This is NOT a pass — the integration is unverified."
  tail -n 20 "$WORK/init.log" | sed 's/^/     /'
  exit 1
fi
pass "\`specify init --here --integration claude\` completed (pinned $SPECKIT_REF)"

# The ownership check does the real work: same path + same owner = fine; different owner = collision.
if bash "$FP" --project "$PROJ" --manifest "$MANIFEST" --baseline "$WORK/baseline" > "$WORK/fp.log" 2>&1; then
  pass "Spec Kit stayed inside its own footprint — nothing Jaimitos owns was touched"
else
  fail "specify init wrote outside its footprint — this is REJECT criterion R7"
  grep '⛔' "$WORK/fp.log" | sed 's/^/     /'
fi
# Report the measured always-loaded tax (R1) whatever the verdict — it is the number the go/no-go turns on.
grep -E 'model-invoked speckit|command surface' "$WORK/fp.log" | sed 's/^  ·/  →/'

# --- the preset ---------------------------------------------------------------------------------
echo ""
echo "the preset (REJECT criterion R2 — is it honoured at all?):"
IMPL_BEFORE="$PROJ/.claude/skills/speckit-implement/SKILL.md"
if [ ! -f "$IMPL_BEFORE" ]; then
  fail "no .claude/skills/speckit-implement/SKILL.md — the skills-mode assumption is wrong for $SPECKIT_REF"
  echo ""; echo "$FAILS live check(s) FAILED."; exit 1
fi
pass "spec-kit installed speckit-implement as a SKILL (skills-mode confirmed for $SPECKIT_REF)"

# Local install is `specify preset add <id> --dev <dir>` (NOT --from, which is for a URL ZIP; NOT
# `preset install`, which does not exist). The first version guessed all three wrong — the live tier
# caught it, and the schema itself was wrong too (missing schema_version, flat shape). R2 in the
# flesh: the preset is the only sanctioned override and its schema is not a contract.
if ( cd "$PROJ" && uvx --from "${SPECKIT_REPO}@${SPECKIT_REF}" specify preset add jaimitos-handoff --dev "$PRESET" ) \
      >"$WORK/preset.log" 2>&1; then
  pass "the preset installed against the pinned CLI (\`preset add --dev\`)"

  # Did it actually REPLACE the command body? This is the whole R2 question.
  if grep -qi 'Implementation is not yours\|owned by Jaimitos' "$IMPL_BEFORE" 2>/dev/null; then
    pass "speckit-implement's body was REPLACED by the redirect (it now points at /phase)"
  else
    fail "speckit-implement still carries its upstream body — the preset did NOT take effect"
  fi

  # Spec Kit re-emits the frontmatter; a preset-sourced skill should say so.
  grep -q 'source: preset:jaimitos-handoff' "$IMPL_BEFORE" 2>/dev/null \
    && pass "the CLI attributes the skill to our preset (source: preset:jaimitos-handoff)" \
    || fail "the skill is not attributed to the preset — it may not have taken"

  # A half-rendered template is worse than none: it would read as an instruction with holes in it.
  if grep -q '__SPECKIT_COMMAND_' "$IMPL_BEFORE" 2>/dev/null; then
    fail "unresolved __SPECKIT_COMMAND_*__ placeholders in the generated skill"
  else
    pass "no unresolved placeholders in the generated skill"
  fi
else
  # A FINDING, not a test error: if the preset cannot be installed against the pinned CLI, R2 fired.
  fail "the preset could not be applied to the pinned CLI — REJECT criterion R2 (the preset treadmill)"
  echo "     actual CLI output:"
  tail -n 12 "$WORK/preset.log" | sed 's/^/       /'
  echo "     → Jaimitos cannot own a moving target it does not control. Record this in REPORT.md."
fi

# --- what the preset can NEVER do ---------------------------------------------------------------
echo ""
echo "what actually protects the queue (and it is not the preset):"
# Stated as a check so the report cannot drift into claiming the preset is a wall. It is a signpost.
if [ -f "$PROJ/docs/ROADMAP.md" ] && git -C "$PROJ" diff --quiet -- docs/ROADMAP.md 2>/dev/null; then
  pass "docs/ROADMAP.md is untouched by the whole Spec Kit install + preset flow"
else
  fail "docs/ROADMAP.md changed during install/preset — Spec Kit reached the queue"
fi
echo "  → the preset is PROMPT-LEVEL. It asks. What it cannot do is stop a model writing code."
echo "  → the real protection: nothing Spec Kit writes can tick a phase (scripts/tick.sh needs an"
echo "    evaluator PASS + green evidence bound to HEAD), and tasks.md is not the roadmap."

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All live preset checks passed (pinned $SPECKIT_REF)."; exit 0
else echo "$FAILS live check(s) FAILED — record them in REPORT.md; do not paper over them."; exit 1; fi
