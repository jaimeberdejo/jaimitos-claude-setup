#!/usr/bin/env bash
# test-sandbox.sh — sandbox/run-autopilot-sandboxed.sh must fail CLOSED before any container
# starts: no docker → clear refusal; no ANTHROPIC_API_KEY → refusal; secret-shaped files that
# would ride into the mount → refusal (reusing _secret-scan.sh's filename rules); missing scan
# lib → refusal. On a clean repo it must invoke docker with ONLY the repo mounted, ONLY
# ANTHROPIC_API_KEY passed, and --dangerously-skip-permissions appended INSIDE the container.
# No real docker is ever used — a stub records the invocation. Also lints the Dockerfile
# (hadolint when available, structural checks otherwise).
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$SCAFFOLD/sandbox/run-autopilot-sandboxed.sh"
DOCKERFILE="$SCAFFOLD/sandbox/Dockerfile.autopilot"
[ -f "$WRAPPER" ] || { echo "test: missing $WRAPPER" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-sbx)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# Stub docker: records `docker run` args, honors an env switch for `image inspect`. On `run` it also
# (a) records what is physically present in the mounted `-v SRC:/work` source — the isolation proof,
# no real docker needed — and (b) can simulate the loop producing an autopilot/* branch commit in the
# mounted clone (STUB_MAKE_REF=1) and a chosen container exit code (STUB_RUN_RC), to drive the export
# path. Everything the stub reads is a real git repo on disk (the clone the wrapper just built).
mkdir -p "$WORK/bin"
cat > "$WORK/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  image) [ "${STUB_IMAGE_EXISTS:-1}" = "1" ] && exit 0 || exit 1 ;;
  build) printf '%s\n' "$@" > "${STUB_LOG:-/dev/null}.build"; exit 0 ;;
  run)
    shift
    printf '%s\n' "$@" > "${STUB_LOG:-/dev/null}"
    # Extract the -v SRC:/work mount source.
    src=""; prev=""
    for a in "$@"; do
      case "$prev" in -v) src="${a%:/work}" ;; esac
      prev="$a"
    done
    if [ -n "${STUB_MOUNT_LS:-}" ] && [ -n "$src" ]; then
      {
        echo "=== files ==="
        find "$src" \( -type f -o -type l \) -not -path '*/.git/*' 2>/dev/null | while IFS= read -r p; do printf '%s\n' "${p#"$src"/}"; done
        echo "=== readable ==="   # a dangling symlink (target absent) fails -e, so it is NOT listed here
        find "$src" \( -type f -o -type l \) -not -path '*/.git/*' 2>/dev/null | while IFS= read -r p; do [ -e "$p" ] && printf '%s\n' "${p#"$src"/}"; done
      } > "$STUB_MOUNT_LS"
    fi
    if [ "${STUB_MAKE_REF:-0}" = "1" ] && [ -d "$src/.git" ]; then
      # Simulate the loop producing an autopilot/* branch commit. If the branch already exists in the
      # clone (it existed on the host and the clone inherited it), reset to its parent first so our
      # commit DIVERGES from the host's — a genuine non-fast-forward for the export-conflict test.
      if git -C "$src" show-ref --verify -q refs/heads/autopilot/teststamp; then
        base=$(git -C "$src" rev-parse autopilot/teststamp~1 2>/dev/null || git -C "$src" rev-parse HEAD)
        git -C "$src" checkout -q -B autopilot/teststamp "$base" 2>/dev/null
      else
        git -C "$src" checkout -q -b autopilot/teststamp 2>/dev/null
      fi
      echo "container work $$" > "$src/container-work.txt"
      git -C "$src" add -A 2>/dev/null
      git -C "$src" -c user.email=c@c.c -c user.name=c commit -q -m "autopilot container commit" 2>/dev/null
    fi
    # F2 loss-of-work fixtures: work produced OFF the autopilot/* channel that the exporter must NOT
    # discard. STUB_MAKE_CURRENT commits on the clone's current branch (the --no-worktree hazard);
    # STUB_MAKE_DETACHED commits on a detached HEAD; STUB_MAKE_DIRTY/UNTRACKED leave uncommitted work.
    if [ "${STUB_MAKE_CURRENT:-0}" = "1" ] && [ -d "$src/.git" ]; then
      echo "work on the current branch" > "$src/on-current-branch.txt"
      git -C "$src" add -A 2>/dev/null
      git -C "$src" -c user.email=c@c.c -c user.name=c commit -q -m "commit on current branch" 2>/dev/null
    fi
    if [ "${STUB_MAKE_DETACHED:-0}" = "1" ] && [ -d "$src/.git" ]; then
      git -C "$src" checkout -q --detach 2>/dev/null
      echo "detached work" > "$src/detached-work.txt"
      git -C "$src" add -A 2>/dev/null
      git -C "$src" -c user.email=c@c.c -c user.name=c commit -q -m "detached-HEAD commit" 2>/dev/null
    fi
    if [ "${STUB_MAKE_DIRTY:-0}" = "1" ] && [ -d "$src/.git" ]; then
      printf '\n# uncommitted change\n' >> "$src/scripts/autopilot.sh"   # modify a tracked file
    fi
    if [ "${STUB_MAKE_UNTRACKED:-0}" = "1" ]; then
      echo "untracked artifact" > "$src/untracked-artifact.txt"
    fi
    exit "${STUB_RUN_RC:-0}" ;;
  *)     exit 0 ;;
esac
EOF
chmod +x "$WORK/bin/docker"

# Stub `claude` too: the autopilot sandbox-gate tests below run the REAL autopilot.sh, whose preflight
# refuses to start without `claude` on PATH — and CI intentionally has no `claude`. The bare-host banner
# (test 9) is emitted only once a real run proceeds PAST that preflight, so without a stub the banner
# path is unreachable claude-less. doctor/autopilot don't execute it, only `command -v claude` it.
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/claude"; chmod +x "$WORK/bin/claude"
export PATH="$WORK/bin:$PATH"

# mkrepo: throwaway git repo with the scan lib in place, WITH an initial commit (the wrapper now
# builds a `git clone --local` staging copy, which needs committed objects). cd's the shell into it.
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO/.claude/lib" "$REPO/scripts"
  cp "$SCAFFOLD/.claude/lib/_secret-scan.sh" "$REPO/.claude/lib/_secret-scan.sh"
  printf '#!/usr/bin/env bash\necho fake autopilot\n' > "$REPO/scripts/autopilot.sh"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A && git commit -q -m init )
  cd "$REPO" || exit 1
}

run_wrapper() {  # run_wrapper [env VAR=..] -- <args...>; stub docker on PATH, output to $WORK/out
  PATH="$WORK/bin:$PATH" STUB_LOG="$WORK/docker-args" ANTHROPIC_API_KEY="${KEY_OVERRIDE-test-key}" \
    bash "$WRAPPER" "$@" >"$WORK/out" 2>&1
  echo $?
}

echo "sandbox wrapper tests"; echo ""

# 1 — no docker anywhere on PATH → refuses with guidance, exit 2, before touching anything.
# (bash resolved to an absolute path FIRST — the emptied PATH must starve the wrapper of
# docker, not starve this test of bash itself.)
mkrepo t1
BASH_BIN="$(command -v bash)"
PATH=/nonexistent-path-for-test "$BASH_BIN" "$WRAPPER" 1 >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 2 ] && grep -qi "docker is required" "$WORK/out"; } \
  && pass "no docker on PATH → clean refusal (exit 2) with install guidance" \
  || fail "missing docker not refused cleanly (rc=$rc)"

# 2 — ANTHROPIC_API_KEY unset → refusal, exit 2.
mkrepo t2
rc=$(KEY_OVERRIDE="" run_wrapper 1)
{ [ "$rc" -eq 2 ] && grep -q "ANTHROPIC_API_KEY" "$WORK/out"; } \
  && pass "unset ANTHROPIC_API_KEY → refusal naming the missing credential" \
  || fail "missing API key not refused (rc=$rc)"

# 3 (C1) — an UNTRACKED, non-gitignored .env is PHYSICALLY ABSENT from the mounted clone (the clone
# is tracked-only), so it can no longer ride into the container. The wrapper proceeds; the mount ls
# proves .env is not there. (Old behavior refused; the new behavior is stronger — the secret simply
# isn't present.)
mkrepo t3
printf 'SECRET=1\n' > .env                 # untracked, uncommitted
rm -f "$WORK/docker-args" "$WORK/mount-ls"
rc=$(STUB_MOUNT_LS="$WORK/mount-ls" run_wrapper 1)
{ [ "$rc" -eq 0 ] && [ -f "$WORK/mount-ls" ] && ! grep -q '\.env' "$WORK/mount-ls"; } \
  && pass "untracked .env → ABSENT from the mounted clone (not blocked, not present)" \
  || fail "untracked .env leaked into the mount or wrapper refused (rc=$rc); mount: $(cat "$WORK/mount-ls" 2>/dev/null | tr '\n' ' ')"

# 3b (C1) — a GITIGNORED .env is likewise absent from the clone (the vector the audit called out:
# gitignoring used to REMOVE it from the scan while it still rode into the mount — now it's gone).
mkrepo t3b
printf 'SECRET=1\n' > .env; printf '.env\n' > .gitignore
( git add .gitignore && git commit -q -m 'ignore .env' )   # commit the ignore rule; .env stays untracked
rm -f "$WORK/mount-ls"
rc=$(STUB_MOUNT_LS="$WORK/mount-ls" run_wrapper 1)
{ [ "$rc" -eq 0 ] && ! grep -q '\.env' "$WORK/mount-ls"; } \
  && pass "gitignored .env → ABSENT from the mounted clone (adding it to .gitignore no longer 'hides' a mounted secret)" \
  || fail "gitignored .env present in the mount (rc=$rc)"

# 3c (C1) — a TRACKED (committed) secret-shaped file WOULD be in the clone → refuse (exit 3), named,
# container never started. This is the one vector the clone doesn't inherently close.
mkrepo t3c
printf 'SECRET=1\n' > .env; ( git add -f .env && git commit -q -m 'oops committed a secret' )
rm -f "$WORK/docker-args"
rc=$(run_wrapper 1)
{ [ "$rc" -eq 3 ] && grep -qF ".env" "$WORK/out" && [ ! -f "$WORK/docker-args" ]; } \
  && pass "TRACKED (committed) .env → refusal (exit 3), file named, container never started" \
  || fail "committed secret not refused (rc=$rc)"

# 3d (N-3) — a TRACKED, unignored SYMLINK pointing at an ignored secret. The symlink is in the clone
# (it's tracked) but its target (.env, gitignored, uncommitted) is NOT — so it dangles, and the secret
# is unreadable inside the container. Defeats even the audit's fallback of "scan all mounted files":
# the link's own name is benign and its tracked blob is just the string ".env".
mkrepo t3d
printf 'SECRET=1\n' > .env; printf '.env\n' > .gitignore
ln -s .env config-link.txt
( git add .gitignore config-link.txt && git commit -q -m 'benign-looking link' )
rm -f "$WORK/mount-ls"
rc=$(STUB_MOUNT_LS="$WORK/mount-ls" run_wrapper 1)
{ [ "$rc" -eq 0 ] \
  && awk '/=== files ===/{f=1;next} /=== readable ===/{f=0} f' "$WORK/mount-ls" | grep -qx 'config-link.txt' \
  && ! awk '/=== readable ===/{r=1;next} r' "$WORK/mount-ls" | grep -qx 'config-link.txt' \
  && ! grep -q '\.env' "$WORK/mount-ls"; } \
  && pass "tracked symlink → ignored secret: link present but DANGLING (target absent), secret unreadable (N-3)" \
  || fail "symlink leaked its ignored target into the mount (rc=$rc); mount: $(cat "$WORK/mount-ls" 2>/dev/null | tr '\n' ' ')"

# 4 — clean repo: docker run mounts the CLEAN CLONE (a temp path, NOT $PWD) as the only volume, passes
# ONLY ANTHROPIC_API_KEY + the JAIMITOS_SANDBOXED marker, forwards wrapper args, and appends
# --dangerously-skip-permissions as the LAST argument inside the container.
mkrepo t4
rm -f "$WORK/docker-args"
rc=$(run_wrapper 3 --pr)
ARGS="$(cat "$WORK/docker-args" 2>/dev/null || true)"
MOUNT_SRC="$(printf '%s\n' "$ARGS" | awk '/:\/work$/{print; exit}')"
{ [ "$rc" -eq 0 ] && [ -n "$ARGS" ] \
  && [ "$(printf '%s\n' "$ARGS" | grep -cx -- '-v')" -eq 1 ] \
  && printf '%s\n' "$MOUNT_SRC" | grep -q ':/work$' \
  && [ "${MOUNT_SRC%:/work}" != "$(cd "$REPO" && pwd -P)" ] \
  && printf '%s\n' "$ARGS" | grep -qx -- "ANTHROPIC_API_KEY" \
  && printf '%s\n' "$ARGS" | grep -qx -- "JAIMITOS_SANDBOXED=1" \
  && [ "$(printf '%s\n' "$ARGS" | grep -cx -- '-e')" -eq 2 ] \
  && printf '%s\n' "$ARGS" | grep -qx -- "scripts/autopilot.sh" \
  && printf '%s\n' "$ARGS" | grep -qx -- "3" \
  && printf '%s\n' "$ARGS" | grep -qx -- "--pr" \
  && [ "$(printf '%s\n' "$ARGS" | tail -1)" = "--dangerously-skip-permissions" ]; } \
  && pass "clean repo: docker run mounts the CLEAN CLONE (not \$PWD), passes ONLY the key + sandboxed marker, forwards args, appends --dangerously-skip-permissions last" \
  || fail "docker run invocation malformed (rc=$rc): mount='$MOUNT_SRC' args=$ARGS"

# 4c (C1) — the mount source is NOT the live working dir: an untracked file created in $PWD is absent.
mkrepo t4c
printf 'live uncommitted\n' > only-in-live-dir.txt
rm -f "$WORK/mount-ls"
rc=$(STUB_MOUNT_LS="$WORK/mount-ls" run_wrapper 1)
{ [ "$rc" -eq 0 ] && ! grep -q 'only-in-live-dir.txt' "$WORK/mount-ls"; } \
  && pass "mounted clone excludes uncommitted working-dir files (not a live bind mount)" \
  || fail "live working-dir file appeared in the mount (rc=$rc)"

# ---- export path (correction C-A): the loop's autopilot/* work must be imported back or fail closed ----

# E1 — the container produces an autopilot/* branch → the wrapper IMPORTS it into this repo; clone gone.
mkrepo te1
before_branches="$(git branch --list 'autopilot/*')"
rc=$(STUB_MAKE_REF=1 run_wrapper 1)
{ [ "$rc" -eq 0 ] && [ -z "$before_branches" ] && git rev-parse --verify -q "autopilot/teststamp" >/dev/null \
  && grep -q "imported autopilot/\* branch" "$WORK/out"; } \
  && pass "produced autopilot/* branch → imported into this repo (export channel works)" \
  || fail "autopilot/* branch NOT imported (rc=$rc)"

# E2 — the container produces NOTHING → the wrapper cleans up and returns the run's exit code.
mkrepo te2
rc=$(STUB_MAKE_REF=0 STUB_RUN_RC=0 run_wrapper 1)
{ [ "$rc" -eq 0 ] && grep -q "no work was produced" "$WORK/out"; } \
  && pass "no work produced → clean exit, nothing imported" \
  || fail "no-work export path wrong (rc=$rc)"

# E3 (C-A) — the container FAILS (rc!=0) AFTER committing an autopilot/* branch → the work is STILL
# imported (never lost because the container exited non-zero), and the wrapper surfaces the run's rc.
mkrepo te3
rc=$(STUB_MAKE_REF=1 STUB_RUN_RC=7 run_wrapper 1)
{ [ "$rc" -eq 7 ] && git rev-parse --verify -q "autopilot/teststamp" >/dev/null; } \
  && pass "container failed after a commit → work imported anyway, run rc surfaced (7)" \
  || fail "work lost or rc swallowed on container-fail-after-commit (rc=$rc)"

# E4 (C-A) — a same-named branch already exists here and diverges → import is a non-fast-forward and
# must FAIL CLOSED (non-zero), print the recovery path, and PRESERVE the staging clone (work not lost).
mkrepo te4
git checkout -q -b autopilot/teststamp
printf 'diverging host work\n' > host-side.txt; git add -A; git commit -q -m 'host diverged'
git checkout -q -                          # back off the branch so the wrapper's fetch targets it
rc=$(STUB_MAKE_REF=1 STUB_RUN_RC=0 run_wrapper 1)
{ [ "$rc" -ne 0 ] && grep -q "PRESERVED" "$WORK/out"; } \
  && pass "non-fast-forward import → fail-closed (non-zero), recovery path printed, clone preserved" \
  || fail "non-ff import did not fail closed / preserve work (rc=$rc)"

# ---- F2: NO produced work is ever discarded (not just autopilot/*) ----

# F2a — --no-worktree is REJECTED before any container starts. Forwarded into the sandbox it makes
# autopilot commit on the clone's CURRENT branch (not autopilot/*), which the export step cannot
# recover — so the wrapper must refuse it up front rather than silently forward it.
mkrepo tf2a
rm -f "$WORK/docker-args"
rc=$(run_wrapper 1 --no-worktree)
{ [ "$rc" -ne 0 ] && grep -qi "no-worktree" "$WORK/out" && [ ! -f "$WORK/docker-args" ]; } \
  && pass "F2: --no-worktree rejected before the container (no docker run)" \
  || fail "F2: --no-worktree not rejected (rc=$rc, docker-args exists=$([ -f "$WORK/docker-args" ] && echo yes))"

# helper: extract the preserved staging-clone path from the recovery output, and clean it up.
clone_path() { grep -oE '/[^ "]*/repo' "$WORK/out" | head -1; }

# F2b — the container commits on the clone's CURRENT branch (not autopilot/*): the wrapper must NOT
# delete the clone. Preserve it + print recovery (pre-fix it printed 'nothing to import' and deleted it).
mkrepo tf2b
rc=$(STUB_MAKE_CURRENT=1 run_wrapper 1); CD=$(clone_path)
{ [ "$rc" -ne 0 ] && [ -n "$CD" ] && [ -d "$CD" ] && grep -qi "PRESERVED" "$WORK/out"; } \
  && pass "F2: commit on current branch → clone PRESERVED + recovery (work not lost)" \
  || fail "F2: current-branch work discarded (rc=$rc, clone='$CD' exists=$([ -d "$CD" ] && echo yes))"
[ -n "$CD" ] && rm -rf "$(dirname "$CD")" 2>/dev/null

# F2c — a detached-HEAD commit in the clone → preserved (not on any branch, easy to lose).
mkrepo tf2c
rc=$(STUB_MAKE_DETACHED=1 run_wrapper 1); CD=$(clone_path)
{ [ "$rc" -ne 0 ] && [ -d "$CD" ]; } \
  && pass "F2: detached-HEAD commit → clone preserved" || fail "F2: detached commit lost (rc=$rc)"
[ -n "$CD" ] && rm -rf "$(dirname "$CD")" 2>/dev/null

# F2d — a dirty TRACKED change left in the clone → preserved.
mkrepo tf2d
rc=$(STUB_MAKE_DIRTY=1 run_wrapper 1); CD=$(clone_path)
{ [ "$rc" -ne 0 ] && [ -d "$CD" ]; } \
  && pass "F2: dirty tracked change → clone preserved" || fail "F2: dirty work lost (rc=$rc)"
[ -n "$CD" ] && rm -rf "$(dirname "$CD")" 2>/dev/null

# F2e — an UNTRACKED file left in the clone → preserved.
mkrepo tf2e
rc=$(STUB_MAKE_UNTRACKED=1 run_wrapper 1); CD=$(clone_path)
{ [ "$rc" -ne 0 ] && [ -d "$CD" ]; } \
  && pass "F2: untracked artifact → clone preserved" || fail "F2: untracked work lost (rc=$rc)"
[ -n "$CD" ] && rm -rf "$(dirname "$CD")" 2>/dev/null

# 4b — missing image → docker build invoked against sandbox/Dockerfile.autopilot before run.
mkrepo t4b
rm -f "$WORK/docker-args" "$WORK/docker-args.build"
rc=$(STUB_IMAGE_EXISTS=0 run_wrapper 1)
{ [ "$rc" -eq 0 ] && grep -q "Dockerfile.autopilot" "$WORK/docker-args.build" 2>/dev/null; } \
  && pass "missing image → wrapper builds from sandbox/Dockerfile.autopilot first" \
  || fail "image build path broken (rc=$rc)"

# 5 — missing _secret-scan.sh lib → fail-closed refusal (exit 2), container never started.
mkrepo t5
rm .claude/lib/_secret-scan.sh
rm -f "$WORK/docker-args"
rc=$(run_wrapper 1)
{ [ "$rc" -eq 2 ] && grep -qi "fail-closed" "$WORK/out" && [ ! -f "$WORK/docker-args" ]; } \
  && pass "missing scan lib → fail-closed refusal, container never started" \
  || fail "missing scan lib not fail-closed (rc=$rc)"

# 6 — --help exits 0 and mentions the contract.
bash "$WRAPPER" --help >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q "ANTHROPIC_API_KEY" "$WORK/out"; } \
  && pass "--help prints the contract and exits 0" || fail "--help broken (rc=$rc)"

# 7 — Dockerfile lint: hadolint when available; otherwise structural must-haves (slim base,
# a USER line that isn't root, /work as the workdir, no credential-path mentions).
echo ""
if command -v hadolint >/dev/null 2>&1; then
  if hadolint "$DOCKERFILE" >"$WORK/hado" 2>&1; then pass "hadolint: Dockerfile.autopilot is clean"
  else fail "hadolint reported issues: $(head -3 "$WORK/hado" | tr '\n' ';')"; fi
else
  { grep -qE '^FROM .*(slim|alpine)' "$DOCKERFILE" \
    && grep -qE '^USER ' "$DOCKERFILE" && ! grep -qE '^USER +root' "$DOCKERFILE" \
    && grep -qE '^WORKDIR /work' "$DOCKERFILE" \
    && ! grep -vE '^[[:space:]]*#' "$DOCKERFILE" | grep -qE '\.aws|\.ssh'; } \
    && pass "Dockerfile structural checks (slim base, non-root USER, /work, no credential paths) — hadolint not installed" \
    || fail "Dockerfile structural checks failed"
fi

# ============================================================================================
# autopilot.sh's OWN sandbox fail-closed brake (v2.6.0): --dangerously-skip-permissions on a bare
# host (no sandbox signal) is REFUSED unless --i-understand-no-sandbox is passed. The container
# indicator paths are overridable (JAIMITOS_DOCKERENV_PATH / JAIMITOS_CGROUP_PATH) so a test can
# simulate a bare host even when the test runner is itself a container.
# ============================================================================================
AUTOPILOT="$SCAFFOLD/scripts/autopilot.sh"

# mkautorepo: minimal scaffold sufficient for autopilot.sh to reach (or refuse before) the sandbox
# gate. cds the shell into it. No real `claude` — a run that gets past the gate simply fails the
# builder, which is fine: the gate's refusal/banner is emitted before the loop.
mkautorepo() {
  R="$WORK/$1"; rm -rf "$R"; mkdir -p "$R/.claude/lib" "$R/scripts" "$R/docs"
  cp "$AUTOPILOT" "$R/scripts/autopilot.sh"
  cp "$SCAFFOLD/.claude/lib/_eval-isolation.sh" "$R/.claude/lib/"     # required (fail-closed) lib
  printf '{"hooks":{}}\n' > "$R/.claude/settings.json"
  printf '# Roadmap\n## Phase 1 — x\n- [ ] a\nDone when: x\nMode: loopable\n' > "$R/docs/ROADMAP.md"
  printf '# State\n' > "$R/docs/STATE.md"
  ( cd "$R" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  cd "$R" || exit 1
}
# No-signal env: forge nothing, just point the container indicators at nonexistent paths.
NOSIG=(JAIMITOS_SANDBOXED= JAIMITOS_DOCKERENV_PATH=/nonexistent-xyz JAIMITOS_CGROUP_PATH=/nonexistent-xyz)

echo ""
# 8 — refusal: bypass + no sandbox signal + no ack → exit 1, names the wrapper, before any loop.
mkautorepo a8
env "${NOSIG[@]}" bash scripts/autopilot.sh 1 --no-worktree --allow-dirty --dangerously-skip-permissions >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 1 ] && grep -qi "NO sandbox signal" "$WORK/out" && grep -q "run-autopilot-sandboxed.sh" "$WORK/out"; } \
  && pass "autopilot refuses --dangerously-skip-permissions with no sandbox signal (exit 1, points at the wrapper)" \
  || fail "autopilot did not refuse the no-sandbox bypass (rc=$rc)"

# 9 — override: same, plus --i-understand-no-sandbox → does NOT refuse; prints the banner and
# records it in autopilot.log. (It then fails the builder — no real claude — which is expected.)
mkautorepo a9
env "${NOSIG[@]}" bash scripts/autopilot.sh 1 --no-worktree --allow-dirty --dangerously-skip-permissions --i-understand-no-sandbox >"$WORK/out" 2>&1
{ ! grep -qi "NO sandbox signal detected" "$WORK/out" \
  && grep -q "OUTSIDE ANY DETECTED SANDBOX" "$WORK/out" \
  && grep -q "OUTSIDE ANY DETECTED SANDBOX" autopilot.log 2>/dev/null; } \
  && pass "--i-understand-no-sandbox proceeds past the gate, prints the banner, and records it in autopilot.log" \
  || fail "--i-understand-no-sandbox banner/logging broken"

# 10 — signal present (JAIMITOS_SANDBOXED=1) → no refusal, no bare-host banner (it IS 'sandboxed').
mkautorepo a10
env JAIMITOS_SANDBOXED=1 JAIMITOS_DOCKERENV_PATH=/nonexistent-xyz JAIMITOS_CGROUP_PATH=/nonexistent-xyz \
  bash scripts/autopilot.sh 1 --no-worktree --allow-dirty --dangerously-skip-permissions >"$WORK/out" 2>&1
{ ! grep -qi "NO sandbox signal" "$WORK/out" && ! grep -q "OUTSIDE ANY DETECTED SANDBOX" "$WORK/out"; } \
  && pass "JAIMITOS_SANDBOXED=1 → no refusal and no bare-host banner (the wrapper's normal path)" \
  || fail "sandbox-signal path wrongly refused or bannered"

# 11 — the brake is inert without --dangerously-skip-permissions (no behavior change there).
mkautorepo a11
env "${NOSIG[@]}" bash scripts/autopilot.sh 1 --no-worktree --allow-dirty >"$WORK/out" 2>&1
grep -qi "NO sandbox signal" "$WORK/out" \
  && fail "sandbox gate wrongly fired without --dangerously-skip-permissions" \
  || pass "sandbox gate is inert when --dangerously-skip-permissions is absent"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All sandbox tests passed."; exit 0
else echo "$FAILS sandbox test(s) FAILED."; echo "--- last output ---"; tail -n 15 "$WORK/out" 2>/dev/null; exit 1; fi
