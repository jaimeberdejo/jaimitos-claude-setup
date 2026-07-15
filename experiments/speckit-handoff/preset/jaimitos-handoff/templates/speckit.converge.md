---
description: Report-only convergence. Assess the codebase against the feature pack — and change nothing.
---

# Convergence is a REPORT here, not a repair

Upstream, `/speckit-converge` **appends new tasks to `tasks.md`** so `/speckit-implement` can finish
them. In this project that is exactly the wrong move: it would grow a second queue behind the
roadmap's back and hand it to an executor that is not allowed to run.

**Do not write to `tasks.md`. Do not write code. Do not touch `docs/ROADMAP.md`.**

## What to do

Run the Jaimitos convergence report, which is read-only by construction:

```
bash experiments/speckit-handoff/bin/speckit-converge.sh --pack <root> --feature <NNN-slug> --project .
```

It writes a report and nothing else. Its exit code carries the finding:

| exit | meaning |
|---|---|
| 0 | no blocking gaps |
| 1 | gaps or drift found |
| 2 | usage / malformed input |
| 3 | a stale or frozen conflict a human must look at |

## Then hand the gaps to the roadmap, not to an executor

If the report shows unbuilt requirements, that is **new roadmap work**, and it enters the queue the
same way all work does:

```
import-speckit          # propose phases; a human appends them
/phase                  # build one, graded, then ticked by scripts/tick.sh
```

A requirement with no implementation is a phase nobody has planned yet. It is not a task for you to
pick up here.

## The boundary, stated plainly

You may **read** the codebase, `spec.md`, `plan.md`, `tasks.md`, and `docs/ROADMAP.md`.
You may **report** what is missing, partial, drifted, or unrequested.

You may not implement, tick, reopen a completed phase, weaken a requirement, or declare anything
complete. Completion has exactly one author in this project — `scripts/tick.sh` — and it will not
take your word for it.
