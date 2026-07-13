---
name: module-design
description: The deep-module vocabulary — depth, seam, leverage, locality, the deletion test. The shared language design-twice, the planner, the executor, the evaluator and mapme all judge in.
disable-model-invocation: true
---

# Module design

Shared language for designing **deep modules**: a lot of behavior behind a small interface, placed
at a clean seam, tested through that interface. This is a **reference, not a workflow** — it runs
no process, writes no artifact, and never ticks a phase. Use the words; apply the principles.

> **User-invoked on purpose (0 B always-loaded).** Every consumer — `design-twice`, `mapme`, the
> planner, the executor, the evaluator — reaches this file by explicit path, so none of them needs
> it to auto-fire. Paying for a description in the context window on every turn, forever, would buy
> nothing. Invoke it by name when you want the vocabulary directly.
> (v2.10.0 shipped it model-invoked; the independent review that v2.11.0 owed overturned that.)

**Project vocabulary wins.** If `docs/GLOSSARY.md` names a thing, use the project's word — never
let imported terminology override it.

## Vocabulary
Use these exactly. Don't substitute "component", "service", "API", or "boundary" — consistent
language is the whole point.

- **Module** — anything with an interface and an implementation. Scale-agnostic on purpose: a
  function, a class, a package, a tier-spanning slice.
- **Interface** — everything a caller must know to use the module correctly: the signature, but
  also invariants, ordering constraints, error modes, required config, performance characteristics.
  Not just the type-level surface.
- **Implementation** — what's inside. Orthogonal to size at the seam: a small **adapter** can have
  a large implementation (a Postgres repo), a large one a small implementation (an in-memory fake).
- **Adapter** — a concrete thing that satisfies an interface at a seam. Names a *role* (which slot
  it fills), not a substance (what's inside).
- **Depth** — leverage at the interface: how much behavior a caller (or a test) can exercise per
  unit of interface it must learn. **Deep** = much behavior, small interface. **Shallow** = the
  interface is nearly as complex as the implementation.
- **Seam** *(Feathers)* — a place where behavior can be altered without editing in that place; the
  location where a module's interface lives. Where the seam goes is its own decision, separate from
  what goes behind it.
- **Leverage** — what callers get from depth: one implementation pays back across N call sites and
  M tests.
- **Locality** — what maintainers get from depth: change, bugs, and verification concentrate in one
  place. Fix once, fixed everywhere.

## Principles
- **Depth is a property of the interface, not the implementation.** A deep module may be internally
  composed of small, swappable parts — they just aren't part of the interface. Internal seams
  (private, used by its own tests) are fine; don't expose them through the interface.
- **The deletion test.** Imagine deleting the module. If complexity vanishes, it was a pass-through.
  If complexity reappears across N callers, it was earning its keep. *(This is the canonical
  definition. `mapme` points here rather than restating it. The `evaluator` is the one documented
  exception: it restates the test inline because a grading contract must stand on its own — it is
  byte-checked as a gate-control file and cannot depend on reading a skill it might not open.)*
- **The interface is the test surface.** Callers and tests cross the same seam. If you need to test
  *past* the interface, the module is the wrong shape.
- **One adapter is a hypothetical seam; two is a real one.** Don't introduce a seam unless something
  actually varies across it.
- **Accept dependencies, don't create them.** `processOrder(order, gateway)` beats constructing a
  `StripeGateway` inside.
- **Return results rather than produce hidden side effects.** `calculateDiscount(cart): Discount`
  beats `applyDiscount(cart): void`.
- **Small surface area.** Fewer methods, fewer params — fewer tests, simpler setup.

## Anti-goals
- **No pass-through abstractions.** A wrapper that only forwards fails the deletion test.
- **No premature generic interfaces, no speculative abstraction.** "We might need X later" is not a
  seam.
- **No forced architectural rewrites.** This skill never justifies restructuring code the task
  didn't ask about — that's scope creep (`scope-guard`).
- **Don't require an interface where a concrete implementation is clearer.** Depth is not a quota.

## Rejected framings
- **Depth as a ratio of implementation lines to interface lines** (Ousterhout): rewards padding the
  implementation. Depth is leverage, not line count.
- **"Boundary"**: overloaded with DDD's bounded context. Say **seam**.

## Boundaries with neighboring skills
- `design-twice` **generates** two candidate designs, chooses, and records an ADR. `module-design`
  supplies the vocabulary it argues in — and the terms the `evaluator` grades against.
- `mapme` **documents what exists** (`docs/ARCHITECTURE.md`). This skill describes what good
  looks like.
- `module-design` **decides nothing and writes no artifact.**

## Going deeper
Deepening a cluster given its dependencies (dependency categories, seam discipline,
replace-don't-layer testing): [deepening.md](deepening.md).

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
