# Ownership Skill Pack

Three skills for actually understanding code Claude helped build — so you can
debug it, extend it, defend it in an interview, and (for regulated code) be
accountable for it.

| Skill | Use when | Does |
|---|---|---|
| **teach-back** | after a phase, before /wrap | Claude explains the build, then quizzes you one question at a time; weak answers become a reading list |
| **mapme** | re-entering a project / after big changes | Regenerates docs/ARCHITECTURE.md (one page) from the real code; emits a graph diagram for LangGraph-style projects |
| **quizme** | periodically / before an interview | Generates a cold-open quiz from the codebase, grades honestly, scores your understanding. Has an "interview mode" |

## The principle
Ownership comes from **active recall**, not passive reading. A wall of generated
comments or a giant wiki is something you trust instead of understand — the opposite
of ownership. teach-back and quizme make you produce the explanation; that's what sticks.

## Wiring (already done in the lean-stack scaffold)
- session-start hook loads the ARCHITECTURE.md overview each session.
- Stop hook (ownership-nudge.sh) reminds you to ADR decisions, run teach-back, and /mapme after code changes.
- CLAUDE.md has an Ownership section pointing at the workflow.

## Install (if using standalone)
    cp -r teach-back mapme quizme .claude/skills/      # per project
    cp -r teach-back mapme quizme ~/.claude/skills/     # or global

## The ritual that protects ownership
    build a SMALL phase  →  teach-back (explain + quiz)  →  adr (record why)  →  /wrap
    ...and every week or two:  quizme  (cold open, find the gaps)
Smaller phases + teach-back is the whole game. The less Claude builds before you
engage, the more you keep.
