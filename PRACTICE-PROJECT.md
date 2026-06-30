# Practice Project — learn the lean-stack hands-on (then delete this)

> **This file is a standalone, throwaway tutorial — safe to delete completely once you've
> test-driven the setup.** Nothing in the scaffold depends on it, and `install.sh` does NOT
> copy it into real projects (it lives at the repo root, outside `lean-stack/`).

A small, self-contained project to learn the whole stack on — not tied to anything real.
A CLI + API that suggests a secondhand-marketplace listing price from an item description,
~4 phases you can build in an evening. Low stakes (no money moves, fully reversible) so you
can safely try the autopilots, steering, and the kill-switch.

## How to use it
1. Make a throwaway repo and install the scaffold into it:
   ```bash
   mkdir /tmp/prendapricer && cd /tmp/prendapricer && git init
   bash ~/my-claude-code-setup/install.sh .
   ```
2. Follow the four sessions below.
3. When you're done learning, `rm -rf /tmp/prendapricer` (and delete this file). Done.

---

## The spec (drop into `docs/SPEC.md`)
```md
# Spec: PrendaPricer

## What & why
A CLI + FastAPI service that suggests a listing price for a secondhand clothing item,
given a structured description (category, brand tier, condition, era/style tags).

## Success criterion (measurable)
Given the 20-item fixture set in tests/fixtures/items.json, the suggested price is within
±20% of the labelled "good_price" for at least 15 of 20 items.

## In scope
- Pure pricing function: features in → price + confidence out.
- A rules+heuristics baseline (no ML in v1).
- CLI (`prendapricer "item desc"`) and POST /price endpoint.

## Non-goals
- No scraping of live marketplace data in v1 (use the fixture set).
- No image input, no persistence in v1.

## Constraints
- Python 3.12, FastAPI, pytest. Money as Decimal, never float.
- Pricing logic must be a pure, unit-tested function.
```

## The roadmap
Run the **`roadmap`** skill on that spec. It will recommend a granularity — for this scope,
~4 fine phases — and write them with `Done when:` lines and loopable/supervised tags, e.g.:
```md
## Phase 1 — Pricing core         (Mode: loopable)
- [ ] ItemFeatures + PriceSuggestion dataclasses
- [ ] suggest_price() with base-by-category + brand/condition/era multipliers
- [ ] Unit tests for each multiplier + an end-to-end example
Done when: pytest passes and suggest_price() returns a Decimal + confidence for a sample item.

## Phase 2 — Evaluation harness    (Mode: loopable)
- [ ] tests/fixtures/items.json (20 labelled items)
- [ ] eval test asserting ≥15/20 within ±20% of good_price
Done when: the eval test runs and reports the hit rate.

## Phase 3 — Interfaces            (Mode: supervised — touches I/O)
- [ ] CLI entrypoint + POST /price endpoint + TestClient test
Done when: curl to /price returns a valid suggestion and the CLI works.

## Phase 4 — Hardening             (Mode: loopable)
- [ ] input validation + 422; README with the eval hit rate; tune multipliers to pass the eval
Done when: full suite green, eval criterion met, README written.
```

## Build it across four sessions
```
Session 1 — scaffold + Phase 1 (manual, learn the rhythm)
  /resume → plan → "implement phase 1, TDD" → @evaluator grade → /wrap → /clear

Session 2 — Phase 2 watchable
  /resume → /autopilot 1   (watch it build fixtures + the eval test) → /wrap → /clear

Session 3 — Phase 3 supervised
  /resume → /phase → curl the endpoint + run the CLI yourself → /wrap → /clear

Session 4 — Phase 4 headless
  bash scripts/autopilot.sh 2
  # if it overfits: echo "Keep multipliers interpretable; don't overfit the fixtures." > STEER.md
```
At the end you have a working, tested, documented tool with a full git checkpoint history,
ADRs, and a STATE.md you could hand to a stranger.

## What you'll have learned
Measurable success criteria · phase boundaries that each leave a working program · TDD as the
loop's truth source · the evaluator catching premature "done" · running a phase watchable and
headless · steering and stopping a loop.

## Graduating to high-stakes work
Apply the same stack to real work with one change for anything consequential: **drop autopilot
for high-stakes/irreversible code** (auth, migrations, money, deletes, external effects). Use
`/phase` supervised, keep `permission_mode: default`, require review before merge, and let git
history + ADRs be your audit trail. The `high-stakes.md` rule encodes this — point its `paths:`
at your dirs.
