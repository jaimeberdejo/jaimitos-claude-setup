#!/usr/bin/env bash
# lint-shell.sh — convenience linter for the toolkit's own shell code (a DEV tool; it lives in
# .github/scripts/ so it never ships into a target project). Mirrors what CI checks, in one place
# you can run locally: `bash .github/scripts/lint-shell.sh`.
#
#   shellcheck  — BLOCKING. Honors the repo-root .shellcheckrc (severity=warning, SC1090/SC1091
#                 disabled). A finding fails this script (exit 1). shellcheck is REQUIRED here (it's
#                 the whole point) — if it's not installed, that's an error, not a skip.
#   shfmt -d    — ADVISORY (for now). Prints formatting diffs but does NOT fail the script: the
#                 toolkit predates shfmt, so the tree isn't shfmt-formatted yet and a blocking check
#                 would be a wall of diffs. Once the tree is formatted, flip ADVISORY_SHFMT=0 (or set
#                 LINT_SHFMT_BLOCKING=1) to make it blocking. If shfmt isn't installed, it's skipped
#                 with a note (it's optional tooling).
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 1

# The exact set CI lints: the installer + repo-dev scripts, and the shipped scaffold scripts/hooks/libs.
FILES=(install.sh)
while IFS= read -r f; do FILES+=("$f"); done < <(
  { ls .github/scripts/*.sh jaimitos-os/scripts/*.sh \
       jaimitos-os/.claude/hooks/*.sh jaimitos-os/.claude/lib/*.sh \
       jaimitos-os/sandbox/*.sh 2>/dev/null; } | sort -u
)

RC=0

echo "== shellcheck (blocking; honors .shellcheckrc) =="
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "${FILES[@]}"; then
    echo "  ✓ shellcheck clean"
  else
    echo "  ✗ shellcheck reported findings (above)" >&2
    RC=1
  fi
else
  echo "  ✗ shellcheck is not installed — install it (brew install shellcheck / apt-get install shellcheck)." >&2
  RC=1
fi

echo ""
echo "== shfmt -d (advisory) =="
LINT_SHFMT_BLOCKING="${LINT_SHFMT_BLOCKING:-0}"
if command -v shfmt >/dev/null 2>&1; then
  # -d prints a unified diff of what shfmt WOULD change; empty output = already formatted.
  if diff_out="$(shfmt -d "${FILES[@]}" 2>&1)" && [ -z "$diff_out" ]; then
    echo "  ✓ shfmt: already formatted"
  else
    printf '%s\n' "$diff_out"
    if [ "$LINT_SHFMT_BLOCKING" = "1" ]; then
      echo "  ✗ shfmt formatting differences (blocking: LINT_SHFMT_BLOCKING=1)" >&2
      RC=1
    else
      echo "  ! shfmt formatting differences above — ADVISORY only (the tree isn't shfmt-formatted yet)."
    fi
  fi
else
  echo "  · shfmt not installed — skipped (optional; go install mvdan.cc/sh/v3/cmd/shfmt@latest)."
fi

echo ""
[ "$RC" -eq 0 ] && echo "lint-shell: PASS" || echo "lint-shell: FAIL"
exit "$RC"
