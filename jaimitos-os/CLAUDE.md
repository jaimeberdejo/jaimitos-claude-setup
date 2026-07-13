# Project: <NAME>

## Commands
- Test: <pytest -q  |  npm test>
- Typecheck: <mypy .  |  npm run typecheck>
- Lint/format: <ruff check . && ruff format .  |  npm run lint>
- Run: <uvicorn app.main:app --reload  |  npm run dev>

## Working agreement
- TDD always: a failing test before implementation. No exceptions on logic code.
- Sole exception — `prototype`: throwaway, isolated from production/runtime paths, never
  accepted as production implementation evidence.
- One feature/phase per session. Small, single-purpose commits.
- At session start, read docs/SPEC.md, docs/ROADMAP.md, docs/STATE.md.
- Real decisions get a 4-line ADR in docs/decisions/.
- Touch src/, tests/, docs/ freely. Project config/manifests (package.json,
  pyproject.toml, lockfiles, migrations, *.example env) only when the task needs
  it, and call it out. Never touch unrelated files.
- Never edit the current phase's `Done when:` line or heading in docs/ROADMAP.md
  while building it — you must not weaken the criteria you're graded against.
- High-stakes/irreversible code (auth, migrations, money, deletes, external side effects that
  MUTATE something outside our control — payments, emails, webhooks, deploys): supervised only —
  no autopilot, smallest phases, `permission_mode: default`, human approval before merge. A
  read-only/idempotent external call (a GET against public data) is NOT automatically high-stakes
  on that basis alone — judge it on its own actual blast radius. (Also in
  .claude/rules/high-stakes.md.)

## Docs are the source of truth (not this file, not your memory)
- docs/SPEC.md     = what we're building and why; non-goals
- docs/ROADMAP.md  = ordered phases, each with "Done when:"
- docs/STATE.md    = where we are right now + the single next action
- docs/decisions/  = ADRs (one file each)

## Autonomy
- **All ticking goes through `scripts/tick.sh`** — the single gate that flips `- [ ]` → `- [x]`.
  No command, prompt, or model may mark a phase done without passing it. `/phase` builds; it
  never ticks.
- The `evaluator` subagent grades completion independently — never mark a phase done on the
  builder's say-so alone.
- `touch AGENT_STOP` halts any loop at the next tool call (`rm` it to resume); write STEER.md
  to redirect a running loop.
- **Closing a milestone / bumping VERSION / tagging is its own checkpoint:** state that question
  explicitly and wait for an explicit yes — never inferred from a broader "go ahead"/"continue",
  even when the roadmap's last phase just ticked. (Loop mechanics: toolkit-docs GUIDE Parts 4–5.)

## Ownership (understand what gets built)
- Before /wrap on a non-trivial phase, run `teach-back` — Claude explains it and
  quizzes you; gaps go in docs/STATE.md under "## Ownership gaps".
- Record decisions with the `adr` skill, always including the alternative rejected.
- After big changes, run the `mapme` skill to refresh docs/ARCHITECTURE.md from the code.
- Periodically (or before an interview) run `quizme` to measure understanding.
- Build high-stakes code (auth, migrations, money, deletes) in the smallest phases and be
  able to explain it line by line. See `.claude/rules/high-stakes.md`.
