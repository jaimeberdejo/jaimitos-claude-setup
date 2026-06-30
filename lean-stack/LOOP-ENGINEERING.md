# Loop Engineering for Claude Code

A standalone guide to designing, running, and trusting autonomous loops. Pairs with the lean-stack scaffold (`autopilot.sh`, the `evaluator` subagent, the kill-switch/steer hooks).

Loop engineering is the discipline of getting an agent to do many steps of work unsupervised *without* it rotting its context, burning your budget, or lying about being done. The code is the easy part — the engineering is in the guardrails.

---

## Part 1 — The one idea

An autonomous loop is just your manual loop with the human replaced by two things: a **stopping condition** and a **verifier**.

```
        ┌──────────────────────────────────────────────┐
        │  read state  →  pick next task  →  do it      │
        │       ↑                              ↓        │
        │   update state  ←  PASS ── verify ── run it   │
        │       ↑               │                       │
        │       └──── fix ◄── NEEDS_WORK (bounded)      │
        └──────────────────────────────────────────────┘
                 exit when: queue empty │ max iters │ kill-switch
```

Everything else in this guide is detail on those five nouns: **state, task, verifier, stopping condition, fix-bound.** Get those right and the loop is safe. Get any one wrong and it's the horror story (the $4k weekend, the 14,000 identical tool calls, the agent that declared a broken build "done").

---

## Part 2 — The four loop architectures

There are four ways to build a loop, from least to most robust. Pick by stakes and length.

### Architecture 1 — In-context prompt loop (smallest)
You tell Claude to keep going within a single session.
```
"Work through docs/ROADMAP.md. For each unchecked task: implement TDD, run tests,
tick it on green, continue. Stop after 3 red attempts or when the roadmap is empty.
Don't ask me between tasks."
```
- **Pros:** zero setup, instant.
- **Cons:** one context window — it rots as it fills; relies on Claude *choosing* to run tests (advisory, ~80% reliable); no independent grader.
- **Use for:** a handful of small, related tasks in one sitting.

### Architecture 2 — `/goal` (built-in, supported)
Claude Code's native goal command. You give a **verifiable completion condition**; after each turn a separate fast model (Haiku) judges met/not-met and feeds the reason back until satisfied or you hit a turn cap.
```
/goal all pytest tests in tests/ pass and ruff reports no errors, or stop after 25 turns
```
- **Pros:** official, low eval cost, survives resume.
- **Critical limit:** the evaluator **can't run tools** — it only reads what Claude surfaced in the transcript. So the condition must be something Claude's own output *demonstrates*. "Tests pass" works only if Claude actually ran them and printed the result. Pair with a real verifier (Architecture 4) for anything you can't eyeball in the transcript.
- **Use for:** mechanical, self-evident goals in one session (formatting sweeps, making a known-failing suite green).

### Architecture 3 — Stop-hook loop (Ralph-style, one context)
A `Stop` hook that exits non-zero forces Claude to continue instead of ending the turn. This is what the official `ralph-wiggum` plugin uses. Runs until a completion sentinel appears or max-iterations trips.
- **Pros:** no external script; runs hands-free.
- **Cons:** still one context window (rot risk on long runs); the loop and the worker share state.
- **Use for:** medium mechanical jobs where a single context can hold the whole task.

### Architecture 4 — Fresh-context script loop (most robust — your `autopilot.sh`)
A shell loop spawns a **brand-new `claude` process each iteration.** State lives in files + git between iterations, so context never accumulates. A **separate** `claude --agent evaluator` process grades each iteration independently.
```bash
for i in $(seq 1 "$MAX_ITER"); do
  [ -f AGENT_STOP ] && break
  grep -q '\- \[ \]' docs/ROADMAP.md || break        # queue empty
  claude -p "/phase" --permission-mode acceptEdits
  VERDICT=$(claude --agent evaluator -p "grade the last phase" | tail -5)
  echo "$VERDICT" | grep -q NEEDS_WORK && echo "$VERDICT" > NEXT_FINDINGS.md
done
```
- **Pros:** no context rot (fresh window every loop — this is the Anthropic "engineers working in shifts" pattern), independent grader, OS-level control flow, git checkpoints as undo stack.
- **Cons:** a few more moving parts; re-establishes context each loop (cheap, since state is on disk).
- **Use for:** overnight builds, whole milestones, anything long. **This is the default for serious autonomy.**

The jump from 1/2/3 to 4 is the jump from "demo" to "trustworthy." The reason is context: architectures 1–3 degrade as the window fills; architecture 4 starts every iteration fresh and carries state through files. That single property is what GSD's fresh-subagent machinery was really buying — and you get it here in 30 lines of bash.

---

## Part 3 — The five guardrails (non-negotiable)

A loop without these is how you get the horror stories. Each maps to a noun from Part 1.

### 1. A verifiable success signal (the verifier)
The loop must check itself against something with an **exit code**, not a vibe. `pytest` returning 0 is a signal; "looks done" is not. This is why TDD and autonomy are inseparable — the tests are the loop's truth source. If a task has no automatable check, it doesn't belong in an autonomous loop; do it supervised.

### 2. A bounded stopping condition
Always bounded, never open-ended. Good: "until ROADMAP empty," "max 15 iterations," "until the eval test passes." **Fatal:** "keep improving the codebase" — that's the prompt that runs till your budget dies. The `autopilot.sh` first argument is your iteration cap; set it deliberately.

### 3. Bounded retries (the fix-bound)
On failure, cap attempts (3 is a good default), then **stop and report** rather than thrash. Thrashing is where both tokens and context quality die — an agent making the same failing edit 14,000 times is a retry-bound failure. Ralph's philosophy is "fail predictably, feed the failure forward": on NEEDS_WORK, write the findings to a file and let the next fresh iteration start from them.

### 4. A blast-radius limit
Constrain what the loop can touch, run, and reach:
- **Files:** "touch only src/, tests/, docs/" (in `/phase` and CLAUDE.md).
- **Commits:** commit after every green step so `git reset` always returns you to safety. The git history *is* your undo stack.
- **Permissions:** `acceptEdits` on a dev machine; `bypassPermissions` **only** inside a sandboxed container/CI, never on your laptop.
- **Worktree:** run long loops in a `git worktree` so a bad run can't corrupt your main checkout.

### 5. An independent verifier (not the builder)
The agent that grades completion must not be the agent that did the work. Three properties make the `evaluator` *much harder to fool* (not impossible — nothing is): **fresh context** (it didn't watch the build, so it can't be primed), **no Write/Edit tools** (it can't "fix" things into passing), and a **default-FAIL contract** (every criterion starts false; evidence is required to flip it). This is the single most important guardrail against hallucinated "done." Note the layering in autopilot: `/phase` runs an in-session evaluator subagent and only ticks the roadmap on its PASS; the script then runs a **second, separate-process** evaluator as defense-in-depth — if that one returns NEEDS_WORK, the loop stops for you to review rather than charging ahead.

### Plus: the kill-switch and the budget backstop
- `touch AGENT_STOP` blocks the *next* tool call and every one after (the PreToolUse hook fires before each tool use). It can't claw back a tool call already in flight, but it stops the loop dead within one step. Your seatbelt.
- A hard daily spend cap in your Claude Code config or gateway is the outer backstop that catches everything the in-loop guards miss. **Set it before your first overnight run, not after.**

---

## Part 4 — State that survives across iterations

In architecture 4, each iteration is amnesiac — fresh context, no memory of the last. So **all continuity lives on disk.** Three files carry it:

| File | Role in the loop | Who writes it |
|---|---|---|
| `docs/STATE.md` | "where we are + next action" — read first each iteration | `/wrap`, Stop hook |
| `docs/ROADMAP.md` | the work queue; `- [ ]` items are what's left | `/phase` ticks on PASS |
| `NEXT_FINDINGS.md` | the previous evaluator's NEEDS_WORK notes | the loop script |
| git history | the actual work + the undo stack | commit-on-stop hook |

The `session-start.sh` hook re-injects STATE + open roadmap items + recent commits into context at the top of every fresh iteration — so even though the process is new, it opens already oriented. This is the mechanism that lets a 15-iteration overnight run behave like one coherent effort instead of 15 disconnected ones.

The mental model (Anthropic's, and it's the right one): **engineers working in shifts.** Each new shift arrives with no memory of the last, reads the handoff notes (STATE, ROADMAP, git log), does one unit of work, writes its own handoff notes, and clocks out. Your job as loop engineer is to make the handoff notes good enough that the next shift never needs to ask what happened.

---

## Part 5 — Designing a loopable phase

Not all work is loopable. A phase is safe to automate when it has all four:

1. **A machine-checkable done condition.** "Eval test asserts ≥15/20 within ±20%" — yes. "Looks polished" — no.
2. **Bounded scope.** One vertical slice. If a phase touches 30 files, split it; fresh-context loops do best with small, self-contained units.
3. **Independent verifiability.** The evaluator can confirm it from the diff + a command, without trusting the builder.
4. **Low or reversible blast radius.** A bad result is caught by tests and undone by `git reset` — nothing irreversible happened (no migration run against prod, no money moved, no email sent).

If a phase fails any of these, run it supervised. The skill of loop engineering is largely **deciding what *not* to loop.**

A good loopable phase, written for the queue:
```md
## Phase 4 — Hardening
- [ ] Input validation + 422 on bad input
- [ ] README with usage + current eval hit rate
- [ ] Tune multipliers until the eval test passes
Done when: full suite green AND eval test passes AND README exists.
```
Every item is checkable, the scope is one slice, the evaluator can verify each, and nothing is irreversible. Textbook loopable.

---

## Part 6 — Running a loop, start to finish

### Pre-flight (every time)
```bash
git status                         # clean tree — loops commit, so start from known-good
git worktree add ../run-x HEAD     # optional: isolate long runs
# confirm budget cap is set in config
grep -c '\- \[ \]' docs/ROADMAP.md # how many open items? sanity-check your iter cap
```

### Launch
```bash
bash scripts/autopilot.sh 8        # cap = a bit above the number of phases you expect
```

### While it runs (monitoring)
- `tail -f autopilot.log` — watch builder turns and evaluator verdicts.
- See it heading wrong? `echo "constraint or correction" > STEER.md` — injected next turn, then cleared.
- Need to abort? `touch AGENT_STOP` — stops at the next tool call. `rm AGENT_STOP` to resume.

### Post-run review
```bash
git log --oneline                  # what got built, one commit per green step
git diff main...HEAD               # the whole change, if on a worktree/branch
cat docs/STATE.md                  # where it ended up
# anything you dislike → git reset --hard <last good commit>
```
Then merge or PR. Never let a loop push to main directly; review the branch.

---

## Part 7 — Failure modes and their fixes

| Symptom | Root cause | Fix |
|---|---|---|
| Quality drops late in a long run | Context rot (architecture 1–3) | Switch to fresh-context loop (arch 4); smaller phases |
| Burned the budget overnight | Open-ended stopping condition | Bound it: max-iters + budget cap + queue-empty check |
| Same failing edit repeated | No retry bound; thrashing | Cap fix attempts (3); on fail, write findings + stop |
| Marked a broken build "done" | Builder graded itself | Independent fresh-context evaluator, default-FAIL |
| `/goal` thinks it's done but isn't | Evaluator can't run tools, judged the transcript | Make the condition transcript-evident, or use arch 4 |
| Touched files it shouldn't | No blast-radius limit | Constrain paths; run in a worktree; review diff |
| Can't tell what it did | Weak handoff notes | Stronger STATE.md + commit-per-step + autopilot.log |
| Loop won't stop | Stop hook re-triggering | Check `stop_hook_active` guard (already in commit-on-stop.sh) |

---

## Part 8 — Matching loops to stakes

The skill of loop engineering is largely deciding *what not to loop*. Sort your work by stakes.

### Low-stakes, reversible work — loop freely
No irreversible side effects, easy to `git reset`, no consequential surface. Run `autopilot.sh` on whole milestones overnight. Good loopable phases: building UI components page-by-page, adding tests, accessibility passes, copy/i18n sweeps, mechanical refactors with full coverage. Let it run; review the branch in the morning.

### High-stakes work — loop the mechanical, gate the consequential
This is where loop engineering becomes risk engineering. Split the work:

**Safe to loop (supervised autopilot, you review each merge):**
- Scaffolding + its unit tests
- CRUD + schema/validation code
- Refactors with full test coverage
- Typecheck/lint/test-fixing phases

**Never loop (human-in-the-loop, `permission_mode: default`):**
- Anything moving money, touching auth, or with regulatory/legal weight
- Database migrations against shared/prod data
- Irreversible deletes or external side effects (payments, emails, deploys)
- Logic whose *correctness is a judgment call*, not a test assertion

The posture is **human-on-the-loop**: the loop *generates and surfaces* the consequential diffs; you *approve* them. Keep the audit trail intact — git history + ADRs give you per-change attribution to a human. Set the loop's blast radius so it physically *cannot* execute the consequential class of action (e.g. no prod credentials in the loop's environment), so a guardrail slip can't become an incident. (The `.claude/rules/high-stakes.md` rule encodes this for whatever paths you mark.)

The rule, compressed: **automate the typing, never the judgment.** A loop is fantastic at writing the tenth thing to match the first nine. It has no business deciding something that needs a human to be accountable for it.

---

## Part 9 — Quick reference

```
ARCHITECTURES   1 in-context prompt   (tiny, one sitting)
                2 /goal               (mechanical, transcript-evident)
                3 stop-hook / ralph   (medium, one context)
                4 fresh-context script (long, robust — autopilot.sh)   ← default for real autonomy

FIVE GUARDRAILS verifiable signal · bounded stop · bounded retries · blast-radius limit · independent verifier
PLUS            kill-switch (AGENT_STOP) · budget cap (set it first!)

LOOPABLE PHASE  machine-checkable done · bounded scope · independently verifiable · reversible

RUN             pre-flight (clean tree, worktree, cap) → autopilot.sh N → monitor (tail/steer/stop) → review branch → merge

NEVER LOOP      money · auth · prod migrations · compliance judgment        → human-in-the-loop

ONE LINE        Automate the typing, never the judgment.
```

---

### The loop engineer's creed
A loop is only as trustworthy as its weakest guardrail. Give it a signal it can't fake, a stop it can't outrun, a grader it can't fool, a blast radius it can't exceed, and a switch you can always reach — then let it work while you sleep. Everything else is tuning.
