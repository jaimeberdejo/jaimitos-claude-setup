---
description: STOP — implementation in this project is owned by Jaimitos, not Spec Kit.
---

# Implementation is not yours

**Do not write code from here. Do not tick anything in `tasks.md`.**

This project is orchestrated by Jaimitos. Spec Kit specifies; Jaimitos executes. That split is the
whole point of the integration, and this command is the one place it would quietly break down.

## Why you are being stopped

`specs/<NNN>/tasks.md` is an **input**. `docs/ROADMAP.md` is the **queue**. If work starts here:

- it never enters the roadmap, so nobody can see what is in flight;
- it is never graded by the `evaluator`, so nothing checks it against the acceptance criteria;
- it produces no test evidence bound to `HEAD`, so `scripts/tick.sh` will refuse to mark it done
  anyway — and you will have written code that the project cannot complete.

You would be building a second, unsupervised queue inside a system that has exactly one.

## What to do instead

1. Hand the feature pack to the roadmap:

   ```
   import-speckit
   ```

   It validates the pack, preserves the `FR-`/`SC-` ids, and proposes phases. A **human** appends
   them to `docs/ROADMAP.md`.

2. Then build one phase, the normal way:

   ```
   /phase
   ```

   That runs the planner, the executor, and an independent evaluator, and only then does
   `scripts/tick.sh` mark the phase done — on a `PASS` plus green tests.

## If you think this is wrong

Say so and stop. Do not implement "just this once" and do not edit `docs/ROADMAP.md` to make room
for what you were about to build. If Spec Kit should own implementation in this project, that is a
decision for a human to make by removing this preset — not for you to make by ignoring it.
