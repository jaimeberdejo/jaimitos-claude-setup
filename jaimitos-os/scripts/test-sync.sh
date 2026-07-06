#!/usr/bin/env bash
# test-sync.sh — scripts/sync.sh must pull toolkit fixes into an already-scaffolded project
# conservatively: never a blind two-way overwrite. Covers arg validation, enumeration parity
# with install.sh's find+exclusions, the four-tier classifier, the three non-mixed tiers
# end-to-end (overwrite / never / unknown), and the mixed tier's value-preserving merge for its
# three known shapes (HIGH_STAKES_RE= / model: / paths: block) plus its malformed fail-safe.
#
# Mixed-tier contract under test: a WELL-FORMED differing mixed file always prompts (never
# bypassed by --yes) and, on yes, merges toolkit body + project value; a MALFORMED shape in
# either copy is NEVER guessed at — it routes to manual review and is left byte-identical.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$SCAFFOLD/scripts/sync.sh"
[ -f "$SYNC" ] || { echo "test: missing $SYNC" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-sync)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# mktoolkit: fresh fake jaimitos-os checkout with one file per tier, the enumeration-exclusion
# fixtures (toolkit-docs/, .github/workflows/, .DS_Store), and a repo-root VERSION next to it
# (sync.sh reads <toolkit>/../VERSION, mirroring install.sh's layout: VERSION next to the
# jaimitos-os/ scaffold dir). Sets the global $TOOLKIT to the scaffold dir path.
mktoolkit() {
  rm -rf "$WORK/src"
  TOOLKIT="$WORK/src/jaimitos-os"
  mkdir -p "$TOOLKIT/scripts" "$TOOLKIT/.github/scripts" "$TOOLKIT/.github/workflows" \
           "$TOOLKIT/.claude/lib" "$TOOLKIT/.claude/hooks" "$TOOLKIT/.claude/commands" \
           "$TOOLKIT/.claude/agents" "$TOOLKIT/.claude/rules" "$TOOLKIT/docs" \
           "$TOOLKIT/toolkit-docs"
  printf '9.9.9\n' > "$WORK/src/VERSION"

  printf '#!/usr/bin/env bash\necho toolkit-foo\n' > "$TOOLKIT/scripts/foo.sh"
  printf '#!/usr/bin/env bash\necho toolkit-a\n'   > "$TOOLKIT/scripts/a.sh"
  printf '#!/usr/bin/env bash\necho toolkit-guard\n' > "$TOOLKIT/.claude/hooks/guard.sh"
  printf '#!/usr/bin/env bash\necho toolkit-z\n'   > "$TOOLKIT/.github/scripts/z.sh"
  printf 'name: ci\n'                              > "$TOOLKIT/.github/workflows/y"
  printf 'legacy toolkit doc\n'                     > "$TOOLKIT/toolkit-docs/x"
  : > "$TOOLKIT/.DS_Store"
  printf '#!/usr/bin/env bash\n# TOOLKIT_HS_BODY_V2\nHIGH_STAKES_RE=toolkit-default\n' > "$TOOLKIT/.claude/lib/_high-stakes.sh"
  printf '{"hooks":{}}\n'             > "$TOOLKIT/.claude/settings.json"
  printf '# Spec\ntoolkit copy\n'     > "$TOOLKIT/docs/SPEC.md"
  printf '# Project\ntoolkit copy\n'  > "$TOOLKIT/CLAUDE.md"

  # Mixed-shape #2 fixtures (Phase 2): agent frontmatter, with and without a model: line —
  # mirrors researcher/planner/executor (no model: = inherit) and evaluator (ships model: sonnet).
  cat > "$TOOLKIT/.claude/agents/researcher.md" <<'EOF'
---
name: researcher
description: TOOLKIT_BODY_V2 researcher
tools: Read, Grep, Glob
---

Toolkit researcher body v2.
EOF
  cat > "$TOOLKIT/.claude/agents/evaluator.md" <<'EOF'
---
name: evaluator
description: TOOLKIT_BODY_V2 evaluator
tools: Read, Glob, Grep, Bash
model: sonnet
---

Toolkit evaluator body v2.
EOF

  # Mixed-shape #3 fixture (Phase 2): rules/high-stakes.md's paths: frontmatter block.
  cat > "$TOOLKIT/.claude/rules/high-stakes.md" <<'EOF'
---
description: TOOLKIT_BODY_V2 rule
paths:
  - "**/toolkit-v2-path/**"
  - "**/toolkit-v2-other/**"
---

# TOOLKIT_BODY_V2 heading
Toolkit rule body v2.
EOF
}

# mkproject <name>: fresh throwaway git repo, cd's the CURRENT shell into it (tests run
# sequentially, each starting a new project — mirrors mkrepo() in test-close-milestone.sh).
mkproject() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO"
  ( cd "$REPO" && git init -q )
  cd "$REPO" || exit 1
}

# runsync [args...]: run the real sync.sh against $TOOLKIT with no stdin attached beyond what's
# already redirected; captures combined output to $WORK/out, echoes the exit code.
runsync() {
  bash "$SYNC" --toolkit "$TOOLKIT" "$@" >"$WORK/out" 2>&1
  echo $?
}

echo "sync.sh tests"; echo ""

# 1 — args: --toolkit missing / pointed at a nonexistent path.
mkproject t1-a
bash "$SYNC" >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -ne 0 ] && grep -qi toolkit "$WORK/out"; } \
  && pass "missing --toolkit → clear error, nonzero exit" \
  || fail "missing --toolkit mishandled (rc=$rc)"

mkproject t1-b
bash "$SYNC" --toolkit /nonexistent-toolkit-path-xyz >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -ne 0 ] && grep -qi toolkit "$WORK/out"; } \
  && pass "--toolkit /nonexistent → clear error, nonzero exit" \
  || fail "nonexistent --toolkit mishandled (rc=$rc)"

mkproject t1-c
bash "$SYNC" --toolkit "$REPO" --bogus-flag >"$WORK/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && pass "unknown argument → nonzero exit" || fail "unknown argument not rejected (rc=$rc)"

# 2 — enumeration parity: excluded dirs/files are never offered; scripts/*.sh IS offered, and
# .github/scripts/*.sh is still ENUMERATED (never blanket-excluded, proving sync doesn't treat all
# of .github/* like install.sh's default) — but since t2 has no .github/ dir, Fix 3's CI opt-in
# gate reports it skipped rather than offering to add it (see tests 12a/12b for the full matrix).
mktoolkit
mkproject t2
rc=$(runsync --dry-run)
{ [ "$rc" -eq 0 ] \
  && grep -q "scripts/a.sh" "$WORK/out" \
  && grep -q ".github/scripts/z.sh" "$WORK/out" \
  && grep -qi "skipped (CI not opted in" "$WORK/out" \
  && ! grep -q "toolkit-docs" "$WORK/out" \
  && ! grep -q ".github/workflows" "$WORK/out" \
  && ! grep -q "DS_Store" "$WORK/out"; } \
  && pass "enumeration mirrors install.sh's exclusions (toolkit-docs/, .github/workflows/, .DS_Store never offered); .github/scripts/z.sh still enumerated but skipped (CI not opted in) with no .github/ dir" \
  || fail "enumeration parity broken"

# 3 — overwrite tier: --yes updates a differing project file to match the toolkit's bytes.
mktoolkit
mkproject t3
mkdir -p scripts
printf '#!/usr/bin/env bash\necho project-foo\n' > scripts/foo.sh
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh"; } \
  && pass "overwrite tier: --yes updates a differing file to the toolkit's bytes" \
  || fail "overwrite --yes did not update scripts/foo.sh (rc=$rc)"

# 3b — overwrite tier: a piped "n" answer (no --yes) leaves the file untouched.
mktoolkit
mkproject t3b
mkdir -p scripts
printf '#!/usr/bin/env bash\necho project-foo\n' > scripts/foo.sh
printf 'n\n' | bash "$SYNC" --toolkit "$TOOLKIT" >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q "project-foo" scripts/foo.sh && ! cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh"; } \
  && pass "overwrite tier: piped 'n' declines, file left unchanged" \
  || fail "declined overwrite ('n') still changed the file (rc=$rc)"

# 3c — overwrite tier: an empty answer defaults to NO (no --yes).
mktoolkit
mkproject t3c
mkdir -p scripts
printf '#!/usr/bin/env bash\necho project-foo\n' > scripts/foo.sh
printf '\n' | bash "$SYNC" --toolkit "$TOOLKIT" >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q "project-foo" scripts/foo.sh && ! cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh"; } \
  && pass "overwrite tier: empty answer defaults to NO, file left unchanged" \
  || fail "empty answer wrongly applied the overwrite (rc=$rc)"

# 4 — never tier: project docs/SPEC.md and CLAUDE.md stay byte-identical even with --yes.
mktoolkit
mkproject t4
mkdir -p docs
printf '# Spec\nproject customized\n'    > docs/SPEC.md
printf '# Project\nproject customized\n' > CLAUDE.md
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && grep -q "project customized" docs/SPEC.md && grep -q "project customized" CLAUDE.md; } \
  && pass "never tier: docs/SPEC.md and CLAUDE.md untouched even with --yes" \
  || fail "never-tier file was overwritten (rc=$rc)"

# 5 — mixed tier (Phase 2): a well-formed differing _high-stakes.sh is NEVER auto-applied by
# --yes (mixed always prompts); with no piped answer the confirm defaults to NO, so the file is
# declined/skipped and left byte-identical — proves mixed isn't treated as overwrite.
mktoolkit
mkproject t5
mkdir -p .claude/lib
printf '#!/usr/bin/env bash\nHIGH_STAKES_RE=project-custom-regex\n' > .claude/lib/_high-stakes.sh
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && grep -q "project-custom-regex" .claude/lib/_high-stakes.sh && grep -qi "skipped (declined mixed merge)" "$WORK/out"; } \
  && pass "mixed tier: well-formed differing _high-stakes.sh → declined by default, untouched even with --yes" \
  || fail "mixed-tier file was overwritten or not reported as declined (rc=$rc)"

# 6 — unknown tier: a differing .claude/settings.json is left byte-identical, reported manual.
mktoolkit
mkproject t6
mkdir -p .claude
printf '{"hooks":{},"env":{"CUSTOM":"1"}}\n' > .claude/settings.json
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && grep -q "CUSTOM" .claude/settings.json && grep -qi "manual review" "$WORK/out"; } \
  && pass "unknown tier: differing .claude/settings.json untouched, reported as manual review" \
  || fail "unknown-tier file was overwritten or not reported (rc=$rc)"

# 7 — --dry-run: nothing is written for ANY tier, regardless of --yes.
mktoolkit
mkproject t7
mkdir -p scripts docs .claude/lib
printf 'project foo\n'          > scripts/foo.sh
printf 'project spec\n'         > docs/SPEC.md
printf 'project claude\n'       > CLAUDE.md
printf 'HIGH_STAKES_RE=project\n' > .claude/lib/_high-stakes.sh
printf '{"env":{"X":1}}\n'      > .claude/settings.json
rc=$(runsync --dry-run --yes)
{ [ "$rc" -eq 0 ] \
  && grep -q "project foo" scripts/foo.sh \
  && grep -q "project spec" docs/SPEC.md \
  && grep -q "project claude" CLAUDE.md \
  && grep -q "HIGH_STAKES_RE=project" .claude/lib/_high-stakes.sh \
  && grep -q '"X":1' .claude/settings.json \
  && [ ! -f .claude/.jaimitos-os-version ]; } \
  && pass "--dry-run writes nothing for any tier (all files byte-identical, no version stamp)" \
  || fail "--dry-run mutated the project tree (rc=$rc)"

# 8 — .claude/.jaimitos-os-version is written/updated to the toolkit VERSION after a real run;
# its prior absence doesn't error.
mktoolkit
mkproject t8
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && [ -f .claude/.jaimitos-os-version ] && [ "$(cat .claude/.jaimitos-os-version)" = "9.9.9" ]; } \
  && pass ".claude/.jaimitos-os-version stamped with toolkit VERSION after a real run (prior absence didn't error)" \
  || fail "version stamp missing or wrong after a real run (rc=$rc)"

# 9 — a --toolkit checkout that enumerates to ZERO files (valid shape, but empty of shipped
# files) must not crash. Bash 3.2 regression guard: "${arr[@]}" on a declared-but-empty array
# throws "unbound variable" under `set -u` unless the loop is guarded by the count form first.
rm -rf "$WORK/empty-src"; TOOLKIT="$WORK/empty-src/jaimitos-os"
mkdir -p "$TOOLKIT/.claude" "$TOOLKIT/scripts"
mkproject t9
rc=$(runsync --dry-run)
[ "$rc" -eq 0 ] && pass "empty --toolkit enumeration (0 files) exits cleanly, no 'unbound variable' crash" \
  || fail "empty --toolkit enumeration crashed or errored (rc=$rc)"

# 10 — Fix 1 regression: a destination cp genuinely cannot write to (chmod 444, so cp's own
# open() fails with EACCES) must be reported as FAILED, must NOT be counted/printed as "updated",
# and must make sync exit nonzero. Uses the same chmod-444-as-non-root pattern as
# test-models.sh's permission-preservation tests, which this repo's harness already relies on.
mktoolkit
mkproject t10
mkdir -p scripts
printf '#!/usr/bin/env bash\necho project-foo\n' > scripts/foo.sh
chmod 444 scripts/foo.sh
rc=$(runsync --yes)
{ [ "$rc" -ne 0 ] \
  && grep -qi "FAILED: scripts/foo.sh" "$WORK/out" \
  && ! grep -q "updated: scripts/foo.sh" "$WORK/out" \
  && ! cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh"; } \
  && pass "Fix 1: cp failure (read-only destination) → FAILED reported, nonzero exit, not counted as updated" \
  || fail "cp failure was silently treated as success (rc=$rc)"
chmod 644 scripts/foo.sh 2>/dev/null || true   # restore write perms so trap cleanup never trips

# 11 — Fix 2 regression: overwriting a mode-644 (non-executable) project scripts/*.sh or
# .claude/hooks/*.sh with --yes must leave the destination executable afterward — install.sh
# makes these executable on a fresh install, and sync must restore that bit too, or a fresh
# checkout re-synced could silently leave a guard hook non-executable (defeating it with no error).
mktoolkit
mkproject t11
mkdir -p scripts .claude/hooks
printf '#!/usr/bin/env bash\necho project-foo\n'   > scripts/foo.sh
printf '#!/usr/bin/env bash\necho project-guard\n' > .claude/hooks/guard.sh
chmod 644 scripts/foo.sh .claude/hooks/guard.sh
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && [ -x scripts/foo.sh ] && [ -x .claude/hooks/guard.sh ]; } \
  && pass "Fix 2: overwriting a mode-644 scripts/*.sh and .claude/hooks/*.sh with --yes leaves both executable" \
  || fail "exec bit not restored after overwrite (rc=$rc)"

# 12a — Fix 3 regression: a toolkit .github/scripts/z.sh, ADDED to a project with NO .github/ dir
# at all, must be reported as skipped (CI not opted in) and must NOT actually be written.
mktoolkit
mkproject t12a
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] \
  && grep -qi "skipped (CI not opted in" "$WORK/out" \
  && grep -q ".github/scripts/z.sh" "$WORK/out" \
  && [ ! -e .github/scripts/z.sh ]; } \
  && pass "Fix 3: .github/scripts/z.sh NOT added to a project with no .github/ dir; reported CI-not-opted-in skip" \
  || fail ".github add wrongly offered/applied without CI opt-in (rc=$rc)"

# 12b — Fix 3 counterpart: a project that already opted into CI (has a .github/ dir, even an
# otherwise-empty one) is unaffected by the gate — the add is offered/applied normally.
mktoolkit
mkproject t12b
mkdir -p .github
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] \
  && ! grep -qi "CI not opted in" "$WORK/out" \
  && grep -q "added: .github/scripts/z.sh" "$WORK/out" \
  && cmp -s .github/scripts/z.sh "$TOOLKIT/.github/scripts/z.sh"; } \
  && pass "Fix 3 counterpart: project with an existing .github/ dir still gets .github/scripts/z.sh added normally" \
  || fail ".github add wrongly gated for a project that already opted into CI (rc=$rc)"

# ============================================================================================
# Phase 2 — value-preserving mixed-file merge (HIGH_STAKES_RE= / model: / paths: block) and its
# malformed fail-safe. The overriding rule under test throughout: an unexpected/malformed shape
# in EITHER the project's or the toolkit's copy must leave the project file byte-identical
# (verified with `cmp -s` against a saved-off copy, not just a substring grep) and be reported —
# never guessed, never partially written.
# ============================================================================================

# 13 — hs_lib normal merge: project's HIGH_STAKES_RE value (containing regex metacharacters
# |()[].* — the exact reason sync.sh must NOT use `sed s/.../$value/`) survives verbatim, AND
# the toolkit's body line change lands. Proves both halves of the merge in one fixture.
mktoolkit
mkproject t13
mkdir -p .claude/lib
printf '#!/usr/bin/env bash\n# PROJECT_HS_BODY_V1\nHIGH_STAKES_RE=project-custom|regex(with)[chars].*\n' > .claude/lib/_high-stakes.sh
printf 'y\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] \
  && grep -qF 'HIGH_STAKES_RE=project-custom|regex(with)[chars].*' .claude/lib/_high-stakes.sh \
  && grep -q "TOOLKIT_HS_BODY_V2" .claude/lib/_high-stakes.sh \
  && ! grep -q "PROJECT_HS_BODY_V1" .claude/lib/_high-stakes.sh \
  && grep -qi "merged" "$WORK/out"; } \
  && pass "mixed merge (_high-stakes.sh): project's HIGH_STAKES_RE value (regex metachars intact) survives, toolkit's body update lands" \
  || fail "mixed merge of _high-stakes.sh did not value-preserve + body-update correctly (rc=$rc)"

# 14 — hs_lib malformed: TWO HIGH_STAKES_RE= lines in the project's copy → manual review,
# byte-identical even when the merge is affirmatively confirmed ('y' piped).
mktoolkit
mkproject t14
mkdir -p .claude/lib
printf '#!/usr/bin/env bash\nHIGH_STAKES_RE=one\nHIGH_STAKES_RE=two\n' > .claude/lib/_high-stakes.sh
cp .claude/lib/_high-stakes.sh "$WORK/t14-before"
printf 'y\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && cmp -s .claude/lib/_high-stakes.sh "$WORK/t14-before" && grep -qi "manual review" "$WORK/out"; } \
  && pass "malformed _high-stakes.sh (2 HIGH_STAKES_RE lines) → manual review, byte-identical even with 'y' piped" \
  || fail "malformed _high-stakes.sh (dup lines) was merged/altered or not reported (rc=$rc)"

# 14b — hs_lib malformed: ZERO HIGH_STAKES_RE= lines in the project's copy → same fail-safe.
mktoolkit
mkproject t14b
mkdir -p .claude/lib
printf '#!/usr/bin/env bash\n# no HIGH_STAKES_RE at all\n' > .claude/lib/_high-stakes.sh
cp .claude/lib/_high-stakes.sh "$WORK/t14b-before"
printf 'y\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && cmp -s .claude/lib/_high-stakes.sh "$WORK/t14b-before" && grep -qi "manual review" "$WORK/out"; } \
  && pass "malformed _high-stakes.sh (0 HIGH_STAKES_RE lines) → manual review, byte-identical" \
  || fail "malformed _high-stakes.sh (0 lines) mishandled (rc=$rc)"

# 15 — agent normal merge: project's model: opus (customized) survives, toolkit's body update
# lands, and no duplicate model: line is introduced.
mktoolkit
mkproject t15
mkdir -p .claude/agents
cat > .claude/agents/evaluator.md <<'EOF'
---
name: evaluator
description: PROJECT_BODY_V1 evaluator
tools: Read, Glob, Grep, Bash
model: opus
---

Project evaluator body v1.
EOF
printf 'y\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] \
  && grep -q "^model: opus$" .claude/agents/evaluator.md \
  && grep -q "TOOLKIT_BODY_V2" .claude/agents/evaluator.md \
  && ! grep -q "PROJECT_BODY_V1" .claude/agents/evaluator.md \
  && [ "$(grep -c '^model:' .claude/agents/evaluator.md)" -eq 1 ]; } \
  && pass "mixed merge (agent model:): project's model: opus survives, toolkit's body update lands, no duplicate model: line" \
  || fail "agent model: merge did not value-preserve + body-update correctly (rc=$rc)"

# 16 — agent merge where the PROJECT has NO model: line (explicit inherit) and the toolkit's
# copy ships model: sonnet → after merge the project's "no model:" state must be preserved
# (the toolkit's model: line is REMOVED from the merged result, not silently kept).
mktoolkit
mkproject t16
mkdir -p .claude/agents
cat > .claude/agents/evaluator.md <<'EOF'
---
name: evaluator
description: PROJECT_BODY_V1 evaluator
tools: Read, Glob, Grep, Bash
---

Project evaluator body v1 (no model: line -- inherits session model).
EOF
printf 'y\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] \
  && ! grep -q "^model:" .claude/agents/evaluator.md \
  && grep -q "TOOLKIT_BODY_V2" .claude/agents/evaluator.md; } \
  && pass "agent model: merge preserves the PROJECT's absent-model: (inherit) state even though toolkit ships model: sonnet" \
  || fail "agent merge wrongly added a model: line the project didn't have (rc=$rc)"

# 17 — agent malformed: TWO model: lines in the project's copy → manual review, byte-identical.
mktoolkit
mkproject t17
mkdir -p .claude/agents
cat > .claude/agents/evaluator.md <<'EOF'
---
name: evaluator
model: opus
model: haiku
---

Project evaluator body (duplicated model: lines).
EOF
cp .claude/agents/evaluator.md "$WORK/t17-before"
printf 'y\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && cmp -s .claude/agents/evaluator.md "$WORK/t17-before" && grep -qi "manual review" "$WORK/out"; } \
  && pass "malformed agent file (2 model: lines) → manual review, byte-identical even with 'y' piped" \
  || fail "malformed agent file (dup model:) mishandled (rc=$rc)"

# 18 — rules_hs normal merge: project's paths: block (including its own comment line) survives
# verbatim, and the toolkit's body update (description + heading + prose) lands.
mktoolkit
mkproject t18
mkdir -p .claude/rules
cat > .claude/rules/high-stakes.md <<'EOF'
---
description: PROJECT_BODY_V1 rule
paths:
  # project comment
  - "**/project-custom-path/**"
  - "**/project-other-path/**"
---

# PROJECT_BODY_V1 heading
Project rule body v1.
EOF
printf 'y\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] \
  && grep -q "project-custom-path" .claude/rules/high-stakes.md \
  && grep -q "project-other-path" .claude/rules/high-stakes.md \
  && grep -q "project comment" .claude/rules/high-stakes.md \
  && grep -q "TOOLKIT_BODY_V2" .claude/rules/high-stakes.md \
  && ! grep -q "PROJECT_BODY_V1" .claude/rules/high-stakes.md \
  && ! grep -q "toolkit-v2-path" .claude/rules/high-stakes.md; } \
  && pass "mixed merge (rules/high-stakes.md): project's paths: block survives verbatim (incl. comment), toolkit's body update lands" \
  || fail "rules/high-stakes.md merge did not value-preserve + body-update correctly (rc=$rc)"

# 19 — rules_hs malformed: unclosed frontmatter (no second --- delimiter) → manual review,
# byte-identical.
mktoolkit
mkproject t19
mkdir -p .claude/rules
cat > .claude/rules/high-stakes.md <<'EOF'
---
description: broken rule
paths:
  - "**/x/**"

# no closing --- delimiter at all
EOF
cp .claude/rules/high-stakes.md "$WORK/t19-before"
printf 'y\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && cmp -s .claude/rules/high-stakes.md "$WORK/t19-before" && grep -qi "manual review" "$WORK/out"; } \
  && pass "malformed rules/high-stakes.md (unclosed frontmatter) → manual review, byte-identical" \
  || fail "malformed rules/high-stakes.md (unclosed) mishandled (rc=$rc)"

# 20 — rules_hs malformed: no paths: key at all in the project's copy → manual review,
# byte-identical.
mktoolkit
mkproject t20
mkdir -p .claude/rules
cat > .claude/rules/high-stakes.md <<'EOF'
---
description: rule with no paths key at all
---

# heading
body
EOF
cp .claude/rules/high-stakes.md "$WORK/t20-before"
printf 'y\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && cmp -s .claude/rules/high-stakes.md "$WORK/t20-before" && grep -qi "manual review" "$WORK/out"; } \
  && pass "malformed rules/high-stakes.md (no paths: key) → manual review, byte-identical" \
  || fail "malformed rules/high-stakes.md (missing paths:) mishandled (rc=$rc)"

# 21 — a mixed file IDENTICAL to the toolkit's copy is a no-op: --dry-run reports it "up to
# date" (the pre-existing cmp -s short-circuit, run BEFORE the tier switch), never a pending
# merge, and it is never counted as changed.
mktoolkit
mkproject t21
mkdir -p .claude/agents
cp "$TOOLKIT/.claude/agents/researcher.md" .claude/agents/researcher.md
rc=$(runsync --dry-run)
{ [ "$rc" -eq 0 ] \
  && grep -q "up to date: .claude/agents/researcher.md" "$WORK/out" \
  && ! grep -q "would merge: .claude/agents/researcher.md" "$WORK/out"; } \
  && pass "mixed file identical to toolkit is a no-op (dry-run reports up to date, not a pending merge)" \
  || fail "identical mixed file was wrongly treated as differing (rc=$rc)"

# 22 — --dry-run on a DIFFERING mixed file: shows the would-be merge but writes NOTHING —
# project file stays byte-identical AND .claude/.high-stakes-default is not (re)written.
mktoolkit
mkproject t22
mkdir -p .claude/lib
printf '#!/usr/bin/env bash\n# PROJECT_HS_BODY_V1\nHIGH_STAKES_RE=project-dry-run-value\n' > .claude/lib/_high-stakes.sh
cp .claude/lib/_high-stakes.sh "$WORK/t22-before"
rc=$(runsync --dry-run --yes)
{ [ "$rc" -eq 0 ] \
  && cmp -s .claude/lib/_high-stakes.sh "$WORK/t22-before" \
  && grep -qi "would merge: .claude/lib/_high-stakes.sh" "$WORK/out" \
  && [ ! -f .claude/.high-stakes-default ]; } \
  && pass "--dry-run on a differing mixed file previews the merge but writes nothing (incl. no .high-stakes-default write)" \
  || fail "--dry-run mixed handling wrote something it shouldn't have (rc=$rc)"

# 23 — --yes does NOT auto-apply a mixed merge: it still prompts, and an empty piped answer
# still declines (mirrors the overwrite-tier's own empty-answer-defaults-to-NO rule).
mktoolkit
mkproject t23
mkdir -p .claude/lib
printf '#!/usr/bin/env bash\n# PROJECT_HS_BODY_V1\nHIGH_STAKES_RE=project-noauto-value\n' > .claude/lib/_high-stakes.sh
cp .claude/lib/_high-stakes.sh "$WORK/t23-before"
printf '\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] \
  && cmp -s .claude/lib/_high-stakes.sh "$WORK/t23-before" \
  && grep -qi "skipped (declined mixed merge)" "$WORK/out"; } \
  && pass "--yes does not bypass a mixed merge's confirm prompt; empty answer still declines" \
  || fail "--yes wrongly auto-applied the mixed merge (rc=$rc)"

# 24 — after a successful REAL (non-dry-run) _high-stakes.sh merge, .claude/.high-stakes-default
# is refreshed to the TOOLKIT's new HIGH_STAKES_RE= line (the new shipped default), mirroring
# install.sh's own fingerprint write, so doctor.sh's drift check stays honest.
mktoolkit
mkproject t24
mkdir -p .claude/lib
printf '#!/usr/bin/env bash\n# PROJECT_HS_BODY_V1\nHIGH_STAKES_RE=project-refresh-value\n' > .claude/lib/_high-stakes.sh
printf 'y\n' | bash "$SYNC" --toolkit "$TOOLKIT" --yes >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] \
  && [ -f .claude/.high-stakes-default ] \
  && grep -q "HIGH_STAKES_RE=toolkit-default" .claude/.high-stakes-default \
  && ! grep -q "project-refresh-value" .claude/.high-stakes-default; } \
  && pass ".claude/.high-stakes-default refreshed to the TOOLKIT's new HIGH_STAKES_RE line after a real merge" \
  || fail ".high-stakes-default not refreshed correctly after mixed merge (rc=$rc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All sync.sh tests passed."; exit 0
else echo "$FAILS sync test(s) FAILED."; echo "--- last output ---"; tail -n 20 "$WORK/out" 2>/dev/null; exit 1; fi
