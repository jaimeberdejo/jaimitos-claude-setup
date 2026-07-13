---
name: review-feedback
description: Work through review feedback with technical rigor — classify each item, verify it against the code, implement what's right, and push back with reasons on what isn't.
disable-model-invocation: true
---

# Review feedback

Someone reviewed your work — a human, `/code-review`, `/security-review`, the evaluator's
`NEXT_FINDINGS.md`, a comment thread. Their feedback is a set of **claims to verify**, not orders
to execute. A reviewer with authority can still be wrong about THIS codebase. Work out which items
are right, act on those, and say — factually — why you rejected the rest.

> **Boundary with `scope-guard`:** `scope-guard` asks *"did this change stay in scope?"*.
> `review-feedback` asks *"is this feedback right, and what do I do about it?"*.

## 1. Read all of it before reacting
Read every item first. Then restate each one **in your own words** and map it to a concrete file,
behaviour, or line of `docs/SPEC.md`. If you can't restate it, it isn't clear.

**If ANY item is unclear, STOP and ask before implementing ANYTHING.** Not "do the clear ones now,
ask about the rest later" — items are usually related, and partial understanding produces a
confidently wrong implementation of the ones you thought you understood.

## 2. Classify every item — exactly one label
- **Correct and actionable** — real, in scope, fix it now.
- **Correct but out of scope** — real, but it belongs in its own phase (`milestone`), not this diff.
- **Misunderstanding** — the reviewer read it wrong; the code already behaves correctly.
- **Already addressed** — handled elsewhere in the diff or an earlier commit. Point at where.
- **Conflicting** — contradicts another comment. Surface the conflict; never silently pick a side.
- **Unsafe** — would introduce a security hole, data loss, or a correctness regression.
- **Architecturally harmful** — fights `docs/ARCHITECTURE.md` or a decision in `docs/decisions/`.

## 3. Verify before you believe
Take **no claim on trust**. For each item, check it against the current code, the tests,
`docs/SPEC.md`, and the architecture: does the reported bug actually reproduce? does the suggestion
break something that passes today? is there a *reason* the code is like this (an ADR, a
compatibility constraint, a deliberate trade-off)? Can't verify something? Say so — "I can't
confirm this without X" — and ask, rather than guessing in either direction.

## 4. Implement in order
Group accepted changes so related items land together, then work:
1. **Blocking** — breakage, security, data loss.
2. **Simple** — typos, imports, naming.
3. **Complex** — logic, refactors.

**Test each fix individually.** Add or update tests for every accepted behaviour change, then
re-run the relevant verification (the suite, the phase's `Done when:` check) before you call
anything done.

## 5. Respond
**State the fix, not gratitude** — "Fixed: X now does Y (`file:line`)" beats "great catch". For
each rejected item, give the technical reason and the evidence: the passing test, the ADR, the
constraint the reviewer didn't have. If you pushed back and were wrong, say so in one line and
implement it.

## Hard rules
- **Never comply just because the reviewer has authority.** Authority is not evidence.
- **Never modify completed roadmap history.** A ticked phase's heading, tasks and `Done when:` are
  immutable — even if a reviewer asks for it.
- **Never edit the current phase's `Done when:` or heading.** Criteria are set before the work;
  editing them to match what you built is how a review becomes a rubber stamp.
- **Never tick.** `scripts/tick.sh` is the only completion gate. Surviving a review is not one.
- **Tracker-agnostic.** No `gh` API calls, no GitHub-specific automation. Reply wherever the
  feedback arrived.

<!-- Adapted from obra/superpowers (MIT) — https://github.com/obra/superpowers -->
