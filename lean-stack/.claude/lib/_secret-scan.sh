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
# This is a LIBRARY under .claude/lib/ (not a hook). Sourcing it only defines the
# functions; running it directly is a harmless no-op.

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
    *.env|.env.*|*.pem|*.key|*.p12|*.pfx|*.jks|credentials*.json|\
    id_rsa|id_ed25519|id_ecdsa|id_dsa|*.tfstate|*.tfvars|.envrc|.netrc|.git-credentials)
      return 0 ;;
  esac
  return 1
}

# --- content patterns: high-confidence secret tokens in ADDED lines ---
# Tuned for low false-positives but broadened to the credential shapes a real project
# most often leaks: AWS keys, PEM private-key blocks, OpenAI (sk-) AND Stripe (sk_live_/
# rk_live_) keys, GitHub/Slack tokens, Google API keys (AIza…), and URLs with an embedded
# user:password (postgres://user:pass@host). The URL rule requires BOTH a non-empty user
# and password before '@', so bare URLs (https://host, redis://:@h) do NOT trip it.
# Still NOT a full scanner (use gitleaks/trufflehog for that) — a strong commit-time default.
_SECRET_CONTENT_RE='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|sk-[A-Za-z0-9]{20,}|sk_live_[A-Za-z0-9]{16,}|rk_live_[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|[a-zA-Z][a-zA-Z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]:@]+@'

# _secret_content_hits <git-diff-args...>: emit up to 10 ADDED lines (leading '+'
# stripped) that contain a high-confidence secret token. Shared by both scanners so the
# content rule lives in one place. We deliberately do NOT print line numbers — the only
# honest number here would be a diff-stream offset, which is meaningless to the user.
_secret_content_hits() {
  git diff "$@" --unified=0 2>/dev/null \
    | grep -E '^\+' | grep -Ev '^\+\+\+' \
    | grep -E "$_SECRET_CONTENT_RE" 2>/dev/null \
    | head -10 | sed 's/^+//'
}

# secret_scan_staged: scan the staged index. Echoes findings; returns 0/1/2.
secret_scan_staged() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "secret-scan: not a git repo"; return 2; }

  local -a found=()
  local staged hits line
  # 1) filename scan
  while IFS= read -r staged; do
    [ -z "$staged" ] && continue
    _secret_basename_match "$staged" && found+=("  [filename] $staged")
  done < <(git diff --cached --name-only 2>/dev/null)

  # 2) content scan over ADDED lines only.
  hits=$(_secret_content_hits --cached)
  if [ -n "$hits" ]; then
    found+=("  [content] high-confidence secret token(s) in staged diff:")
    while IFS= read -r line; do [ -n "$line" ] && found+=("      $line"); done <<< "$hits"
  fi

  if [ "${#found[@]}" -gt 0 ]; then printf '%s\n' "${found[@]}"; return 1; fi
  return 0
}

# secret_scan_diff <git-range>: scan a commit RANGE (e.g. "$BASE..HEAD") by filename
# and content. Used before pushing (the builder's per-task commits don't pass through
# the Stop-hook guard, so this is the gate that stops a secret reaching a remote).
# Echoes findings; returns 0 clean / 1 secrets / 2 cannot-scan (fail-closed).
secret_scan_diff() {
  local range="$1"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "secret-scan: not a git repo"; return 2; }
  [ -z "$range" ] && { echo "secret-scan: no range given"; return 2; }
  local -a found=()
  local f hits line
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    _secret_basename_match "$f" && found+=("  [filename] $f")
  done < <(git diff --name-only "$range" 2>/dev/null)
  hits=$(_secret_content_hits "$range")
  if [ -n "$hits" ]; then
    found+=("  [content] secret token(s) in range $range:")
    while IFS= read -r line; do [ -n "$line" ] && found+=("      $line"); done <<< "$hits"
  fi
  if [ "${#found[@]}" -gt 0 ]; then printf '%s\n' "${found[@]}"; return 1; fi
  return 0
}

# Running directly = no-op (this file is a library, not a hook).
return 0 2>/dev/null || exit 0
