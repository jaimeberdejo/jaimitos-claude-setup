---
name: mapme
description: Regenerates a one-page architecture map of the project from the actual current code. Use when re-entering a project after time away, onboarding, or after big changes — "map the project", "how does this fit together", "update the architecture doc", "give me the lay of the land". Reads code, does not trust stale docs.
---

# Map me

A one-page "how this fits together" doc is what lets you re-enter a project cold.
This regenerates it from the code as it actually is now — not from whatever the old
doc claimed. Run it whenever the mental map has gone fuzzy.

## Steps
1. **Survey the structure.** List the top-level dirs and key files. Identify the entry
   points (main, app factory, CLI, server, the graph's compile/run for agent projects).
2. **Trace the main flows.** For the 1–3 primary use cases, follow execution: where a
   request/input enters, what it passes through, where it exits. Use the real call graph,
   not assumptions — grep/read to confirm.
3. **Identify the boundaries.** The modules and their responsibilities, what depends on what,
   and where the seams are (interfaces, adapters, external services, the DB).
4. **Write `docs/ARCHITECTURE.md`** with these sections, kept to one page:
   - **One-paragraph overview** — what the system does, top down.
   - **Entry points** — where execution starts, with file:line.
   - **Module map** — each module: one line on responsibility + key files.
   - **Main data flow** — the primary path, as a short numbered list or a simple
     text/mermaid diagram.
   - **External dependencies** — DBs, APIs, services, and what they're used for.
   - **Where the risk lives** — the 2–3 most complex or consequential spots.

## For graph/agent projects (e.g. LangGraph)
Also emit a mermaid diagram of the node/edge structure — the graph IS the system,
so a picture of nodes, edges, and conditional routing is the single most useful artifact.
Read the graph definition to get it right; don't sketch from memory.

## Architectural friction
Reading the whole system is the only time you see its seams at once — so note the friction, but
**flag it, never fix it.** Vocabulary comes from `module-design`; use those words exactly:
- **Shallow module** — interface nearly as complex as the implementation it hides.
- **Pass-through layer** — forwards calls, adds no abstraction.
- **Leaky seam** — callers must know the internals to use it correctly.
- **Poor locality** — one concept smeared across many files; a change means shotgun surgery.
- **Oversized interface** — many entry points, most of them barely used.
- **Hidden dependency** — reaching into global state, env, or another module's internals.
- **Premature abstraction** — an extension point with exactly one implementation.
- **Excessive fragmentation** — files so small the structure costs more than it saves.
- **Domain-language mismatch** — the code's nouns disagree with `docs/GLOSSARY.md`.
- **Doc drift** — the previous ARCHITECTURE.md claims something the code no longer does.

**Deletion test** for anything you suspect is shallow: if you deleted it, would the complexity it
holds *concentrate* somewhere (it earns its keep) or just *move* one level up (it's a
pass-through)? Only "concentrates" defends a module.

Classify each finding **Strong** · **Worth exploring** · **Speculative** and report them to the
user with the map. Keep the doc to one page — at most, the Strong ones inform "Where the risk
lives". Then stop: **flagging is the deliverable.** Anything worth acting on becomes a design
session (`design-twice`) or a roadmap phase (`milestone`) — never an edit you make while mapping.

## Guardrails
- Regenerate from code every time; never just reformat the existing doc.
- **Never refactor while mapping.** A map that changed the territory is not a map.
- **Don't silently clobber a hand-authored doc.** If `docs/ARCHITECTURE.md` already exists, diff your
  regenerated version against it and show the user what materially changed (sections added, removed, or
  altered) BEFORE you overwrite — then get their OK, or write to `docs/ARCHITECTURE.new.md` for them to
  compare and swap in. Regenerating from code is right; replacing edits they made without showing them
  first is not.
- One page. If it's growing past that, link out to detail rather than inlining it.
- Flag anything you found that contradicts the previous ARCHITECTURE.md — drift is a signal.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
