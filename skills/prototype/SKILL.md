---
name: prototype
description: Build throwaway code that answers one explicit design question, then throw it away and keep only the answer.
disable-model-invocation: true
---

# Prototype

A prototype is **throwaway code that answers ONE explicit question**. **State the question first,
before any code** — a prototype without a written question is unaccountable code, and one that
answers the wrong question is pure waste.

Questions worth a prototype:
- Is this integration technically possible?
- Does this state model behave correctly?
- Which interface is easiest to use?
- Can this performance target be reached?
- Which UI direction communicates the concept best?

## Why this is allowed at all
CLAUDE.md says: *"TDD always: a failing test before implementation. No exceptions on logic code."*
A prototype is the **sanctioned exception — precisely BECAUSE it is not production code and can
never become production evidence.** The moment its output is offered as proof that a feature works,
the exception is void and TDD applies in full.

## Pick the branch
Getting this wrong wastes the whole prototype. Pick by what the question is *about* — behavior →
logic; appearance → UI — not by what's easier to build.

**Logic / state-model prototype.** The question is about behavior, transitions, or data shape
("does this state machine survive X then Y?"). Build a **tiny interactive terminal app** that
pushes the state machine through the cases that are hard to reason about on paper: in-memory state,
one keystroke per action, full state re-rendered after each action, a one-line key legend at the
bottom. Keep the logic (a reducer, a state machine, a set of pure functions) separate from the
terminal shell: the shell is disposable, the validated logic is the finding.

**UI-direction prototype.** The question is what something should look like. Build **several (3;
cap at 5) radically different variations** — different layout, different information hierarchy,
different primary affordance, *not* different colors — switchable from one place (e.g. a `?variant=`
param plus a floating switcher). Variants that differ only in styling are wallpaper, not a prototype.

Ambiguous and the user is away? Follow the surrounding code (a module → logic, a page → UI) and
state the assumption at the top of the prototype.

## Rules
1. **Throwaway from day one, and clearly marked.** The name and the top-of-file header say PROTOTYPE.
2. **Isolated from production and runtime paths** — `/tmp`, a temp branch, or a separate worktree.
   Never on any path the app, the build, or the test suite loads.
3. **One command to run it.** The user must never have to remember a path.
4. **No persistence** unless persistence *is* the question — then a scratch store named so it is
   obviously disposable.
5. **Skip the polish.** No abstractions, no broad error handling, no tests for the prototype's own
   sake. The point is to learn fast.
6. **Surface the full relevant state** after every action or variant switch. A state change nobody
   can see teaches nothing.
7. **Delete it when done — or explicitly archive it** (throwaway branch, pointer in the record).
   **Never leave debug routes, temporary interfaces, or prototype flags behind in production.**

## Record the outcome
Five lines, wherever the work lives: **Question · Experiment · Result · Limitations · Decision.**

Then transfer only *validated learning*: into `docs/SPEC.md`, an ADR (the `adr` skill), or the
roadmap (the `milestone` skill). The code does not graduate — it was written under prototype rules.
Rewrite it test-first if it becomes real.

## Evidence rule
- Prototype tests and outputs **MAY** serve as evidence for an **explicitly scoped
  prototype/research phase** — one whose `Done when:` asks for an *answer*, not a feature.
- Prototype tests and outputs **MAY NEVER** satisfy production implementation or release criteria.
  A green prototype is not a passing test suite.
- **This skill never ticks a phase.** `scripts/tick.sh` is the only gate, and the `evaluator` grades
  production criteria against production code.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
