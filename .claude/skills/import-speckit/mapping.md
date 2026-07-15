# Mapping a Spec Kit pack onto a Jaimitos phase

The mechanical rules the proposer already applies, and the judgement it hands you.

## The shape of an imported phase

```md
## Phase 7 — Widget Search
- [ ] T002 implement search_widgets(query, limit) in src/search/query.py
- [ ] T003 implement relevance ordering in src/search/ranking.py
Sources: specs/001-widget-search/spec.md specs/001-widget-search/plan.md
Requirements:
- FR-002 — System MUST order results by relevance, most relevant first.
- SC-001 — p95 search latency is under 200 ms against the 10k-widget fixture.
Done when: `pytest tests/test_search.py` is green and p95 latency < 200 ms on the 10k-doc fixture
Mode: loopable
```

`Sources:` and `Requirements:` are lines the roadmap linter ignores, so they cost nothing to add and
break nothing. `Done when:` and `Mode:` are the schema; the linter enforces them.

## What maps mechanically

| Spec Kit | Jaimitos |
|---|---|
| `# Feature Specification: <Title>` | the phase goal |
| `- [ ] T### [P] [US#] <text>` | a phase task (`[P]`/`[US#]` stripped — Jaimitos does not model them) |
| `**FR-###**`, `**SC-###**` | the `Requirements:` block |
| `spec.md`, `plan.md`, `tasks.md`, `contracts/` | the `Sources:` line |
| a high-stakes **path** in `plan.md`/`tasks.md` | `Mode: supervised` |

Keep the `T###` prefix on each task. It is how `speckit-converge.sh` later tells an upstream task
that landed from one that was added after the import.

## What does NOT map, and must not be faked

**Requirement → task attribution does not exist in a Spec Kit pack.** `tasks.md` carries `[US#]`
(user story), not `FR-###`. So when you split a feature across phases you are *deciding* which
requirements each phase owes — you are not reading it off the pack.

Do that honestly:

- A phase's `Requirements:` must list exactly what that phase is accountable for. The evaluator will
  check every id you write there against that phase's diff, and an id it cannot trace to code or a
  test is an unmet criterion.
- An `SC` that spans the whole feature (`SC-002: a user finds a known widget in under 10 seconds`)
  belongs on the phase that finally makes it true — usually the last one — not on every phase.
- If you cannot say which slice owes an id, **the split is wrong.** Do not spread the id across all
  slices to be safe; that fails every phase. Re-cut the phases, or import the feature as one.

## `Done when:` — write it so a person can check it

The default the proposer emits cites the SC ids and stops. That is enough to be *valid* and not
enough to be *useful*. Replace it with something observable, in this order of preference:

1. **A command and its result** — `` `pytest tests/test_search.py` is green ``
2. **A threshold you can measure** — `p95 latency < 200 ms on the 10k-doc fixture`
3. **An observable behavior** — `searching a term with no matches returns 200 and an empty list`

Never: "the feature works", "the code is clean", "SC-001 is met" (that is the id, not the check).

## Mode

`Mode: supervised` when the phase touches auth, migrations, money, deletes, secrets, or an external
side effect that MUTATES something outside our control (payments, emails, webhooks, deploys). The
gate catches these by **path**. You are responsible for the ones described only in prose — a task
that says "purge the audit log" names no path and the gate will not see it.

`Mode: loopable` otherwise. When you are unsure, choose `supervised`: the cost is a human glance;
the cost of the other mistake is an unattended agent doing something irreversible.
