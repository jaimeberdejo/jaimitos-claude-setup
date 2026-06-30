#!/usr/bin/env bash
# test-high-stakes.sh — assert HIGH_STAKES_RE matches every category the docs promise,
# and does NOT trip on clearly-benign paths. Regression guard for finding #2 (the regex
# used to miss authentication/, oauth/, delete, email, deploy, refund, webhook).

set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/lib/_high-stakes.sh"
[ -f "$LIB" ] || { echo "test: cannot find _high-stakes.sh at $LIB" >&2; exit 1; }
# shellcheck disable=SC1090
. "$LIB"

FAILS=0
should_match()   { if high_stakes_match "$1" >/dev/null; then printf '  ✓ matches: %s\n' "$1"; else printf '  ✗ MISSED (should match): %s\n' "$1"; FAILS=$((FAILS+1)); fi; }
should_ignore()  { if high_stakes_match "$1" >/dev/null; then printf '  ✗ FALSE HIT (should ignore): %s\n' "$1"; FAILS=$((FAILS+1)); else printf '  ✓ ignores: %s\n' "$1"; fi; }

echo "high-stakes detection tests"
echo ""
echo "Documented categories — directory form (must match):"
for p in \
  "src/auth/session.py" \
  "src/authentication/login.py" \
  "src/authorization/rbac.py" \
  "app/oauth/callback.ts" \
  "app/oauth2/callback.ts" \
  "services/auth-service/x.go" \
  "services/auth_service/x.go" \
  "services/login/handler.go" \
  "db/migrations/004_drop_users.sql" \
  "prisma/migrate/x.sql" \
  "payments/charge.py" \
  "billing/invoice.rb" \
  "lib/user_delete.py" \
  "services/deletion/purge.py" \
  "mailer/email_sender.py" \
  "ops/deploy/release.sh" \
  "api/refund_handler.js" \
  "wallet/withdraw.py" \
  "integrations/stripe_webhook.py" \
  "compliance/suitability_check.py" \
  "secrets/loader.py" \
  "secret/key.py" \
  "transaction/ledger.py" \
  "core/money_utils.py"
do should_match "$p"; done

echo ""
echo "Documented categories — SINGLE-FILE module form (must match; regression for the .ext anchor):"
for p in \
  "src/auth.py" "app/oauth.ts" "services/login.go" "core/session.rb" \
  "models/account.py" "billing.py" "wallet.py" "ledger.py" "kyc.py" \
  "compliance.py" "suitability.py" "transactions.py" "session-store.ts"
do should_match "$p"; done

echo ""
echo "Benign paths (must NOT match — keep the widened anchor tight):"
for p in \
  "src/utils/strings.py" \
  "tests/test_parser.py" \
  "components/Button.tsx" \
  "docs/README.md" \
  "lib/http_client.go" \
  "accounting/reports.py" \
  "src/accountant.py" \
  "src/healthcheck.py"
do should_ignore "$p"; done

echo ""
echo "Fail-safe: an empty/unset HIGH_STAKES_RE must treat ALL paths as high-stakes (never fail open):"
(
  unset HIGH_STAKES_RE
  if high_stakes_match "any/ordinary/path.py" >/dev/null 2>&1; then printf '  ✓ unset regex fails SAFE (matches)\n'
  else printf '  ✗ unset regex FAILED OPEN (matched nothing)\n'; exit 1; fi
) || FAILS=$((FAILS+1))

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All high-stakes detection tests passed."; exit 0
else echo "$FAILS detection test(s) FAILED."; exit 1; fi
