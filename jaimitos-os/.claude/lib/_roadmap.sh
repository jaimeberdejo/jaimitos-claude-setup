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
  h=$(awk '/^## /{h=$0} /^[[:space:]]*- \[ \] /{if(h!=""){print h; exit}}' "$f")
  [ -n "$h" ] || return 1
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
  PH="$heading" awk '
    $0==ENVIRON["PH"] {inphase=1; next}
    /^## / && inphase {inphase=0}
    inphase && /- \[ \]/ {c++}
    END {print c+0}
  ' "$f"
}

return 0 2>/dev/null || exit 0
