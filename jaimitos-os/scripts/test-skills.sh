#!/usr/bin/env bash
# test-skills.sh — objective, mechanical checks on the skill pack. Shape only, never judgement:
# this suite can prove a skill's frontmatter is valid, that it is registered, that it isn't shipped
# when it must not be, and what it costs in always-loaded context. It CANNOT prove the skill was
# worth adding — that stays a human call (see docs/dev/AUTHORING.md).
#
# Fails ONLY on objective violations. Heuristic concerns are printed as warnings and never fail CI.
#
#   1. frontmatter: name present, name == directory, description present
#   2. no duplicate skill names; no collision with a command or an agent name
#   3. catalog <-> directory: every skills/*/ has a row in skills/README.md, and vice versa
#   4. maintainer-only skills (repo-root .claude/skills/) are structurally unshippable
#   5. provenance: integrations/upstreams.lock.json is valid, complete, and its paths exist
#   6. context budget: model-invoked descriptions are the always-loaded cost — cap each and the sum
#   7. attribution: every skill the lockfile says was influenced carries an attribution comment
#   8. local markdown references inside a skill resolve
#
# Runs from the wrapper repo. Inside an installed project there is no skills/ source root, so it
# degrades to a no-op pass (install-smoke owns the post-install checks there).
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$SCAFFOLD/.." && pwd)"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
warn() { printf '  ! %s\n' "$1"; }

echo "skill-pack checks"; echo ""

if [ ! -d "$ROOT/skills" ] || [ ! -f "$ROOT/skills/README.md" ]; then
  echo "  - SKIPPED: no wrapper repo around this scaffold (installed project) — nothing to check."
  exit 0
fi

# Read one frontmatter field from a SKILL.md (between the first two '---' fences). Bash 3.2 safe.
fm() {
  awk -v k="$2" '
    /^---[[:space:]]*$/ { fence++; if (fence == 2) exit; next }
    fence == 1 && index($0, k ":") == 1 { sub("^" k ":[[:space:]]*", ""); print; exit }
  ' "$1"
}

# Every skill in the SHIPPED source root, plus the MAINTAINER-ONLY root .claude/skills/.
SHIPPED_DIRS=$(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d | sort)
MAINT_DIRS=$(find "$ROOT/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

# --- 1/2 — frontmatter, name==dir, uniqueness, collisions -------------------------------------
NAMES=""; DUPES=""; BAD_FM=""
for d in $SHIPPED_DIRS $MAINT_DIRS; do
  sk="$(basename "$d")"; s="$d/SKILL.md"
  [ -f "$s" ] || { BAD_FM="$BAD_FM $sk(no-SKILL.md)"; continue; }
  n="$(fm "$s" name)"; desc="$(fm "$s" description)"
  [ -n "$n" ]     || BAD_FM="$BAD_FM $sk(no-name)"
  [ -n "$desc" ]  || BAD_FM="$BAD_FM $sk(no-description)"
  [ "$n" = "$sk" ] || [ -z "$n" ] || BAD_FM="$BAD_FM $sk(name:'$n'!=dir)"
  case " $NAMES " in *" $sk "*) DUPES="$DUPES $sk" ;; esac
  NAMES="$NAMES $sk"
done
[ -z "$BAD_FM" ] && pass "every SKILL.md has name + description, and name matches its directory" \
                 || fail "frontmatter problems:$BAD_FM"
[ -z "$DUPES" ]  && pass "no duplicate skill names across shipped + maintainer skills" \
                 || fail "duplicate skill names:$DUPES"

CMDS=$(find "$SCAFFOLD/.claude/commands" -name '*.md' -exec basename {} .md \; 2>/dev/null | sort)
AGENTS=$(find "$SCAFFOLD/.claude/agents" -name '*.md' -exec basename {} .md \; 2>/dev/null | sort)
COLL=""
for sk in $NAMES; do
  case " $CMDS "   in *" $sk "*) COLL="$COLL $sk(command)" ;; esac
  case " $AGENTS " in *" $sk "*) COLL="$COLL $sk(agent)" ;; esac
done
[ -z "$COLL" ] && pass "no skill name collides with a command or an agent name" \
               || fail "name collisions:$COLL"

# --- 3 — catalog <-> directory ----------------------------------------------------------------
# The invariant that did not exist before v2.10.0: a skill could ship while being absent from the
# catalog (or linger in the catalog after deletion) and nothing noticed.
CAT="$ROOT/skills/README.md"
MISSING_ROW=""; ORPHAN_ROW=""
for d in $SHIPPED_DIRS; do
  sk="$(basename "$d")"
  grep -qE "^\| \*\*\`?${sk}\`?\*\*" "$CAT" || grep -qE "\*\*${sk}\*\*" "$CAT" \
    || MISSING_ROW="$MISSING_ROW $sk"
done
# Every bolded name in the catalog table must be a real shipped skill dir.
while IFS= read -r row; do
  [ -n "$row" ] || continue
  [ -d "$ROOT/skills/$row" ] || ORPHAN_ROW="$ORPHAN_ROW $row"
done < <(grep -oE '^\| \*\*[a-z0-9-]+\*\*' "$CAT" 2>/dev/null | sed -e 's/^| \*\*//' -e 's/\*\*$//')
[ -z "$MISSING_ROW" ] && pass "every shipped skill has a catalog row in skills/README.md" \
                      || fail "skill(s) missing from the catalog:$MISSING_ROW"
[ -z "$ORPHAN_ROW" ]  && pass "every catalog row maps to a real skills/ directory" \
                      || fail "catalog row(s) with no directory:$ORPHAN_ROW"

# --- 4 — maintainer-only skills are structurally unshippable -----------------------------------
# The guarantee is STRUCTURAL, not a list: install.sh reads exactly two source roots. If either of
# those ever grows to include the repo-root .claude/, the maintainer skills start shipping — so we
# assert the source roots themselves, not an exclusion list that could silently drift.
SRC_ROOTS=$(grep -cE '^(SCAFFOLD|SKILLS_SRC)="\$SRC/(jaimitos-os|skills)"$' "$ROOT/install.sh")
if [ "$SRC_ROOTS" = "2" ] && ! grep -qE '^\s*(SCAFFOLD|SKILLS_SRC)=.*\.claude' "$ROOT/install.sh"; then
  pass "install.sh reads only jaimitos-os/ + skills/ — repo-root .claude/skills/ cannot be installed"
else
  fail "install.sh's source roots changed — maintainer-only skills may now be shippable"
fi
if [ -n "$MAINT_DIRS" ]; then
  LEAK=""
  for d in $MAINT_DIRS; do
    mk="$(basename "$d")"
    [ -d "$ROOT/skills/$mk" ] && LEAK="$LEAK $mk"
    # A maintainer skill must never auto-fire: it is invoked by name, deliberately.
    grep -qE '^disable-model-invocation:[[:space:]]*true' "$d/SKILL.md" \
      || fail "maintainer skill '$mk' lacks 'disable-model-invocation: true' (it would auto-fire and cost context)"
  done
  [ -z "$LEAK" ] && pass "no maintainer-only skill is duplicated into the shipped skills/ root" \
                 || fail "maintainer skill(s) also present in shipped skills/:$LEAK"
else
  warn "no repo-root .claude/skills/ found — maintainer tooling absent?"
fi

# --- 5 — provenance ----------------------------------------------------------------------------
LOCK="$ROOT/integrations/upstreams.lock.json"
if [ ! -f "$LOCK" ]; then
  fail "missing integrations/upstreams.lock.json (provenance for adopted upstream work)"
elif ! command -v jq >/dev/null 2>&1; then
  warn "jq not installed — skipping provenance schema check"
else
  if jq -e . "$LOCK" >/dev/null 2>&1; then
    MISSING_KEYS=$(jq -r '
      [.upstreams[] | select(
        (has("repo") and has("sha") and has("license") and has("paths_consulted")
         and has("jaimitos_files_influenced") and has("inspected") and has("adoption")
         and has("deviations")) | not
      ) | .repo // "?"] | join(" ")' "$LOCK")
    [ -z "$MISSING_KEYS" ] && pass "upstreams.lock.json: every entry has the required provenance keys" \
                           || fail "upstreams.lock.json entries missing required keys: $MISSING_KEYS"
    BAD_ADOPT=$(jq -r '[.upstreams[] | select(.adoption | IN("copied","adapted","merged","concept-only") | not) | .repo] | join(" ")' "$LOCK")
    [ -z "$BAD_ADOPT" ] && pass "upstreams.lock.json: every adoption type is one of copied/adapted/merged/concept-only" \
                        || fail "invalid adoption type: $BAD_ADOPT"
    GONE=""
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      [ -e "$ROOT/$p" ] || GONE="$GONE $p"
    done < <(jq -r '.upstreams[].jaimitos_files_influenced[]' "$LOCK" 2>/dev/null)
    [ -z "$GONE" ] && pass "every jaimitos_files_influenced path in the lockfile still exists" \
                   || fail "lockfile references files that no longer exist:$GONE"
  else
    fail "integrations/upstreams.lock.json is not valid JSON"
  fi
fi

# --- 6 — context budget ------------------------------------------------------------------------
# A model-invoked skill's description sits in the window EVERY TURN. A user-invoked skill
# (disable-model-invocation: true) costs zero. This is the only always-loaded cost the skill pack
# adds, so it is bounded here rather than left to drift.
DESC_CAP=500          # per model-invoked description, bytes
TOTAL_CAP=6000        # sum of all model-invoked descriptions, bytes
SUM=0; OVER=""
for d in $SHIPPED_DIRS; do
  sk="$(basename "$d")"; s="$d/SKILL.md"
  [ -f "$s" ] || continue
  grep -qE '^disable-model-invocation:[[:space:]]*true' "$s" && continue   # zero always-loaded cost
  b=$(fm "$s" description | wc -c | tr -d ' ')
  SUM=$((SUM + b))
  [ "$b" -gt "$DESC_CAP" ] && OVER="$OVER $sk(${b}B)"
done
[ -z "$OVER" ] && pass "every model-invoked description is within ${DESC_CAP}B" \
               || fail "description(s) over the ${DESC_CAP}B always-loaded cap:$OVER"
if [ "$SUM" -le "$TOTAL_CAP" ]; then
  pass "model-invoked description budget: ${SUM}B / ${TOTAL_CAP}B (~$((SUM / 4)) tokens, loaded every turn)"
else
  fail "model-invoked description budget blown: ${SUM}B > ${TOTAL_CAP}B — make a skill user-invoked, don't make descriptions vague"
fi

# --- 7 — attribution ---------------------------------------------------------------------------
if [ -f "$LOCK" ] && command -v jq >/dev/null 2>&1; then
  NOATTR=""
  while IFS= read -r p; do
    case "$p" in skills/*/SKILL.md) ;; *) continue ;; esac
    [ -f "$ROOT/$p" ] || continue
    grep -qE '<!-- Adapted from (mattpocock/skills|obra/superpowers) \(MIT\)' "$ROOT/$p" \
      || NOATTR="$NOATTR $p"
  done < <(jq -r '.upstreams[].jaimitos_files_influenced[]' "$LOCK" 2>/dev/null | sort -u)
  [ -z "$NOATTR" ] && pass "every upstream-influenced skill carries its MIT attribution comment" \
                   || fail "upstream-influenced skill(s) missing attribution:$NOATTR"
fi

# --- 8 — local markdown references resolve -----------------------------------------------------
BADREF=""
for d in $SHIPPED_DIRS $MAINT_DIRS; do
  for f in "$d"/*.md; do
    [ -f "$f" ] || continue
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      [ -e "$d/$ref" ] || BADREF="$BADREF $(basename "$d")/$ref"
    done < <(grep -oE '\]\([A-Za-z0-9._-]+\.md\)' "$f" 2>/dev/null | sed -e 's/^](//' -e 's/)$//')
  done
done
[ -z "$BADREF" ] && pass "every local .md reference inside a skill resolves" \
                 || fail "broken local reference(s):$BADREF"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All skill-pack checks passed."; exit 0
else echo "$FAILS skill-pack check(s) FAILED."; exit 1; fi
