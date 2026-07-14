#!/usr/bin/env bash
# _roadmap.sh — SHARED, fail-closed roadmap phase parser (sourced, not a hook).
#
# ONE parser for the phase heading / Mode: / task structure of docs/ROADMAP.md, replacing the several
# ad-hoc awk copies that lived in tick.sh, close-milestone.sh and (absent entirely) autopilot.sh and
# had drifted. Pure awk/grep — NO Markdown-parser dependency, bash-3.2 / BSD-userland safe.
#
# A "phase" is a `## ` heading line and every line under it up to the next `## ` heading. Its Mode is
# the `Mode:` line(s) inside that block; its open tasks are `- [ ]` lines inside that block.
#
# Fail-closed philosophy: an ambiguous or malformed phase must never be silently read as "safe". The
# functions distinguish three outcomes — a clean answer (rc 0), "nothing here" (rc 1, benign), and a
# CONFIGURATION ERROR (rc 2) that callers MUST treat as a hard stop, never as "not supervised".

# --- THE definition of a task line -------------------------------------------------------------
# A task is a list item at the START of a line. A line that merely CONTAINS the substring "- [ ]"
# — prose, a quoted example, a "Done when:" that talks about checkboxes — is NOT a task: a roadmap
# is allowed to talk about its own notation.
#
# These two constants are the ONLY place that is written down. Before them there were eight
# hand-copied variants across five files; the anchored ones (lint-roadmap.sh) and the unanchored
# ones (this library's open count, and tick.sh's gate, counts AND its gsub) had drifted apart, so
# prose mentioning "- [ ]" was counted as an open task, silently rewritten to "- [x]", and could
# tick a phase that had no real work in it. Every core consumer now goes through these functions.
#
# Passed to awk via ENVIRON, never -v: awk processes escape sequences in a -v assignment, and would
# mangle the `\[`. ENVIRON values are taken literally.
ROADMAP_OPEN_RE='^[[:space:]]*- \[ \] '        # an OPEN task
ROADMAP_TASK_RE='^[[:space:]]*- \[[ xX]\] '    # any task line, open or done
export ROADMAP_OPEN_RE ROADMAP_TASK_RE

# roadmap_next_open_heading <roadmap-file>
#   Prints the first `## ...` heading that still has an open task. rc 1 if none.
#   No uniqueness check — that is roadmap_first_open_heading's job, for callers that will KEY on the
#   heading. Use this one for display/reporting, where an ambiguous roadmap is not a hard stop.
roadmap_next_open_heading() {
  local f="$1" h
  [ -f "$f" ] || return 1
  h=$(RE="$ROADMAP_OPEN_RE" awk '/^## /{h=$0} $0 ~ ENVIRON["RE"] {if(h!=""){print h; exit}}' "$f")
  [ -n "$h" ] || return 1
  printf '%s\n' "$h"
}

# roadmap_first_open_task <roadmap-file>
#   Prints the TEXT of the first open task (the checkbox prefix stripped). rc 1 if none.
roadmap_first_open_task() {
  local f="$1" t
  [ -f "$f" ] || return 1
  t=$(RE="$ROADMAP_OPEN_RE" awk '$0 ~ ENVIRON["RE"] {sub(ENVIRON["RE"], ""); print; exit}' "$f")
  [ -n "$t" ] || return 1
  printf '%s\n' "$t"
}

# roadmap_open_total <roadmap-file>
#   Prints the number of open tasks in the WHOLE file (0 if none / no file). rc 0 always.
roadmap_open_total() {
  local f="$1"
  [ -f "$f" ] || { echo 0; return 0; }
  RE="$ROADMAP_OPEN_RE" awk '$0 ~ ENVIRON["RE"] {c++} END {print c+0}' "$f"
}

# roadmap_tick_phase <roadmap-file> <exact-heading>
#   Prints the roadmap to stdout with every OPEN TASK LINE inside that phase flipped to "- [x]".
#   Pure: it never touches the input file — the caller redirects to a temp and validates.
#   rc 1 if the file is missing.
#
#   Only anchored task lines are rewritten. Prose inside the block — including prose that mentions
#   "- [ ]" — is emitted byte-for-byte. (The sub is on `[ ]`, not `- [ ]`, and fires only on a line
#   already known to BE an open task, so the first `[ ]` on it is necessarily the checkbox.)
roadmap_tick_phase() {
  local f="$1" heading="$2"
  [ -f "$f" ] || return 1
  PH="$heading" RE="$ROADMAP_OPEN_RE" awk '
    $0==ENVIRON["PH"] {inphase=1; print; next}
    /^## / && inphase {inphase=0}
    inphase && $0 ~ ENVIRON["RE"] {sub(/\[ \]/, "[x]")}
    {print}
  ' "$f"
}

# roadmap_first_open_heading <roadmap-file>
#   Prints the EXACT `## ...` heading of the first phase that still has an open `- [ ]` item.
#     rc 0 + heading  — found
#     rc 1            — no phase has an open item (roadmap complete / nothing to build)
#     rc 2            — the file is missing, OR that heading text is not a UNIQUE full line (every
#                       downstream consumer keys on `$0==heading`, so a duplicated heading would match
#                       two different blocks — ambiguous, fail closed).
roadmap_first_open_heading() {
  local f="$1" h
  [ -f "$f" ] || { echo "roadmap: no such roadmap file: $f" >&2; return 2; }
  h=$(roadmap_next_open_heading "$f") || return 1
  if [ "$(grep -cxF -e "$h" "$f" 2>/dev/null)" != "1" ]; then
    echo "roadmap: phase heading is not a unique line (ambiguous): $h" >&2
    return 2
  fi
  printf '%s\n' "$h"
}

# roadmap_phase_mode <roadmap-file> <exact-heading>
#   Prints the phase's Mode value, lowercased.
#     rc 0 + "loopable"|"supervised"  — exactly one Mode: line, known value
#     rc 0 + ""                       — NO Mode: line in the block (UNCLASSIFIED). Callers decide:
#                                       tick.sh treats absence as loopable (unchanged legacy behavior);
#                                       the headless pre-build gate REFUSES to build an unclassified
#                                       phase (Mode is mandatory per the roadmap template + skill).
#     rc 2                            — file missing, OR more than one Mode: line in the block, OR a
#                                       Mode: value that is neither loopable nor supervised. An unknown
#                                       token must NEVER be waved through as "not supervised".
roadmap_phase_mode() {
  local f="$1" heading="$2" modes n val
  [ -f "$f" ] || { echo "roadmap: no such roadmap file: $f" >&2; return 2; }
  modes=$(PH="$heading" awk '
    $0==ENVIRON["PH"] {inphase=1; next}
    /^## / && inphase {inphase=0}
    inphase && /^[[:space:]]*Mode:/ {
      v=$0; sub(/^[[:space:]]*Mode:[[:space:]]*/,"",v); sub(/[[:space:]]*$/,"",v); print tolower(v)
    }
  ' "$f")
  [ -n "$modes" ] || return 0   # no Mode: line — empty output, rc 0 (unclassified)
  n=$(printf '%s\n' "$modes" | grep -c .)
  if [ "$n" != "1" ]; then
    echo "roadmap: phase has $n Mode: lines (ambiguous): $heading" >&2
    return 2
  fi
  val="$modes"
  case "$val" in
    loopable|supervised) printf '%s\n' "$val" ;;
    *) echo "roadmap: invalid Mode value '$val' in '$heading' (expected loopable|supervised)" >&2; return 2 ;;
  esac
}

# roadmap_open_count <roadmap-file> <exact-heading>
#   Prints the number of open `- [ ]` items in the phase block (0 if none). rc 0 always.
roadmap_open_count() {
  local f="$1" heading="$2"
  [ -f "$f" ] || { echo 0; return 0; }
  PH="$heading" RE="$ROADMAP_OPEN_RE" awk '
    $0==ENVIRON["PH"] {inphase=1; next}
    /^## / && inphase {inphase=0}
    inphase && $0 ~ ENVIRON["RE"] {c++}
    END {print c+0}
  ' "$f"
}

return 0 2>/dev/null || exit 0
