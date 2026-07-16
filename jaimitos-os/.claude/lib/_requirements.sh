#!/usr/bin/env bash
# _requirements.sh — SHARED, focused validator for native requirement ids (sourced, not a hook).
#
# This is the smallest helper that owns REQ/AC/OBJ id SEMANTICS, so lint-roadmap.sh stays the
# roadmap-schema linter and does NOT become the parser/owner of docs/SPEC.md. lint-roadmap.sh
# sources this file and calls `requirements_lint`, which validates whenever a roadmap phase declares
# a `Requirements:` line OR the spec defines ids; it is a no-op (rc 0, no output) when neither holds,
# so it is inert in a default project.
#
# It validates STRUCTURE only — never semantic satisfaction, completeness, measurability, or test
# quality (those stay evaluator + human judgment). Concretely it checks:
#   - malformed ids, and duplicate ids inside one roadmap phase's `Requirements:` block
#   - each roadmap-referenced id resolves to a definition in docs/SPEC.md — but only for a phase whose
#     ONLY named source is the spec (its `Sources:` names docs/SPEC.md and no external file, or it has
#     no `Sources:` and the spec has a Requirements section). A phase that also names an external file
#     is left to the evaluator to resolve — this helper cannot parse an arbitrary external source.
#   - in docs/SPEC.md: duplicate REQ/OBJ ids; AC ids duplicated ANYWHERE (globally unique); and a
#     `Status: Approved` requirement whose text still carries `[NEEDS CLARIFICATION` (a strict
#     validation failure — a Proposed/Clarifying one may keep the marker).
#
# Native ids are REQ-###, AC-###, OBJ-### (the ### is one or more digits). An external id
# (FR-001, REQ-AR-001, JIRA-1234) is accepted STRUCTURALLY — a generic PREFIX-### shape — only when
# the authoritative source defines it; this helper hard-codes the semantics of no external prefix.
#
# Pure awk/grep, bash-3.2 / BSD-userland / non-root mawk safe. Regexes go to awk via ENVIRON, never
# -v (awk processes escapes in a -v assignment and would mangle the `[`/`\`); ENVIRON is literal.

# A native id: exactly one of REQ/AC/OBJ, then a dash and digits.
REQ_NATIVE_RE='^(REQ|AC|OBJ)-[0-9]+$'
# A structurally valid id of any prefix: an uppercase-alnum prefix (optionally hyphen-segmented),
# ending in a numeric segment. Matches REQ-001, AC-002, FR-001, REQ-AR-001, JIRA-1234.
REQ_GENERIC_RE='^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*-[0-9]+$'
export REQ_NATIVE_RE REQ_GENERIC_RE

# Task-line detection reuses the ONE shared task regex from _roadmap.sh — the project forbids
# hand-writing a task-line regex outside that file (test-roadmap-lib.sh enforces it). Source it if a
# caller has not already; if it is unavailable, a leading `[` checkbox token is still recognized so an
# adjacent task line is never misread as a requirement ref.
if [ -z "${ROADMAP_TASK_RE:-}" ]; then
  _req_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || _req_dir=""
  if [ -n "$_req_dir" ] && [ -f "$_req_dir/_roadmap.sh" ]; then . "$_req_dir/_roadmap.sh" 2>/dev/null || true; fi
fi

# requirements_lint <roadmap-file> [spec-file]
#   Prints "  ! <problem>" lines for every id problem found. Default spec-file is SPEC.md beside the
#   roadmap. rc 0 = clean (INCLUDING "no Requirements: block anywhere" — inert). rc 1 = problems.
requirements_lint() {
  local road="$1" spec="${2:-}"
  [ -f "$road" ] || return 0
  if [ -z "$spec" ]; then spec="$(dirname "$road")/SPEC.md"; fi

  local specarg=""
  [ -f "$spec" ] && specarg="$spec"

  # Inert unless there is something native to validate: a roadmap phase that declares Requirements:,
  # OR a spec that defines ids (so the spec-internal checks — dup / AC-uniqueness / Approved+
  # clarification — fire as soon as ids exist, not only once a roadmap phase references them).
  if ! grep -qE '^[[:space:]]*Requirements:[[:space:]]*$' "$road" 2>/dev/null; then
    { [ -n "$specarg" ] && grep -qE '^###[[:space:]]+(REQ|AC|OBJ)-|^[[:space:]]*-[[:space:]]+AC-' "$specarg" 2>/dev/null; } || return 0
  fi

  local out
  out=$(SPECF="$specarg" GEN_RE="$REQ_GENERIC_RE" NAT_RE="$REQ_NATIVE_RE" TASK_RE="${ROADMAP_TASK_RE:-}" awk '
    function prob(m) { problems[++np] = "  ! " m }

    # Strip <!-- ... --> (single- and multi-line) using a persistent in-comment state, so a
    # commented example in the SPEC template is never read as a real definition.
    function stripcom(line,   out,p) {
      out=""
      while (1) {
        if (incom) { p=index(line,"-->"); if (p==0) return out; line=substr(line,p+3); incom=0 }
        else       { p=index(line,"<!--"); if (p==0) return out line; out=out substr(line,1,p-1); line=substr(line,p+4); incom=1 }
      }
    }
    function firsttok(s,   a,n) { gsub(/^[[:space:]]+/,"",s); n=split(s,a,/[[:space:]]/); return a[1] }

    # flush the current SPEC requirement block: enforce Approved + [NEEDS CLARIFICATION]
    function flush_req() {
      if (cur_req != "" && cur_status == "Approved" && cur_clar)
        prob("requirement " cur_req " is Status: Approved but still carries [NEEDS CLARIFICATION] in docs/SPEC.md")
      cur_req=""; cur_status=""; cur_clar=0
    }
    # flush the current ROADMAP phase: cross-ref its refs against SPEC defs when spec-sourced
    function flush_phase(   i,id) {
      if (cur_phase == "" ) return
      # Cross-ref only when docs/SPEC.md is the ONLY source a phase names (a phase that also names an
      # external file is left to the evaluator — we cannot parse the external source), or when a phase
      # names no source at all and the spec defines ids.
      spec_sourced = 0
      if (phase_src_spec && !phase_src_other) spec_sourced = 1
      else if (!phase_has_sources && spec_has_req) spec_sourced = 1
      if (spec_sourced && SPEC != "")
        for (i=1;i<=nref;i++) { id=ref[i]; if (!(id in defall)) prob("phase references " id " not defined in docs/SPEC.md — " cur_phase) }
      cur_phase=""; phase_has_sources=0; phase_src_spec=0; phase_src_other=0; in_src=0; in_req=0; nref=0; delete refseen
    }

    BEGIN { SPEC=ENVIRON["SPECF"]; GEN=ENVIRON["GEN_RE"]; NAT=ENVIRON["NAT_RE"]; np=0; incom=0 }

    # ---------------- SPEC pass (ARGV[1], read first) ----------------
    SPEC != "" && FILENAME==SPEC {
      a = stripcom($0)
      if (a ~ /^[[:space:]]*$/) next
      # A requirement/objective definition heading: "### REQ-001 — title" / "### OBJ-002 — ..."
      if (a ~ /^###[[:space:]]+/) {
        flush_req()
        h=a; sub(/^###[[:space:]]+/,"",h); id=firsttok(h)
        # A def heading is one whose first token is a valid id (native OR external), or LOOKS like a
        # native id attempt (so a malformed REQ-ABC is flagged, while prose like "### Edge cases" is
        # left alone — its first word matches neither).
        if (id ~ GEN || id ~ /^(REQ|AC|OBJ)-/) {
          spec_has_req=1
          if (id !~ GEN) prob("malformed id in docs/SPEC.md heading: " id)
          else {
            if (id ~ /^AC-/) { if (id in acall) prob("duplicate AC id " id " (AC ids must be unique across the whole spec)"); acall[id]=1 }
            else if (id in defall) prob("duplicate id " id " defined in docs/SPEC.md")
            defall[id]=1
            if (id ~ /^(REQ|OBJ)-/) cur_req=id
          }
        }
        next
      }
      if (a ~ /^##[[:space:]]/) { flush_req(); next }
      # Status line inside a requirement block
      if (cur_req != "" && a ~ /^[[:space:]]*Status:[[:space:]]*/) {
        s=a; sub(/^[[:space:]]*Status:[[:space:]]*/,"",s); s=firsttok(s); cur_status=s; next
      }
      if (cur_req != "" && a ~ /\[NEEDS CLARIFICATION/) cur_clar=1
      # An acceptance-criterion definition bullet: "- AC-001: ..."
      if (a ~ /^[[:space:]]*-[[:space:]]+AC-/) {
        spec_has_req=1
        b=a; sub(/^[[:space:]]*-[[:space:]]+/,"",b); id=firsttok(b); sub(/:.*/,"",id)
        if (id !~ GEN) prob("malformed AC id in docs/SPEC.md: " id)
        else { if (id in acall) prob("duplicate AC id " id " (AC ids must be unique across the whole spec)"); acall[id]=1; defall[id]=1 }
      }
      next
    }

    # ---------------- ROADMAP pass ----------------
    /^## / { flush_phase(); flush_req(); cur_phase=$0; next }
    cur_phase=="" { next }
    /^[[:space:]]*Sources:[[:space:]]*$/  { in_src=1; in_req=0; phase_has_sources=1; next }
    /^[[:space:]]*Requirements:[[:space:]]*$/ { in_req=1; in_src=0; next }
    # classify each Sources: bullet — is it docs/SPEC.md, or some external file?
    in_src && /^[[:space:]]*-[[:space:]]/ {
      sp=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",sp); sp=firsttok(sp)
      if (sp ~ /(^|\/)docs\/SPEC\.md$/) phase_src_spec=1; else phase_src_other=1
      next
    }
    # a task line ends any Sources/Requirements block; it is never a requirement ref (shared regex)
    ENVIRON["TASK_RE"] != "" && $0 ~ ENVIRON["TASK_RE"] { in_src=0; in_req=0; next }
    # collect Requirements: ref bullets
    in_req && /^[[:space:]]*-[[:space:]]/ {
      b=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",b); id=firsttok(b)
      if (id ~ /^\[/) { in_req=0; next }   # a task checkbox, not a ref (robust even if TASK_RE is empty)
      if (id !~ GEN) prob("malformed requirement id in phase: " id " — " cur_phase)
      else { if (id in refseen) prob("duplicate id " id " in one phase Requirements: block — " cur_phase); refseen[id]=1; ref[++nref]=id }
      next
    }
    # any other line ends the inline Sources/Requirements bullet region
    { in_src=0; in_req=0 }

    END { flush_phase(); flush_req(); for (i=1;i<=np;i++) print problems[i]; exit (np>0?1:0) }
  ' ${specarg:+"$specarg"} "$road")
  local rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"
  return $rc
}

# requirements_orphans <roadmap> [spec] — ADVISORY coverage check (v2.14.0): a REQ/OBJ defined and still
# ACTIVE in docs/SPEC.md (Status not Rejected/Superseded/Deferred) that NO roadmap phase references is an
# "orphan" — approved but with no planned work. A requirement is covered if its own id OR any of its child
# AC ids appears in a phase's `Requirements:` block. Prints "  ~ <id> …" lines. Always rc 0: an orphan is a
# planning gap to surface, never a build blocker (a spec may legitimately hold not-yet-scheduled work).
# This complements requirements_lint (which checks refs→defs); orphans are the reverse, defs→refs.
requirements_orphans() {
  local road="$1" spec="${2:-}"
  [ -f "$road" ] || return 0
  if [ -z "$spec" ]; then spec="$(dirname "$road")/SPEC.md"; fi
  [ -f "$spec" ] || return 0

  local out
  out=$(SPECF="$spec" GEN_RE="$REQ_GENERIC_RE" awk '
    function stripcom(line,   out,p) {
      out=""
      while (1) {
        if (incom) { p=index(line,"-->"); if (p==0) return out; line=substr(line,p+3); incom=0 }
        else       { p=index(line,"<!--"); if (p==0) return out line; out=out substr(line,1,p-1); line=substr(line,p+4); incom=1 }
      }
    }
    function firsttok(s,   a,n) { gsub(/^[[:space:]]+/,"",s); n=split(s,a,/[[:space:]]/); return a[1] }
    BEGIN { SPEC=ENVIRON["SPECF"]; GEN=ENVIRON["GEN_RE"]; incom=0; ndef=0; cur="" }

    # ---- SPEC pass (read first) ----
    FILENAME==SPEC {
      a=stripcom($0); if (a ~ /^[[:space:]]*$/) next
      if (a ~ /^###[[:space:]]+/) {
        h=a; sub(/^###[[:space:]]+/,"",h); id=firsttok(h)
        if ((id ~ /^(REQ|OBJ)-/) && id ~ GEN) { cur=id; if (!(id in seendef)) { seendef[id]=1; deford[++ndef]=id; defstatus[id]="" } }
        else cur=""
        next
      }
      if (a ~ /^##[[:space:]]/) { cur=""; next }
      if (cur!="" && a ~ /^[[:space:]]*Status:[[:space:]]*/) { s=a; sub(/^[[:space:]]*Status:[[:space:]]*/,"",s); defstatus[cur]=firsttok(s); next }
      if (a ~ /^[[:space:]]*-[[:space:]]+AC-/) { b=a; sub(/^[[:space:]]*-[[:space:]]+/,"",b); id=firsttok(b); sub(/:.*/,"",id); if (cur!="") acparent[id]=cur }
      next
    }

    # ---- ROADMAP pass ----
    /^## /                                     { in_req=0; next }
    /^[[:space:]]*Requirements:[[:space:]]*$/  { in_req=1; next }
    /^[[:space:]]*Sources:[[:space:]]*$/       { in_req=0; next }
    in_req && /^[[:space:]]*-[[:space:]]/ {
      b=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",b); id=firsttok(b)
      if (id ~ /^\[/) { in_req=0; next }
      ref[id]=1; next
    }
    { in_req=0 }

    END {
      for (i=1;i<=ndef;i++) {
        id=deford[i]; st=defstatus[id]
        if (st ~ /^(Rejected|Superseded|Deferred)$/) continue
        covered = (id in ref)
        if (!covered) for (ac in acparent) if (acparent[ac]==id && (ac in ref)) { covered=1; break }
        if (!covered) print "  ~ " id " is defined and active in docs/SPEC.md but no roadmap phase plans it (orphan requirement)"
      }
    }
  ' "$spec" "$road")
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

return 0 2>/dev/null || exit 0
