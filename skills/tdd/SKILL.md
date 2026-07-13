---
name: tdd
description: The red → green loop plus what makes a test worth keeping — seams, anti-patterns, mocking rules. Use when building test-first — "tdd", "red-green", "test-first", "write the failing test first". The executor agent follows this as its TDD manual.
---

# TDD

TDD is the red → green loop. This skill is the reference that makes the loop produce tests worth
keeping: what a good test is, where tests go, the anti-patterns, and the rules of the loop.
Consult [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking rules.

Name tests in the project's own vocabulary — check `docs/GLOSSARY.md` if it exists — and respect
ADRs in `docs/decisions/` for the area you're touching.

## What a good test is
Tests verify behavior through public interfaces, not implementation details. A good test reads
like a specification — "user can checkout with valid cart" — and survives refactors because it
doesn't care about internal structure.

## Seams — where tests go
A **seam** is the public boundary you test at. Tests live at seams, never against internals, and
seams are **pre-agreed, not improvised mid-loop**:
- If `docs/SPEC.md`'s `## Test seams` section (written via `to-spec`) or the phase's plan under
  `docs/plans/` already names the seams, **use those — do not re-ask.** They were confirmed when
  the spec/plan was written.
- Only when neither names a seam: propose the fewest that cover the work (ideal: one), confirm
  with the user, and note the choice in the plan file so the next cycle doesn't re-litigate it.

## Anti-patterns (the evaluator grades against these — teaching and grading are symmetric)
- **Implementation-coupled** — mocks internal collaborators, tests private methods, or verifies
  through a side channel (querying the DB instead of the interface). Tell: the test breaks on a
  refactor when behavior didn't change.
- **Tautological** — the assertion recomputes the expected value the way the code does
  (`expect(add(a,b)).toBe(a+b)`), so it passes by construction and can never disagree with the
  code. Expected values come from an independent source: a known-good literal, a worked example,
  the spec.
- **Mocking the subject under test** — the thing the task asked to build is itself mocked, so the
  test cannot fail.
- **Horizontal slicing** — all tests first, then all implementation. Bulk tests verify *imagined*
  behavior and commit you to structure before understanding. Work in **vertical slices**: one
  test → one implementation → repeat, each test a tracer bullet.

## Rules of the loop
- **Red before green.** Failing test first, then only enough code to pass it.
- **The red must be meaningful.** Run the test, watch it fail, and confirm it failed *for the
  reason you intended* — because the behavior is missing. A failure from a typo, a bad import, or
  a broken fixture is not red, it's broken: fix it and re-run until it fails correctly. A test
  that passes on its first run is testing behavior that already existed — the seam is wrong.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle. Commit each
  green slice (small, single-purpose commits).
- **Green means green, and quiet.** The targeted test passes *and* the output is clean. New errors
  or warnings are a finding, not noise.
- **Then run the wider suite.** A targeted green proves the slice; only the relevant wider suite
  proves you broke nothing else. The slice isn't done until both are green.
- **Protect existing behavior.** When you change something that already works, its regression test
  comes first — that red is what proves the old behavior was real.
- **Stuck at red after 3 attempts?** Stop and report the blocker — never skip ahead or weaken the
  test to get past it.
- **Refactoring is not part of the loop.** It's a separate, deliberate pass after green — with
  the tests as the safety net.

## When production code has to come first
Sometimes it genuinely does: a `prototype` whose behavior can't be named until it runs, generated
code, a config change with no seam. That's allowed — **but the exception is explicit, never
silent.** Record which code preceded its test, why no red was reachable first, and which test
covers it now. An unrecorded exception isn't an exception; it's just skipped TDD.

**Never claim TDD was followed if no meaningful red was ever observed.** "The tests pass" is not
evidence of TDD: a test written after the code passes on its first run and proves nothing about
whether it can fail.

## Evidence
When a phase asks you to show the loop was real, this is the shape. Keep it in the artifacts the
phase already has (the plan file, the commit message) — a two-line change does not need its own
evidence file.

```md
### TDD evidence
- Behavioral seam:
- Red command:
- Observed failure:
- Why the failure was expected:
- Minimal implementation:
- Green command:
- Wider verification:
- Exception, if any:
```

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
