# Personal Skills — general-purpose dev workflow

> Part of **[my-claude-code-setup](../README.md)** — see the repo-root README for the full
> picture and how these pair with the lean-stack scaffold.

Six portable, stack-agnostic skills for any Claude Code project. Single-file each,
no dependencies, no project specifics. They encode workflows the base model doesn't
reliably do unprompted.

| Skill | Fires when you... | What it does |
|---|---|---|
| **roadmap** | have a spec, need phases | Turns docs/SPEC.md into docs/ROADMAP.md — 4–6 phases, each with a measurable "Done when:" and a loopable/supervised tag |
| **adr** | make a real decision | Writes a terse 4-line ADR to docs/decisions/ |
| **ship-check** | are about to commit/PR | Runs the project's tests/lint/typecheck + scans for debug leftovers, secrets, missing docs. Verdict: READY / NOT READY (report-only; can't edit) |
| **scope-guard** | finish a change | Flags out-of-scope edits, drive-by refactors, unexpected deletions. Verdict: IN SCOPE / SCOPE CREEP (report-only; can't edit) |
| **explain-diff** | want a self-review | Summarizes what changed and, mainly, where it might be wrong (risks, assumptions, untested paths) (report-only; can't edit) |
| **unstick** | are going in circles | Stops the thrash: restates the goal, names the shared failing assumption, proposes fresh hypotheses + the cheapest next test |

## Design principles
- **Report-only where it matters.** The three review skills (ship-check, scope-guard,
  explain-diff) set `disallowed-tools: Edit, Write, MultiEdit, NotebookEdit` in their
  frontmatter — so they *cannot* modify code, only report. Fixing is a separate, deliberate step.
- **Portable.** They read commands from your CLAUDE.md/README rather than hardcoding a
  stack, so the same skill works in a Python service and a Next.js app.
- **Small.** One file each — low context cost, easy to read and adapt. Edit them; they're yours.

## Install
Per-project (committed with the repo, travels with the code):
```bash
mkdir -p .claude/skills
cp -r roadmap adr ship-check scope-guard explain-diff unstick .claude/skills/
```
Or globally for all projects, in your user-level skills directory:
```bash
cp -r roadmap adr ship-check scope-guard explain-diff unstick ~/.claude/skills/
```

## Use
They auto-trigger on the phrases in each skill's description, or invoke by name:
```
ship-check                 # before committing
scope-guard                # after a change, before commit
explain-diff               # self-review
unstick                    # when the same fix keeps failing
"log this decision: ..."   # adr
```

## A natural sequence
A clean end-of-task ritual chains three of them:
```
scope-guard   →   explain-diff   →   ship-check
(stayed on task)  (what's risky)     (verified + ready)
```
Run that before any commit and most of what slips through review gets caught first.
