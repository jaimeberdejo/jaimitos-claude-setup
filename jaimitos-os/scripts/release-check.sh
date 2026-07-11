#!/usr/bin/env bash
# release-check.sh — VERSION ↔ CHANGELOG ↔ git-tag consistency check (audit 6.10 / F7). Creates NO tags
# and pushes nothing — it only REPORTS. Two modes:
#   --prepare  (default) run BEFORE creating a tag: VERSION == newest CHANGELOG release, [Unreleased]
#              empty, working tree clean; the v$VERSION tag is EXPECTED to be absent (not an error yet).
#   --released run AFTER tagging/pushing: an ANNOTATED v$VERSION tag exists AND points at a commit whose
#              VERSION + newest CHANGELOG both equal $VERSION (catches a tag on the WRONG commit — the
#              old check only proved the tag NAME existed); reports master↔tag; verifies the REMOTE tag
#              when an origin remote is configured.
# Historical misses BEFORE the grandfather floor (2.8.0) are a WARNING, not a failure. Exit 0 =
# consistent (warnings allowed); 1 = a blocking inconsistency.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1
ROOT="."; [ -f VERSION ] || ROOT=".."
VER_FILE="$ROOT/VERSION"; CHANGELOG="$ROOT/CHANGELOG.md"
GRANDFATHER_FLOOR="2.8.0"

MODE="prepare"
for a in "$@"; do case "$a" in
  -h|--help) echo "usage: release-check.sh [--prepare|--released]   (reports VERSION/CHANGELOG/tag consistency; creates nothing)"; exit 0 ;;
  --prepare)  MODE="prepare" ;;
  --released) MODE="released" ;;
  *) echo "release-check: unknown argument '$a' (try --prepare|--released)" >&2; exit 2 ;;
esac; done

WARN=0; ERR=0
warn() { echo "release-check: ! $1" >&2; WARN=$((WARN+1)); }
err()  { echo "release-check: ⛔ $1" >&2; ERR=$((ERR+1)); }
ok()   { echo "release-check: ✓ $1"; }

[ -f "$VER_FILE" ]  || { err "no VERSION file"; exit 1; }
[ -f "$CHANGELOG" ] || { err "no CHANGELOG.md"; exit 1; }
VERSION=$(tr -d '[:space:]' < "$VER_FILE")
[ -n "$VERSION" ] || { err "VERSION is empty"; exit 1; }

# ver_lt A B : 0 (true) if A < B by dotted numeric compare (bash 3.2 / BSD safe, no sort -V).
ver_lt() {
  local a="$1" b="$2" IFS=.
  # shellcheck disable=SC2206
  local ax=($a) bx=($b) i
  for i in 0 1 2; do
    local an=${ax[i]:-0} bn=${bx[i]:-0}
    [ "$an" -lt "$bn" ] 2>/dev/null && return 0
    [ "$an" -gt "$bn" ] 2>/dev/null && return 1
  done
  return 1
}

echo "release-check: mode = $MODE   VERSION = $VERSION   HEAD = $(git rev-parse --short HEAD 2>/dev/null)   branch = $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

# (1) VERSION == newest released (non-[Unreleased]) heading.
NEWEST=$(grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | head -1 | sed -E 's/^## \[([0-9.]+)\].*/\1/')
if [ "$NEWEST" = "$VERSION" ]; then ok "VERSION ($VERSION) == newest CHANGELOG release"
else err "VERSION ($VERSION) != newest CHANGELOG release ($NEWEST)"; fi

# (2) [Unreleased] should be empty at release time.
UNREL=$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f' "$CHANGELOG" | grep -vE '^[[:space:]]*(_.*_)?[[:space:]]*$' | grep -c .)
if [ "${UNREL:-0}" -gt 0 ]; then warn "[Unreleased] section is non-empty ($UNREL lines) — promote it into the version heading before tagging"
else ok "[Unreleased] is empty (or a placeholder)"; fi

TAG="v$VERSION"
TAG_EXISTS=0; git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 && TAG_EXISTS=1

if [ "$MODE" = prepare ]; then
  # (3p) working tree clean, so the tag will capture exactly what was reviewed.
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then err "working tree is not clean — commit/stash before tagging so the tag captures the reviewed state"
  else ok "working tree is clean"; fi
  # (4p) the current tag is EXPECTED to be absent at prepare time (it's created after this check passes).
  if [ "$TAG_EXISTS" = 1 ]; then warn "$TAG already exists — this is prepare mode (the release isn't tagged yet); use --released to verify an existing tag"
  else ok "$TAG not yet created (expected in prepare mode) — HEAD $(git rev-parse --short HEAD) is the release commit"; fi
else
  # --released: (3r) the tag must exist, be ANNOTATED, and point at a commit whose VERSION + newest
  # CHANGELOG both equal $VERSION (a tag on the WRONG commit must fail — the core F7 gap).
  if [ "$TAG_EXISTS" != 1 ]; then err "$TAG does not exist — cannot verify a released version without its tag"
  else
    ok "$TAG exists"
    [ "$(git cat-file -t "$TAG" 2>/dev/null)" = tag ] && ok "$TAG is an annotated tag" || warn "$TAG is a LIGHTWEIGHT tag (annotated tags are recommended for releases)"
    t_ver=$(git show "$TAG:VERSION" 2>/dev/null | tr -d '[:space:]')
    t_new=$(git show "$TAG:CHANGELOG.md" 2>/dev/null | grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' | head -1 | sed -E 's/^## \[([0-9.]+)\].*/\1/')
    if [ "$t_ver" = "$VERSION" ] && [ "$t_new" = "$VERSION" ]; then ok "$TAG points at a commit whose VERSION ($t_ver) and newest CHANGELOG ($t_new) both == $VERSION"
    else err "$TAG points at the WRONG commit: its VERSION='$t_ver', newest CHANGELOG='$t_new' (expected $VERSION) — the tag does not capture this release"; fi
    # report master↔tag relationship (informational).
    tc=$(git rev-list -n1 "$TAG" 2>/dev/null); hc=$(git rev-parse HEAD 2>/dev/null)
    if [ "$tc" = "$hc" ]; then ok "HEAD is exactly the tagged commit"
    elif git merge-base --is-ancestor "$tc" "$hc" 2>/dev/null; then warn "HEAD is AHEAD of $TAG by $(git rev-list --count "$TAG"..HEAD 2>/dev/null) commit(s) — the current tree is not the tagged release"
    else warn "HEAD and $TAG have diverged"; fi
    # (4r) remote tag verification, ONLY when an origin remote exists (never mandatory for local dev).
    if git remote get-url origin >/dev/null 2>&1; then
      if git ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null | grep -q "refs/tags/$TAG"; then ok "$TAG is present on origin (pushed)"
      else warn "$TAG exists locally but NOT on origin — push it (git push origin $TAG) so the release is public"; fi
    else ok "no origin remote configured — skipping remote-tag check (local-only)"; fi
  fi
fi

# Every released heading >= floor must have a tag; below floor → warn (grandfathered). (Both modes.)
MISS_ERR=""; MISS_WARN=""
while IFS= read -r v; do
  [ -n "$v" ] || continue
  { [ "$v" = "$VERSION" ] && [ "$MODE" = prepare ]; } && continue   # current release expected untagged only in prepare
  git rev-parse -q --verify "refs/tags/v$v" >/dev/null 2>&1 && continue
  if ver_lt "$v" "$GRANDFATHER_FLOOR"; then MISS_WARN="$MISS_WARN v$v"; else MISS_ERR="$MISS_ERR v$v"; fi
done < <(grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | sed -E 's/^## \[([0-9.]+)\].*/\1/')
[ -n "$MISS_WARN" ] && warn "untagged historical releases (grandfathered, will not retro-tag):$MISS_WARN"
[ -n "$MISS_ERR" ]  && err  "untagged releases at/after $GRANDFATHER_FLOOR (must be tagged):$MISS_ERR"
[ -z "$MISS_ERR" ] && ok "no untagged releases at/after the $GRANDFATHER_FLOOR floor"

echo "release-check: $WARN warning(s), $ERR error(s)."
[ "$ERR" -eq 0 ] || exit 1
exit 0
