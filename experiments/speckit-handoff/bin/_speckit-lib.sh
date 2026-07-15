#!/usr/bin/env bash
# _speckit-lib.sh — shared parsing + rendering for the Spec Kit handoff. Sourced, not run.
#
# Pure grep/awk/sed. Bash 3.2 safe (CI asserts bash 3.2 on the macOS leg): no associative arrays,
# no mapfile, no ${x^^}. No network. No Python. It reads a Spec Kit feature pack and renders a
# Jaimitos roadmap FRAGMENT — it never edits docs/ROADMAP.md.
#
# Spec Kit markers, from the real templates at github/spec-kit@v0.12.13:
#   **FR-###**  functional requirement      **SC-###**  success criterion (measurable outcome)
#   T###        task, with [P] parallel and [US#] owning-user-story markers
#   [NEEDS CLARIFICATION: <reason>]         inline, inside the requirement bullet
# There is no NFR- convention: non-functional constraints are expressed as measurable SCs.

sk_warn() { printf 'speckit: %s\n' "$1" >&2; }

# sk_hash <file> — a content hash for a file, git-independent. Used to stamp the spec at import time
# so convergence can tell "the spec changed" from "the label was always a paraphrase".
sk_hash() {
  { git hash-object "$1" 2>/dev/null; } || \
  { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; } || \
  { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
}

# sk_feature_dir <pack> <feature> — the specs/<NNN-slug> directory. rc 1 if absent.
sk_feature_dir() {
  local d="$1/specs/$2"
  [ -d "$d" ] || return 1
  printf '%s\n' "$d"
}

# sk_ids <spec.md> <FR|SC> — every id of that kind, in document order, DUPLICATES INCLUDED.
# Duplicates are kept on purpose: dedupe first and you destroy the evidence you need to refuse.
sk_ids() {
  grep -oE "\*\*$2-[0-9]{3}\*\*" "$1" 2>/dev/null | sed -e 's/^\*\*//' -e 's/\*\*$//'
}

# sk_dupe_ids <spec.md> <FR|SC> — ids that appear more than once (empty = clean).
sk_dupe_ids() { sk_ids "$1" "$2" | sort | uniq -d; }

# sk_req_text <spec.md> <id> — the requirement's prose, markers stripped.
sk_req_text() {
  grep -m1 -E "\*\*$2\*\*" "$1" 2>/dev/null \
    | sed -e "s/^[[:space:]]*-[[:space:]]*\*\*$2\*\*:[[:space:]]*//" \
          -e 's/[[:space:]]*$//'
}

# sk_clarifications <feature-dir> — "file:line: text" for every unresolved [NEEDS CLARIFICATION.
sk_clarifications() {
  grep -rn '\[NEEDS CLARIFICATION' "$1" 2>/dev/null | sed "s|^$1/||"
}

# sk_measurable <text> — rc 0 if the text carries a numeric or comparator signal.
#
# THIS IS A HEURISTIC AND IT IS WRONG IN BOTH DIRECTIONS. "The operation is idempotent" is perfectly
# measurable and contains no digit; "the system handles 100 users" contains one and says nothing.
# So it may only WARN — never refuse. See the README's Guarantee|Enforcement table: this row proves
# a criterion *looks* measurable, and nothing more. A gate people learn to route around is worse
# than no gate at all.
sk_measurable() {
  printf '%s' "$1" | grep -qE '[0-9]|%|\bp[0-9]+\b|<=|>=|<|>|\bunder\b|\bwithin\b|\bat least\b|\bat most\b|\bno more than\b|\bfewer than\b|\bexceed'
}

# sk_paths <feature-dir> — every file/dir path the pack names (a token containing a "/").
# Fed verbatim to the REAL _high-stakes.sh; we never re-implement path classification.
sk_paths() {
  grep -ohE '([A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+' \
    "$1/plan.md" "$1/tasks.md" "$1/spec.md" 2>/dev/null | sort -u
}

# sk_title <spec.md> — "# Feature Specification: <Title>" → "<Title>".
sk_title() {
  grep -m1 '^# ' "$1" 2>/dev/null \
    | sed -e 's/^#[[:space:]]*//' -e 's/^Feature Specification:[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# sk_tasks <tasks.md> — the task text of each "- [ ] T### ..." line, [P]/[US#] markers stripped.
sk_tasks() {
  grep -E '^[[:space:]]*- \[[ xX]\] ' "$1" 2>/dev/null \
    | sed -e 's/^[[:space:]]*- \[[ xX]\][[:space:]]*//' \
          -e 's/\[P\][[:space:]]*//g' -e 's/\[US[0-9]*\][[:space:]]*//g' \
          -e 's/[[:space:]]*$//'
}

# --- the Jaimitos side -------------------------------------------------------------------------

# sk_phase_headings <roadmap> — every "## Phase ..." heading line.
sk_phase_headings() { grep '^## Phase' "$1" 2>/dev/null; }

# sk_next_phase_num <roadmap> — one past the highest "## Phase N" already present.
sk_next_phase_num() {
  local n
  n=$(sk_phase_headings "$1" | sed -e 's/^## Phase[[:space:]]*//' -e 's/[^0-9].*$//' \
        | grep -E '^[0-9]+$' | sort -n | tail -1)
  printf '%s\n' "$(( ${n:-0} + 1 ))"
}

# sk_norm <text> — lowercase, punctuation stripped, whitespace collapsed. For comparing GOALS.
# An exact-heading match is not enough: "## Phase 3 — Browse the Widget Catalogue" and the already
# COMPLETED "## Phase 1 — Browse the widget catalogue" are the same work under different numbers.
sk_norm() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9 ]/ /g' -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

# sk_phase_goal <heading> — "## Phase 3 — Widget Search" → "Widget Search".
sk_phase_goal() {
  printf '%s' "$1" | sed -e 's/^## Phase[[:space:]]*[0-9]*[[:space:]]*[—-][[:space:]]*//'
}

# sk_matching_phase <roadmap> <goal> — an existing phase whose GOAL normalizes to the same string.
# Prints the heading, rc 0 if found.
sk_matching_phase() {
  local rmap="$1" want; want=$(sk_norm "$(sk_phase_goal "$2")")
  local h
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    [ "$(sk_norm "$(sk_phase_goal "$h")")" = "$want" ] && { printf '%s\n' "$h"; return 0; }
  done < <(sk_phase_headings "$rmap")
  return 1
}
