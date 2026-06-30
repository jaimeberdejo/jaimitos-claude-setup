#!/usr/bin/env bash
# test-secret-scan.sh — fixtures for _secret-scan.sh. Asserts the broadened content regex
# catches the credential shapes a project most often leaks (Stripe/Google/URL creds, …)
# AND that benign content (plain URLs, example files) does NOT trip it (a false hit blocks
# a legitimate commit, so the no-false-positive cases matter as much as the catches).

set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/hooks/_secret-scan.sh"
[ -f "$LIB" ] || { echo "test: cannot find _secret-scan.sh at $LIB" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }
# shellcheck disable=SC1090
. "$LIB"

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t secretscan)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
git init -q && git config user.email t@t.t && git config user.name t
# An initial commit so `git reset` (used between fixtures to clear the index) resolves
# HEAD — without it, reset fails and staged files leak from one case into the next.
git commit -q --allow-empty -m init

FAILS=0
# stage_only <path> <content>: reset the index, write+stage one file.
stage_only() { git reset -q 2>/dev/null; rm -f f_*; printf '%s\n' "$2" > "$1"; git add "$1" 2>/dev/null; }

want_secret() {  # $1 desc, $2 path, $3 content
  stage_only "$2" "$3"
  if secret_scan_staged >/dev/null; then printf '  ✗ MISSED secret: %s\n' "$1"; FAILS=$((FAILS+1));
  else printf '  ✓ caught: %s\n' "$1"; fi
}
want_clean() {   # $1 desc, $2 path, $3 content
  stage_only "$2" "$3"
  # secret_scan_staged: 0 = clean, non-zero = secret found.
  if secret_scan_staged >/dev/null; then printf '  ✓ clean: %s\n' "$1";
  else printf '  ✗ FALSE HIT: %s\n' "$1"; FAILS=$((FAILS+1)); fi
}

echo "secret-scan fixture tests"
echo ""
echo "Must be caught:"
want_secret "Stripe live key"      "f_stripe.py" 'STRIPE="sk_live_51HxxxxxxxxxxxxxxxxxxYz"'
want_secret "Google API key"       "f_g.py"      'KEY = "AIzaSyA1234567890abcdefghijklmnopqrstuv"'
want_secret "DB URL with password" "f_db.py"     'DATABASE_URL="postgres://admin:Hunter2@db.prod/app"'
want_secret "AWS access key id"    "f_aws.txt"   'AKIAIOSFODNN7EXAMPLE'
want_secret "OpenAI key"           "f_oai.py"    'OPENAI="sk-abcdefghijklmnopqrstuvwxyz0123"'
want_secret "secret filename"      ".env"        'X=1'

echo ""
echo "Must stay clean:"
want_clean  "plain https URL"      "f_url.py"    'API = "https://api.example.com/v1/users"'
want_clean  "localhost with port"  "f_lh.py"     'DEV = "http://localhost:3000/health"'
want_clean  "credential-less SSH"  "f_ssh.txt"   'git@github.com:org/repo.git'
want_clean  ".env.example template" ".env.example" 'STRIPE=sk_live_xxx_placeholder_here'
want_clean  "ordinary code"        "f_ok.py"     'def add(a, b): return a + b'

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All secret-scan fixture tests passed."; exit 0
else echo "$FAILS fixture test(s) FAILED."; exit 1; fi
