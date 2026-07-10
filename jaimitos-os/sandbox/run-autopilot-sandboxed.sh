#!/usr/bin/env bash
# run-autopilot-sandboxed.sh — the SUPPORTED way to run the headless autopilot unattended.
#
# The docs have always said "run --dangerously-skip-permissions only in a sandboxed container
# with no production credentials"; this wrapper IS that container. It:
#   • builds the sandbox image (sandbox/Dockerfile.autopilot) if it doesn't exist yet;
#   • mounts a CLEAN, TRACKED-ONLY CLONE of the repo (not the live working dir) — so a gitignored
#     or untracked `.env`, `*.pem`, `.netrc`, `secrets/`, cache tree, or a symlink to any of those
#     is PHYSICALLY ABSENT from the container (finding C1/N-3). The clone is built with
#     `git clone --local`, which copies only the committed object store and checks out HEAD, and
#     yields a SELF-CONTAINED `.git` so `git worktree add` works inside the container (a host
#     `git worktree add` would produce a broken `.git` pointer file);
#   • passes exactly ONE credential into the container: ANTHROPIC_API_KEY (env var). That is
#     the single allowed credential, by design — the loop needs it to call the API and nothing
#     else. NOTE: the agent inside the container necessarily HAS this key (it must, to call the
#     API); the sandbox's guarantee is "no OTHER credential and no ignored secret rides in", not
#     "the agent has no credentials at all";
#   • runs `scripts/autopilot.sh "$@" --dangerously-skip-permissions` inside;
#   • EXPORTS the loop's work back: the mounted clone is not the live repo, so any `autopilot/*`
#     branch the loop produces lives only in the clone. After the run this wrapper imports those
#     refs into your repo. If work was produced but cannot be imported (a non-fast-forward, or a
#     same-named branch already here), it FAILS CLOSED (non-zero) and PRESERVES the clone so the
#     work is never silently lost behind a warning (correction C-A).
#
# Refusals (fail-closed, before any container starts):
#   • docker missing                          → exit 2 with install guidance
#   • ANTHROPIC_API_KEY unset                 → exit 2
#   • clean staging clone cannot be built     → exit 3 (never fall back to mounting the live dir)
#   • secret-shaped TRACKED file in the clone → exit 3 (a committed secret rides into any checkout)
#
# Usage: bash sandbox/run-autopilot-sandboxed.sh <autopilot.sh args>
#        e.g. bash sandbox/run-autopilot-sandboxed.sh 3 --pr
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1
SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${JAIMITOS_SANDBOX_IMAGE:-jaimitos-autopilot}"

case "${1:-}" in
  -h|--help)
    echo "usage: run-autopilot-sandboxed.sh <autopilot.sh args>   (e.g. ... 3 --pr)"
    echo "  Builds the sandbox image if missing, mounts ONLY this repo, passes ONLY"
    echo "  ANTHROPIC_API_KEY, and runs scripts/autopilot.sh <args> --dangerously-skip-permissions"
    echo "  inside the container. Refuses if docker is missing, the key is unset, or the repo"
    echo "  contains secret-shaped files that would be mounted in."
    exit 0 ;;
esac

command -v docker >/dev/null 2>&1 || {
  echo "sandbox: ⛔ docker is required — install Docker (or Podman with a docker alias) first." >&2
  echo "sandbox:   Unattended --dangerously-skip-permissions runs are ONLY supported inside this container." >&2
  exit 2
}
[ -n "${ANTHROPIC_API_KEY:-}" ] || {
  echo "sandbox: ⛔ ANTHROPIC_API_KEY is not set — it is the single credential the container receives." >&2
  exit 2
}
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "sandbox: ⛔ not a git repo — autopilot needs one." >&2
  exit 2
}

# The scan lib is still required (fail closed if missing) — we use it to scan the CLONE's tracked
# files below, so a committed secret-shaped file is refused before it can be mounted.
SCAN_LIB=".claude/lib/_secret-scan.sh"
[ -f "$SCAN_LIB" ] || {
  echo "sandbox: ⛔ $SCAN_LIB missing — cannot scan the repo for secret-shaped files (fail-closed)." >&2
  echo "sandbox:   Restore it (re-run install.sh) and retry." >&2
  exit 2
}

# --- build a CLEAN, tracked-only staging clone (C1/N-3) ---
# `git clone --local` copies ONLY the committed object store and checks out HEAD. An ignored/untracked
# `.env`, a cache, or a symlink to an ignored secret simply does not exist in the clone — so nothing
# but committed, tracked content can ride into the container. It is a SELF-CONTAINED repo (real `.git`
# dir), so `git worktree add` inside the container works. Fail closed if the clean clone can't be built
# — never fall back to mounting the live working dir.
STAGE="$(mktemp -d 2>/dev/null || mktemp -d -t jaimitos-sbx)" || {
  echo "sandbox: ⛔ could not create a staging directory (fail-closed)." >&2; exit 3; }
PRESERVE_STAGE=0
cleanup_stage() { [ "$PRESERVE_STAGE" = "1" ] || rm -rf "$STAGE" 2>/dev/null || true; }
trap cleanup_stage EXIT
if ! git clone --local --no-hardlinks --quiet "$PWD" "$STAGE/repo" 2>"$STAGE/clone.err"; then
  echo "sandbox: ⛔ could not build a clean staging clone of this repo (fail-closed):" >&2
  sed 's/^/sandbox:   /' "$STAGE/clone.err" >&2 2>/dev/null || true
  exit 3
fi

# Belt-and-braces: scan the CLONE's tracked files. A gitignored/untracked secret can't be here (the
# clone excludes it), but a TRACKED secret-shaped file (a committed `.env`) can — and must not be
# mounted. This is the one secret vector the clone doesn't inherently close.
# shellcheck disable=SC1090
. "$SCAN_LIB"
HITS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  _secret_basename_match "$f" && HITS="${HITS}    $f"$'\n'
done < <( git -C "$STAGE/repo" ls-files 2>/dev/null )
if [ -n "$HITS" ]; then
  echo "sandbox: ⛔ secret-shaped TRACKED file(s) would be mounted into the container:" >&2
  printf '%s' "$HITS" >&2
  echo "sandbox:   A committed secret rides into ANY checkout. Remove it from the repo (git rm --cached" >&2
  echo "sandbox:   and rotate the credential), then retry." >&2
  exit 3
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "sandbox: building image '$IMAGE' from $SANDBOX_DIR/Dockerfile.autopilot ..."
  docker build -f "$SANDBOX_DIR/Dockerfile.autopilot" -t "$IMAGE" "$SANDBOX_DIR" || {
    echo "sandbox: ⛔ image build failed." >&2
    exit 1
  }
fi

# -i always (stdin for the loop); -t only when we actually have a TTY.
TTY_FLAG=""
[ -t 0 ] && [ -t 1 ] && TTY_FLAG="-t"
echo "sandbox: clean clone → /work (tracked files only; ignored/untracked excluded) · credential → ANTHROPIC_API_KEY · image → $IMAGE"
# NOT exec: we must run the export step after the container exits. TTY_FLAG is deliberately unquoted.
# shellcheck disable=SC2086
docker run --rm -i $TTY_FLAG \
  -v "$STAGE/repo":/work -w /work \
  -e ANTHROPIC_API_KEY \
  -e JAIMITOS_SANDBOXED=1 \
  "$IMAGE" scripts/autopilot.sh "$@" --dangerously-skip-permissions
run_rc=$?

# --- export the loop's work back, fail-closed (correction C-A) ---
# The mounted clone is not the live repo, so any autopilot/* branch the loop produced lives only in
# the clone. From here we assume work exists until proven otherwise, so an unexpected death preserves
# the clone rather than discarding uncommitted-back work.
PRESERVE_STAGE=1
git -C "$STAGE/repo" worktree prune >/dev/null 2>&1 || true
PRODUCED=$(git -C "$STAGE/repo" for-each-ref --format='%(refname:short)' 'refs/heads/autopilot/*' 2>/dev/null || true)
if [ -z "$PRODUCED" ]; then
  # No autopilot/* branch → the loop produced nothing to import → safe to discard the clone.
  PRESERVE_STAGE=0
  echo "sandbox: run finished (rc=$run_rc); no autopilot/* branch was produced — nothing to import."
  exit "$run_rc"
fi
# Work exists — import it into THIS repo. ALWAYS attempt, even after a container failure (rc!=0). Never
# force: a non-fast-forward or an existing same-name branch must be PRESERVED for the human to resolve,
# not clobbered.
if git fetch --no-tags "$STAGE/repo" 'refs/heads/autopilot/*:refs/heads/autopilot/*' 2>"$STAGE/fetch.err"; then
  PRESERVE_STAGE=0
  echo "sandbox: imported autopilot/* branch(es) into this repo:"
  printf '%s\n' "$PRODUCED" | sed 's/^/sandbox:   /'
  echo "sandbox: staging clone removed."
  exit "$run_rc"
fi
# Import failed and work exists → fail closed, keep the clone (PRESERVE_STAGE stays 1).
echo "sandbox: ⛔ the run produced autopilot/* work but it could NOT be imported into this repo:" >&2
sed 's/^/sandbox:   /' "$STAGE/fetch.err" >&2 2>/dev/null || true
echo "sandbox:   (Likely a non-fast-forward, or a branch of the same name already exists here.)" >&2
echo "sandbox:   Your work is PRESERVED in the staging clone — recover it, then remove the clone:" >&2
echo "sandbox:     git fetch \"$STAGE/repo\" 'refs/heads/autopilot/*:refs/heads/autopilot/*'" >&2
echo "sandbox:     # resolve the conflict (rename/merge), then:  rm -rf \"$STAGE\"" >&2
exit 4
