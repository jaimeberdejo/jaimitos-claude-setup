#!/usr/bin/env bash
# _secret-scan.sh — SHARED secret-scanning library (sourced, not a hook).
# Used by commit-on-stop.sh (Stop hook) and scripts/autopilot.sh (post-PASS commit)
# so the SAME guard runs everywhere — the orchestrator commit can't bypass it.
#
# Provides: secret_scan_staged
#   Scans the current git STAGED set (git diff --cached) for secrets by BOTH
#   filename and content. Prints offending items to stdout. Returns:
#     0  = clean (no secrets staged)
#     1  = secrets found (caller MUST NOT commit/push)
#     2  = could not scan (not a git repo / git error) — treat as fail-closed
#
# Sourcing this file only defines the function; running it directly is a harmless
# no-op (so it's safe under the hooks/*.sh glob used by CI/doctor/test-hooks).

# --- filename patterns (basename or path) that are always secrets ---
# Kept in sync with .gitignore and settings.json permissions.deny.
_secret_basename_match() {
  # $1 = a staged path; returns 0 if it looks like a secret file.
  local p="$1" base="${1##*/}"
  # Allow obvious template/example files FIRST — teams track these intentionally,
  # and they must win over the .env.* secret pattern below (e.g. .env.example).
  case "$base" in
    *.example|*.sample|*.template|*.dist) return 1 ;;
  esac
  case "$p" in
    secrets/*|*/secrets/*) return 0 ;;
  esac
  case "$base" in
    *.env|.env|.env.*|*.pem|*.key|*.p12|*.pfx|*.jks|credentials*.json|\
    id_rsa|id_ed25519|id_ecdsa|id_dsa|*.tfstate|*.tfvars|.envrc|.netrc|.git-credentials)
      return 0 ;;
  esac
  return 1
}

# --- content patterns: high-confidence secret tokens in ADDED lines ---
# Deliberately narrow (low false-positive) — AWS keys, private-key blocks,
# OpenAI/GitHub/Slack tokens. Not a substitute for gitleaks; a strong default.
_SECRET_CONTENT_RE='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}'

# secret_scan_staged: scan the staged index. Echoes findings; returns 0/1/2.
secret_scan_staged() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "secret-scan: not a git repo"; return 2; }

  local found="" staged
  # 1) filename scan
  while IFS= read -r staged; do
    [ -z "$staged" ] && continue
    if _secret_basename_match "$staged"; then
      found="$found\n  [filename] $staged"
    fi
  done < <(git diff --cached --name-only 2>/dev/null)

  # 2) content scan over ADDED lines only (prefix '+', excluding the +++ header).
  local hits
  hits=$(git diff --cached --unified=0 2>/dev/null \
         | grep -E '^\+' | grep -Ev '^\+\+\+' \
         | grep -nE "$_SECRET_CONTENT_RE" 2>/dev/null | head -10)
  if [ -n "$hits" ]; then
    found="$found\n  [content] high-confidence secret token(s) in staged diff:"
    found="$found\n$(printf '%s' "$hits" | sed 's/^/      /')"
  fi

  if [ -n "$found" ]; then
    printf '%b\n' "$found"
    return 1
  fi
  return 0
}

# secret_scan_diff <git-range>: scan a commit RANGE (e.g. "$BASE..HEAD") by filename
# and content. Used before pushing (the builder's per-task commits don't pass through
# the Stop-hook guard, so this is the gate that stops a secret reaching a remote).
# Echoes findings; returns 0 clean / 1 secrets / 2 cannot-scan (fail-closed).
secret_scan_diff() {
  local range="$1" found="" f
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "secret-scan: not a git repo"; return 2; }
  [ -z "$range" ] && { echo "secret-scan: no range given"; return 2; }
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    _secret_basename_match "$f" && found="$found\n  [filename] $f"
  done < <(git diff --name-only "$range" 2>/dev/null)
  local hits
  hits=$(git diff --unified=0 "$range" 2>/dev/null \
         | grep -E '^\+' | grep -Ev '^\+\+\+' \
         | grep -nE "$_SECRET_CONTENT_RE" 2>/dev/null | head -10)
  [ -n "$hits" ] && found="$found\n  [content] secret token(s) in range $range:\n$(printf '%s' "$hits" | sed 's/^/      /')"
  if [ -n "$found" ]; then printf '%b\n' "$found"; return 1; fi
  return 0
}

# Running directly = no-op (this file is a library, not a hook).
return 0 2>/dev/null || exit 0
