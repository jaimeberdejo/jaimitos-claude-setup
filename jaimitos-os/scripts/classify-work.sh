#!/usr/bin/env bash
# classify-work.sh — recommend a proportionate workflow tier (TINY | STANDARD | DEEP) for a unit of work.
#
# This is an INSPECTABLE control-plane helper, not a skill and not an agent. It takes signal flags,
# prints a "## Work classification" block, and exits. It has NO side effects: it never edits SPEC.md,
# never selects a model, never routes anything. A human (or a skill) records the selected tier in
# docs/SPEC.md frontmatter (`tier:`) and may override the recommendation with an explicit reason.
#
# The recommendation is deterministic and reproducible from the flags — the same flags always give the
# same tier. What tier a piece of work SHOULD be is a human judgement; this only makes the signals and
# the default explicit so nothing is decided invisibly.
#
# Usage:
#   bash scripts/classify-work.sh [signal flags] [--select TIER] [--reason "..."] [--subject "..."]
#
# Escalation signals (any one normally PREVENTS TINY — an override is possible but must be explicit):
#   --auth --authz --secrets --payments --privacy --destructive-migration --public-api
#   --high-stakes-data --major-deps --multi-service-deploy --irreversible --arch-unresolved --high-stakes
#
# Complexity signals:
#   --components N        number of affected components/modules (default 1)
#   --phases N            expected phase count (default 1)
#   --files N             rough count of likely-affected files (default 0 = unknown)
#   --novelty LEVEL       low | medium | high (default low)
#   --ambiguous          requirement is ambiguous / underspecified
#   --research           external research is needed
#   --external-interface an externally exposed interface / public contract is touched
#   --db-migration       a (non-destructive) database migration is involved
#   --deploy             deployment impact
#   --deps               dependency changes (non-major)
#   --compat             backward-compatibility impact
#   --observability      new observability/monitoring is needed
#   --brownfield         work is in an unfamiliar / legacy codebase
#
# Selection / override:
#   --select TIER        the tier actually chosen (default = the recommendation)
#   --reason "..."       why the chosen tier differs from the recommendation (required on override)
#   --subject "..."      short description of the work (for the block header)
#
# Exit: 0 on success (prints the block). 2 on a usage error (unknown flag / bad value) — fail-closed so a
# typo can never silently misclassify. A TINY selection that overrides an escalation signal prints a loud
# warning but still exits 0 (the human is allowed to override; they are not allowed to do it invisibly).
set -uo pipefail

die() { printf 'classify-work: %s\n' "$1" >&2; exit 2; }

# --- defaults -----------------------------------------------------------------
COMPONENTS=1; PHASES=1; FILES=0; NOVELTY="low"
AMBIGUOUS=0; RESEARCH=0; EXT_IFACE=0; DB_MIGRATION=0; DEPLOY=0; DEPS=0; COMPAT=0; OBSERV=0; BROWNFIELD=0
AUTH=0; AUTHZ=0; SECRETS=0; PAYMENTS=0; PRIVACY=0; DESTRUCTIVE_MIGRATION=0; PUBLIC_API=0
HIGH_STAKES_DATA=0; MAJOR_DEPS=0; MULTI_DEPLOY=0; IRREVERSIBLE=0; ARCH_UNRESOLVED=0; HIGH_STAKES=0
SELECT=""; REASON=""; SUBJECT=""

is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# --- parse --------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --components) COMPONENTS="${2:-}"; is_int "$COMPONENTS" || die "--components needs an integer"; shift 2 ;;
    --phases)     PHASES="${2:-}";     is_int "$PHASES"     || die "--phases needs an integer"; shift 2 ;;
    --files)      FILES="${2:-}";      is_int "$FILES"      || die "--files needs an integer"; shift 2 ;;
    --novelty)    NOVELTY="${2:-}"; case "$NOVELTY" in low|medium|high) ;; *) die "--novelty must be low|medium|high" ;; esac; shift 2 ;;
    --select)     SELECT="${2:-}"; case "$SELECT" in TINY|STANDARD|DEEP) ;; *) die "--select must be TINY|STANDARD|DEEP" ;; esac; shift 2 ;;
    --reason)     REASON="${2:-}"; shift 2 ;;
    --subject)    SUBJECT="${2:-}"; shift 2 ;;
    --ambiguous)  AMBIGUOUS=1; shift ;;
    --research)   RESEARCH=1; shift ;;
    --external-interface) EXT_IFACE=1; shift ;;
    --db-migration) DB_MIGRATION=1; shift ;;
    --deploy)     DEPLOY=1; shift ;;
    --deps)       DEPS=1; shift ;;
    --compat)     COMPAT=1; shift ;;
    --observability) OBSERV=1; shift ;;
    --brownfield) BROWNFIELD=1; shift ;;
    --auth)       AUTH=1; shift ;;
    --authz)      AUTHZ=1; shift ;;
    --secrets)    SECRETS=1; shift ;;
    --payments)   PAYMENTS=1; shift ;;
    --privacy)    PRIVACY=1; shift ;;
    --destructive-migration) DESTRUCTIVE_MIGRATION=1; shift ;;
    --public-api) PUBLIC_API=1; shift ;;
    --high-stakes-data) HIGH_STAKES_DATA=1; shift ;;
    --major-deps) MAJOR_DEPS=1; shift ;;
    --multi-service-deploy) MULTI_DEPLOY=1; shift ;;
    --irreversible) IRREVERSIBLE=1; shift ;;
    --arch-unresolved) ARCH_UNRESOLVED=1; shift ;;
    --high-stakes) HIGH_STAKES=1; shift ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

# --- collect signals ----------------------------------------------------------
RISK=""; COMPLEX=""
add_risk()    { RISK="${RISK}- $1"$'\n'; }
add_complex() { COMPLEX="${COMPLEX}- $1"$'\n'; }

[ "$AUTH" = 1 ]                  && add_risk "authentication"
[ "$AUTHZ" = 1 ]                 && add_risk "authorization"
[ "$SECRETS" = 1 ]              && add_risk "secrets / credentials"
[ "$PAYMENTS" = 1 ]            && add_risk "payments / money"
[ "$PRIVACY" = 1 ]            && add_risk "privacy-sensitive data"
[ "$DESTRUCTIVE_MIGRATION" = 1 ] && add_risk "destructive database migration"
[ "$PUBLIC_API" = 1 ]        && add_risk "public API contract change"
[ "$HIGH_STAKES_DATA" = 1 ]  && add_risk "high-stakes data"
[ "$MAJOR_DEPS" = 1 ]        && add_risk "major dependency upgrade"
[ "$MULTI_DEPLOY" = 1 ]      && add_risk "multi-service deployment"
[ "$IRREVERSIBLE" = 1 ]      && add_risk "irreversible behavior"
[ "$ARCH_UNRESOLVED" = 1 ]   && add_risk "unresolved architecture decision"
[ "$HIGH_STAKES" = 1 ]       && add_risk "explicitly high-stakes"

[ "$AMBIGUOUS" = 1 ]  && add_complex "requirement is ambiguous / underspecified"
[ "$RESEARCH" = 1 ]   && add_complex "external research needed"
[ "$EXT_IFACE" = 1 ]  && add_complex "externally exposed interface touched"
[ "$DB_MIGRATION" = 1 ] && add_complex "database migration"
[ "$DEPLOY" = 1 ]     && add_complex "deployment impact"
[ "$DEPS" = 1 ]       && add_complex "dependency changes"
[ "$COMPAT" = 1 ]     && add_complex "backward-compatibility impact"
[ "$OBSERV" = 1 ]     && add_complex "observability needed"
[ "$BROWNFIELD" = 1 ] && add_complex "unfamiliar / brownfield codebase"
[ "$NOVELTY" != low ] && add_complex "novelty: $NOVELTY"
[ "$COMPONENTS" -ge 3 ] && add_complex "affects $COMPONENTS components"
[ "$PHASES" -ge 2 ]     && add_complex "expected $PHASES phases"
[ "$FILES" -ge 10 ]     && add_complex "~$FILES files likely affected"

# --- decision -----------------------------------------------------------------
# escalation: any one of these normally forbids TINY (floor = STANDARD).
escalation=0
if [ "$AUTH" = 1 ] || [ "$AUTHZ" = 1 ] || [ "$SECRETS" = 1 ] || [ "$PAYMENTS" = 1 ] || \
   [ "$DESTRUCTIVE_MIGRATION" = 1 ] || [ "$PUBLIC_API" = 1 ] || [ "$HIGH_STAKES_DATA" = 1 ] || \
   [ "$MAJOR_DEPS" = 1 ] || [ "$MULTI_DEPLOY" = 1 ] || [ "$IRREVERSIBLE" = 1 ] || \
   [ "$ARCH_UNRESOLVED" = 1 ] || [ "$HIGH_STAKES" = 1 ] || [ "$PRIVACY" = 1 ]; then
  escalation=1
fi

# deep: large / uncertain / research-heavy work.
deep=0
if [ "$RESEARCH" = 1 ] || [ "$ARCH_UNRESOLVED" = 1 ] || [ "$NOVELTY" = high ] || \
   [ "$MULTI_DEPLOY" = 1 ] || [ "$COMPONENTS" -ge 5 ] || [ "$PHASES" -ge 4 ] || \
   [ "$BROWNFIELD" = 1 ]; then
  deep=1
fi

# standardish: medium signals that lift TINY to STANDARD even without an escalation signal.
standardish=0
if [ "$AMBIGUOUS" = 1 ] || [ "$EXT_IFACE" = 1 ] || [ "$DB_MIGRATION" = 1 ] || [ "$DEPLOY" = 1 ] || \
   [ "$DEPS" = 1 ] || [ "$OBSERV" = 1 ] || [ "$COMPAT" = 1 ] || [ "$NOVELTY" = medium ] || \
   [ "$COMPONENTS" -ge 3 ] || [ "$PHASES" -ge 2 ] || [ "$FILES" -ge 10 ]; then
  standardish=1
fi

if [ "$deep" = 1 ]; then RECOMMEND="DEEP"
elif [ "$escalation" = 1 ] || [ "$standardish" = 1 ]; then RECOMMEND="STANDARD"
else RECOMMEND="TINY"; fi

SELECTED="${SELECT:-$RECOMMEND}"
if [ "$SELECTED" = "$RECOMMEND" ]; then OVERRIDE="NO"; else OVERRIDE="YES"; fi

# --- per-tier workflow text ---------------------------------------------------
workflow_for() {
  case "$1" in
    TINY) cat <<'EOT'
- compact spec (Objective / Current / Expected / Scope / Likely files / Verification / Non-goals)
- diagnose + TDD where logic changes; deterministic reproduction for bugs
- generic evidence; lightweight evaluation; tick.sh
EOT
;;
    STANDARD) cat <<'EOT'
- native REQ/AC spec (docs/SPEC.md) + ROADMAP phase
- ownership-aware plan (## Change ownership) + stale-assumption revalidation
- Evaluator PLAN_CHECK + pre-mortem (unless explicitly waived with a reason)
- TDD implementation; generic evidence; Evaluator IMPLEMENTATION_REVIEW
- optional UAT when user-facing acceptance differs from automated tests; tick.sh
EOT
;;
    DEEP) cat <<'EOT'
- sourced research; mapme --brownfield and mapme --ownership as needed
- native DEEP spec (architecture, data model, contracts, migration/rollback, threat, failure modes)
- enforcement ledger where architectural claims exist; ROADMAP; ownership-aware plan
- stale-assumption revalidation; Evaluator PLAN_CHECK + pre-mortem (required)
- TDD implementation; generic evidence; IMPLEMENTATION_REVIEW; UAT; release check; tick.sh
EOT
;;
  esac
}
skipped_for() {
  case "$1" in
    TINY) cat <<'EOT'
- no full requirement hierarchy, architecture review, ownership map, or formal UAT
- no PLAN_CHECK unless a risk signal justifies it
EOT
;;
    STANDARD) cat <<'EOT'
- no DEEP research / architecture-alternatives / enforcement ledger unless a signal calls for it
- brownfield/ownership mapping only when the codebase is unfamiliar
EOT
;;
    DEEP) cat <<'EOT'
- nothing skipped by tier; drop individual sections only when demonstrably not applicable
EOT
;;
  esac
}

# --- reasons ------------------------------------------------------------------
REASONS=""
add_reason() { REASONS="${REASONS}- $1"$'\n'; }
case "$RECOMMEND" in
  DEEP)     add_reason "deep signals present (research / unresolved architecture / high novelty / many components or phases / brownfield / multi-service deploy)" ;;
  STANDARD) [ "$escalation" = 1 ] && add_reason "an escalation signal is present, which normally prevents TINY"
            [ "$standardish" = 1 ] && add_reason "medium complexity signals lift this above TINY" ;;
  TINY)     add_reason "small, reversible, low-risk change with no escalation or deep signals" ;;
esac
[ -z "$RISK" ]    && RISK="- none"$'\n'
[ -z "$COMPLEX" ] && COMPLEX="- none"$'\n'

# --- output -------------------------------------------------------------------
printf '## Work classification\n\n'
[ -n "$SUBJECT" ] && printf 'Subject: %s\n\n' "$SUBJECT"
printf 'Recommended mode: %s\n' "$RECOMMEND"
printf 'Selected mode: %s\n' "$SELECTED"
printf 'User override: %s' "$OVERRIDE"
[ "$OVERRIDE" = YES ] && [ -n "$REASON" ] && printf ' — %s' "$REASON"
printf '\n\n'
printf 'Reasons:\n%s\n' "$REASONS"
printf 'Risk signals:\n%s\n' "$RISK"
printf 'Complexity signals:\n%s\n' "$COMPLEX"
printf 'Required workflow:\n'; workflow_for "$SELECTED"; printf '\n'
printf 'Explicitly skipped ceremony:\n'; skipped_for "$SELECTED"

# --- override guardrails (printed, never blocking) ----------------------------
if [ "$OVERRIDE" = YES ] && [ -z "$REASON" ]; then
  printf '\n! override with no --reason: record why the selected tier differs from the recommendation.\n' >&2
fi
if [ "$SELECTED" = TINY ] && [ "$escalation" = 1 ]; then
  printf '\n! TINY selected despite an escalation signal (auth/secrets/payments/migration/public-API/…).\n' >&2
  printf '  This override must be explicit and recorded — escalation signals normally require STANDARD+.\n' >&2
fi
exit 0
