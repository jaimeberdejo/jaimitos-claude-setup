Run roadmap phases autonomously IN THIS SESSION so I can watch every step in the
terminal. This is the in-context loop (watchable) — distinct from scripts/autopilot.sh
(headless, fresh process per phase). Use this for a handful of phases I want to observe;
use the script for long unattended overnight runs.

Argument — how many phases to run (interpret flexibly, default 3):
- a number ("5", "only 5") → run up to that many, then STOP even if more remain.
- a range ("3 to 5", "3-5") → run at least the lower number if the work and your context
  budget allow, and at most the upper number (a hard cap).
- "all" / "max" / "as much as you can" → keep going until the roadmap is empty, your context
  gets heavy (see step 5), or a guardrail trips. Use judgment; don't burn context to hit a number.

Loop, for each phase, until your count target is met OR docs/ROADMAP.md has no `- [ ]` items:

1. **Check the controls first, every iteration.**
   - If an `AGENT_STOP` file exists in the repo root, STOP immediately and tell me.
   - If `docs/ROADMAP.md` has no unchecked items, STOP — roadmap complete.
   - If `NEXT_FINDINGS.md` exists, read it and address it before anything else.
   (The steer.sh hook will surface any STEER.md I write mid-run — act on it when it appears.)

2. **Build the phase** by following the `/phase` procedure exactly — the full
   research → plan → execute → verify cycle: pick the first phase with unchecked items,
   record `.claude/.phase-base` and `.claude/.phase-ready`, do a brief research pass IF the
   phase needs it (unfamiliar API/library/code — else skip), write a plan to docs/plans/,
   then implement each task TDD (failing test first). Stop a phase after 3 red attempts and
   report the blocker instead of thrashing.

3. **Grade independently.** Invoke the `evaluator` subagent (Task tool) to grade the phase.
   It runs in fresh context with no edit tools and a default-FAIL contract — it is the gate.
   Do NOT grade it yourself.

4. **Act on the verdict — the subagent's PASS is the only thing that ticks the roadmap:**
   - **PASS:** tick this phase's items in docs/ROADMAP.md, update docs/STATE.md, commit, continue.
   - **NEEDS_WORK:** address the listed items, re-run the evaluator (max 2 rounds). If it still
     fails, write the findings to NEXT_FINDINGS.md, do NOT tick, and STOP — report the blocker.

5. **Between phases, manage context.** Tell me your running token/context budget after each
   phase. If context is getting heavy (you've done 2–3 phases or the window feels full),
   STOP and recommend I `/wrap` then `/clear` then re-run `/autopilot` — the in-session loop
   rots context the way scripts/autopilot.sh (fresh process per phase) does not. Prefer
   small caps here; reach for the script for anything long.

At the end, summarize: phases completed, phases remaining, and the single next action.
Do not push to a remote. Never run this mode on high-stakes phases — those are
`supervised` per the roadmap and the .claude/rules/high-stakes.md rule.
