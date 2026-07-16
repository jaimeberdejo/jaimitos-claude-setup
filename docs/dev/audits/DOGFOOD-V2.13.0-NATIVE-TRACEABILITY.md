# Dogfood — v2.13.0 native requirement traceability

Native `REQ/AC/OBJ` traceability exercised end-to-end on a realistic **account export & deletion**
scenario (the same shape as the Release 2 Spec Kit dogfood), in a throwaway project outside the toolkit.
Disposable project code stayed in scratchpad; only this report and the deterministic fixtures (in
`test-lint.sh`) are committed.

## Scenario

`docs/SPEC.md` defined `REQ-001` (export, `AC-001..003`), `REQ-002` (deletion — high-stakes/irreversible,
`AC-004..005`), and `OBJ-001`/`AC-006` (no external calls). `docs/ROADMAP.md` had two phases: **Phase 1 —
Account export** (`Mode: loopable`) and **Phase 2 — Account deletion** (`Mode: supervised`), each with a
`Sources: docs/SPEC.md` + `Requirements:` block naming exactly the ids it owns. A real installed layout
(`scripts/`, `.claude/lib/`, `docs/`) was assembled from the shipped files.

## Deterministic results (ran for real)

| Check | Result |
|---|---|
| `lint-roadmap.sh --strict` on the clean native flow | **exit 0** — schema + all ids valid |
| High-stakes deletion phase mode (`_roadmap.sh`) | parsed as **`supervised`** |
| `tick.sh "## Phase 1 …"` with a `Requirements:` block but no grade | **REFUSED** — "missing evaluator grade evidence" (requirement metadata alone cannot tick) |
| NEG — phase references an unknown id (`AC-999`) | `--strict` **exit 1**: "phase references AC-999 not defined in docs/SPEC.md" |
| NEG — malformed id (`ac-1`) | `--strict` **exit 1**: "malformed requirement id in phase: ac-1" |
| NEG — `Status: Approved` + blocking `[NEEDS CLARIFICATION]` | `--strict` **exit 1**: "requirement REQ-001 is Status: Approved but still carries [NEEDS CLARIFICATION]" |
| Restore clean flow | `--strict` **exit 0** |

The completion chain is unchanged: `tick.sh` still gates on evaluator PASS + fresh HEAD-bound evidence.
A `Requirements:` block adds no open tasks and cannot bypass the gate.

## Model-dependent result (the evaluator, exercised for real)

A subagent followed the **shipped** `evaluator.md` on a Phase-1 diff that implemented the export (AC-001,
AC-003) but left **AC-002 (owner-only download)** as a *comment only* — no authorization check, and a test
file that explicitly declined to cover it. The automated suite was green.

The evaluator, with traceability active because the phase declared `Requirements:`, produced:

- **AC-001 — SATISFIED** (with an honest caveat that "all supported data" is unverifiable from the diff, and
  that the test is implementation-coupled).
- **AC-002 — NOT SATISFIED**: "no authorization or authentication check anywhere … a comment only … cannot
  be traced to code or a test, so it fails Axis A exactly as a missing 'Done when:' would." It further named
  the comment-as-fix fakery pattern and the **IDOR-class data-export bypass** as a blocking Axis-B finding.
- **AC-003 — SATISFIED** (behavioral before/after snapshot test — sound).
- Final line: **`NEEDS_WORK: AC-002 owner-only authorization is unimplemented … and untested`.**

The green suite did **not** fool it: an untraceable acceptance criterion failed the phase, and the last-line
verdict is the exact non-`PASS` string that stops `record-grade.sh` recording a grade and `tick.sh` ticking.
The evaluator also honestly recorded a check it *could not* run in the standalone scenario (the
criteria-integrity `git diff`) — no overstatement.

## Comparison with the Release 2 Spec Kit dogfood

| Dimension | Release 2 (Spec Kit, rejected) | v2.13.0 native |
|---|---|---|
| Evaluator traceability benefit | Present | **Present — same benefit** (see above) |
| Always-loaded context tax | Spec Kit skill description(s), always loaded | **≈ 0** — guidance lives in skill/agent *bodies*; descriptions byte-unchanged |
| New artifact locations | `.specify/`, `specs/`, `tasks.md` (a second spec + task tree) | **none** — `docs/SPEC.md` gains an optional section; ids ride the existing `Requirements:` block |
| External runtime dependency | Spec Kit CLI + presets | **none** |
| Completion mechanism | risk of a second one | **unchanged** — `tick.sh` remains the sole gate |
| Ownership clarity | split across the tool and Jaimitos | **one owner per stage** — `to-spec` owns ids, roadmap owns assignment, evaluator owns satisfaction |
| Maintenance surface | CLI/preset/schema volatility | one `_requirements.sh` helper + prose; upgrade risk local |
| User effort (tiny work) | scaffolding to opt out of | **inert by default** — nothing required until you add ids |

## Limitations (honest)

- Deterministic validation checks id **structure and references only** — never that a requirement is
  *satisfied*, *complete*, or *measurable*. Those are evaluator/human judgment (and were shown to work here,
  but remain model-dependent, not guaranteed).
- Cross-reference resolution is enforced only for phases whose `Sources:` name `docs/SPEC.md` (or that have
  no `Sources:` and a spec with ids). A phase sourced from an external file is left to the evaluator — the
  helper cannot parse arbitrary external spec formats, by design.
- The `AC-001` caveat the evaluator raised (a test coupled to the implementation) is a genuine, general
  limitation of any single acceptance criterion — traceability surfaces it but cannot fix authoring quality.

## Verdict

Native traceability delivered the **same** evaluator benefit as the Spec Kit dogfood with **fewer artifacts,
zero always-loaded tax, no external CLI, and no second task queue or completion mechanism** — and did not
weaken any high-stakes protection (the deletion phase stayed `supervised`; `tick.sh` stayed the sole gate).
No dimension came out materially weaker.
