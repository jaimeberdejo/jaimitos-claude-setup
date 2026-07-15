---
name: import-speckit
description: EXPERIMENTAL, maintainer-only. Hand a GitHub Spec Kit feature pack to the Jaimitos roadmap — validate it, preserve its FR/SC requirement ids, and propose phases. It proposes; it never writes docs/ROADMAP.md, and it can never tick.
disable-model-invocation: true
---

# Import a Spec Kit feature pack

**Experimental.** Part of `experiments/speckit-handoff/`, which does not ship. Read its
[README](../../../experiments/speckit-handoff/README.md) before using this — especially the
Guarantee|Enforcement table, which says plainly what is proved and what is merely asked.

You turn a Spec Kit feature pack into **proposed** Jaimitos roadmap phases. You do not implement,
you do not tick, and you do not edit `docs/ROADMAP.md`. A human appends the fragment.

## The line you do not cross

Jaimitos is the sole orchestrator. Spec Kit may **specify** and **report**.

`specs/<NNN>/tasks.md` is an **input**. `docs/ROADMAP.md` is the **queue**. If you ever find
yourself reading `tasks.md` to decide what to build next, stop — that is the failure mode this whole
experiment exists to test for (REJECT criterion R3).

## Run the gate FIRST — before you think about phases

```bash
bash experiments/speckit-handoff/bin/speckit-propose.sh \
  --pack <spec-kit-root> --feature <NNN-slug> --project . --out .speckit-handoff
```

| exit | what it means | what you do |
|---|---|---|
| **0** | importable | continue below |
| **1** | REFUSED | **stop.** Report the reason verbatim. Do not "work around" it, do not hand-write the fragment the gate just rejected. |
| **2** | usage error | fix the invocation |
| **3** | high-stakes paths | the fragment exists and every phase is `supervised`. **Present it and wait for an explicit human yes.** Do not apply it yourself. |

Read `.speckit-handoff/HANDOFF.md`. Its `## For human review` section is the list of things the gate
deliberately refused to decide — carry every one of them to the human. Do not quietly resolve them.

## What the gate cannot decide — and now you must

The gate proves shape. It cannot prove judgement. These four are yours, and each is a place you can
do real damage by being confident:

**1. Sizing.** The proposer emits **one phase for the whole feature**, deliberately: Spec Kit does
not link a requirement to a task, so any split has to *guess* which `FR`/`SC` each slice owes. If you
split it, you must attribute the requirements yourself, honestly — a phase must carry exactly the ids
it is actually accountable for. Give the evaluator a requirement the phase was never meant to satisfy
and you have manufactured a failure nobody introduced. When you cannot attribute an id to a slice,
that is a signal the split is wrong, not a rounding error.

**2. `Done when:`.** The linter proves it is non-empty. Nothing proves it is *observable*. The
default cites the SC ids; sharpen it into something a person could actually check. See
[mapping.md](mapping.md).

**3. Measurability.** `HANDOFF.md` may flag success criteria with no numeric signal. **The check is a
heuristic and it is wrong in both directions** — "the operation is idempotent" is measurable and has
no digit in it; "handles 100 users" has one and says nothing. Read each flagged criterion and decide.
Waive the false positives *out loud*, in your report, so the cost of the heuristic stays visible.

**4. Scope, and high-stakes intent.** Read `docs/SPEC.md`, especially **Non-goals**, against the
requirements. The gate does not judge this and does not pretend to. Separately: `_high-stakes.sh`
matches **paths, not intentions** — a feature that says "purge the audit log" but names no path will
not be caught. If the work is dangerous in intent, say so and mark the phase `supervised`.

## Then

Re-run the **same gate** on any fragment you wrote yourself — `speckit-gate.sh --fragment <file>`.
There is no bypass, and you do not get a friendlier gate for being the model.

Present the fragment, the review items, and this exact command. **The human runs it, not you:**

```bash
cat .speckit-handoff/roadmap.append.md >> docs/ROADMAP.md
```

## What you must never do

- Write `docs/ROADMAP.md`, `docs/STATE.md`, or `docs/SPEC.md`.
- Implement any of the tasks. `/phase` owns implementation.
- Tick anything. Only `scripts/tick.sh` writes `- [x]`, and only on an evaluator `PASS` plus green
  test evidence bound to `HEAD`. You cannot produce either, and you must not try.
- Re-import a feature the roadmap already has. The gate refuses this; do not route around it.
- Weaken a `Done when:` to make a phase easier to pass.

<!-- Experimental. Not shipped: install.sh reads only jaimitos-os/ and skills/. See
     experiments/speckit-handoff/README.md and integrations/upstreams.lock.json (github/spec-kit, MIT). -->
