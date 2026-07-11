#!/usr/bin/env bash
# test-release-check.sh — scripts/release-check.sh --prepare/--released consistency checks (finding F7).
# Builds throwaway toolkit-shaped repos (VERSION + CHANGELOG.md at root, scripts/release-check.sh) and
# asserts: prepare passes on a clean tree and fails on a dirty one; released fails on a WRONG-commit tag
# or a missing tag, warns on a lightweight tag, and passes on a correct annotated tag.
set -uo pipefail
RC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release-check.sh"
[ -f "$RC" ] || { echo "test: missing $RC" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }
FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# mkrel <name> <version>: a repo with VERSION + a CHANGELOG whose newest release == <version>.
mkrel() {
  local d="$W/$1" v="$2"; rm -rf "$d"; mkdir -p "$d/scripts"
  cp "$RC" "$d/scripts/release-check.sh"
  printf '%s\n' "$v" > "$d/VERSION"
  printf '# Changelog\n\n## [Unreleased]\n\n_Nothing yet._\n\n## [%s] — 2026-01-01\n\n- stuff\n' "$v" > "$d/CHANGELOG.md"
  ( cd "$d" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm "release $v" )
  REPO="$d"
}
run() { ( cd "$REPO" && bash scripts/release-check.sh "$@" ) >"$W/out" 2>&1; echo $?; }

echo "release-check tests"; echo ""

# 1 — prepare on a clean tree with the correct VERSION/CHANGELOG and no tag → pass (exit 0).
mkrel r1 2.9.0; rc=$(run --prepare)
{ [ "$rc" = 0 ] && grep -q 'working tree is clean' "$W/out" && grep -q 'not yet created' "$W/out"; } \
  && pass "prepare: clean tree, correct VERSION, no tag → exit 0" || fail "prepare-clean (rc=$rc)"

# 2 — prepare with a dirty tree → error (exit 1).
mkrel r2 2.9.0; echo dirty > "$REPO/uncommitted.txt"; rc=$(run --prepare)
{ [ "$rc" = 1 ] && grep -qi 'not clean' "$W/out"; } && pass "prepare: dirty tree → error" || fail "prepare-dirty (rc=$rc)"

# 3 — released with a correct ANNOTATED tag on the release commit → pass.
mkrel r3 2.9.0; git -C "$REPO" tag -a v2.9.0 -m 'v2.9.0'; rc=$(run --released)
{ [ "$rc" = 0 ] && grep -q 'is an annotated tag' "$W/out" && grep -q 'both == 2.9.0' "$W/out"; } \
  && pass "released: annotated tag on the correct commit → exit 0" || fail "released-correct (rc=$rc): $(tail -3 "$W/out")"

# 4 — released with a tag on the WRONG commit (VERSION there != 2.9.0) → error (the core F7 gap).
mkrel r4 2.9.0
git -C "$REPO" tag -a v2.9.0 -m 'v2.9.0'                      # tag the release commit first
printf '2.9.0\n' > "$REPO/VERSION"                           # keep working VERSION 2.9.0
# make a commit whose VERSION differs, MOVE the tag onto it, then restore VERSION to 2.9.0.
( cd "$REPO" && printf '2.8.0\n' > VERSION && git commit -qam 'wrong version commit' \
    && git tag -f v2.9.0 "$(git rev-parse HEAD)" && printf '2.9.0\n' > VERSION && git commit -qam 'back to 2.9.0' )
rc=$(run --released)
{ [ "$rc" = 1 ] && grep -qi 'WRONG commit' "$W/out"; } \
  && pass "released: tag on the WRONG commit (VERSION mismatch) → error (F7 core)" || fail "released-wrong-commit (rc=$rc): $(tail -3 "$W/out")"

# 5 — released with NO tag → error.
mkrel r5 2.9.0; rc=$(run --released)
{ [ "$rc" = 1 ] && grep -qi 'does not exist' "$W/out"; } && pass "released: missing tag → error" || fail "released-no-tag (rc=$rc)"

# 6 — released with a LIGHTWEIGHT tag on the correct commit → warns (annotated recommended).
mkrel r6 2.9.0; git -C "$REPO" tag v2.9.0; rc=$(run --released)
grep -qi 'LIGHTWEIGHT tag' "$W/out" && pass "released: lightweight tag → annotated-recommended warning" || fail "released-lightweight (rc=$rc): $(tail -2 "$W/out")"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All release-check tests passed."; exit 0
else echo "$FAILS release-check test(s) FAILED."; exit 1; fi
