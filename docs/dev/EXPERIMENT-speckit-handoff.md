# Maintainer note — the Spec Kit handoff experiment

**The experiment, its go/no-go bar, and its Guarantee|Enforcement table live in
[`experiments/speckit-handoff/README.md`](../../experiments/speckit-handoff/README.md).**
This file exists so a maintainer reading `docs/dev/` knows the experiment is there and knows the
three rules that govern it. It deliberately does **not** restate the contract — one meaning, one home.

## Why it is a directory at the repo root

`install.sh` reads exactly two source roots (`jaimitos-os/` and `skills/`), and
`jaimitos-os/scripts/test-skills.sh` check 4 asserts those two lines. A new repo-root directory is
therefore **structurally** unable to ship — the same guarantee that keeps the maintainer-only skills
in `.claude/skills/` out of user projects. It also means a REJECT verdict is one `git rm -r`, not an
excavation.

## The three rules

1. **Nothing from this experiment merges to `master` unless the verdict is PROMOTE.** That includes
   the conditional requirement-traceability section in `jaimitos-os/.claude/agents/evaluator.md` —
   the one shipped file the branch touches. "An experiment needed it" is not a justification for
   changing shipped behavior. If that section is good enough for core, it can survive being
   justified *as core*: its own version bump, its own CHANGELOG entry, its own review.

2. **The experiment never compensates for a core defect.** Designing the gate surfaced a real bug in
   the roadmap parser (prose containing `- [ ]` counted as an open task, and `tick.sh`'s `gsub`
   rewrote it). That was fixed in core, in its own release — **v2.11.2** — *before* this branch
   started. The gate's poison-line check remains only as defense in depth. If a future gate here
   exists to protect against something core gets wrong, that is a core fix, not a gate.

3. **The REJECT playbook has a trap.** `integrations/upstreams.lock.json` records the Spec Kit
   entry, and `test-skills.sh` check 5 asserts that every `jaimitos_files_influenced` path **still
   exists on disk**. Delete the experiment without removing the lockfile entry in the *same commit*
   and CI goes red. Removing it means:

   ```
   git rm -r experiments/ .claude/skills/import-speckit/
   # + drop the spec-kit entry from integrations/upstreams.lock.json
   # + revert the experiment-speckit CI job and the evaluator commit
   ```

## Where the tests run

The experiment has its **own** runner (`experiments/speckit-handoff/tests/run-experiment-tests.sh`)
with its own drift guard, and its **own** CI job (`experiment-speckit`). It is deliberately not in
`jaimitos-os/scripts/run-guard-tests.sh`: that runner's drift guard would force any `test-*.sh` in
`jaimitos-os/scripts/` into its list, and everything in that directory **ships**. Keeping the two
apart also means a red experiment reads as *the experiment is red*, and a REJECT deletes the job and
the directory together.

Core CI stays **offline**. The live tier (which installs the pinned Spec Kit CLI) runs only in the
experiment job, and reports honestly when it cannot run rather than passing silently.
