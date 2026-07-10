# Repository-wide audit — `jaimeberdejo/jaimitos-claude-setup`

**Audited revision:** `master` at `07bba1c0ddc3da0d3c6ac61babc02f8d1d2f8f62`  
**Declared version:** `2.6.0`  
**Audit date:** 2026-07-10  
**Method:** complete tracked-file review through the GitHub repository API, architectural mapping, implementation-versus-documentation comparison, historical design review, and focused destructive reproductions in isolated temporary Git repositories.

## Audit confidence legend

- **Confirmed:** directly established from implementation or reproduced in an isolated test.
- **Repository-reported:** stated by the repository’s current CI configuration, changelog, or historical audit, but not independently rerun in this environment.
- **Inferred:** follows directly from a reachable code path but was not exercised end to end.
- **Unverified:** depends on a live Claude Code, Docker, GitHub Actions, or operating-system environment unavailable during this audit.

## Scope and exclusions

The audit covered the repository root, scaffold, commands, all four agents, hooks, shared libraries, operational scripts, all 17 guard suites, installer smoke checks, both CI workflows, all 18 skills and their support files, templates, sandbox, synchronization logic, contributor/security documentation, changelog, historical implementation plans, and historical audits/dogfood reports.

The following were grouped rather than individually evaluated as runtime components:

- `LICENSE`: legal boilerplate, no runtime behavior.
- Historical plans and audits under `docs/dev/`: read to reconstruct design decisions and identify intentionally deferred findings, but not treated as current sources of runtime truth.
- Runtime artifacts such as `.claude/.phase-base`, `.claude/.phase-grade`, `.claude/.tick-evidence.json`, `NEXT_FINDINGS.md`, and `autopilot.log`: not tracked by design; their producers, consumers, validation rules, and failure paths were audited.
- There are no vendored dependency trees, generated binaries, lockfiles, or material binary assets in the repository.

---

# 1. Executive summary

## Purpose

`jaimitos-claude-setup` is a personal Claude Code operating system for turning an idea into a specification, roadmap, bounded implementation phases, independent evaluation, evidence-backed completion, and milestone archival. It combines:

1. A project scaffold installed by `install.sh`.
2. Project commands such as `/resume`, `/phase`, `/wrap`, `/autopilot`, and `/autopilot-parallel`.
3. Four staged agents: researcher, planner, executor, and evaluator.
4. Hooks for context loading, steering, formatting, emergency stopping, checkpointing, and ownership reminders.
5. Deterministic shell gates for tests, secret scanning, high-stakes detection, completion, synchronization, and health checks.
6. Seventeen per-project skills plus one installer skill.
7. A headless execution mode with worktrees, a lock, watchdogs, control-file integrity checks, and evaluator rollback.

## Maturity

This is substantially more mature than a normal personal prompt collection. It has a coherent state model, deterministic completion gate, unusually good adversarial shell tests, conservative synchronization, and honest documentation about several limitations. The repository has clearly been dogfooded and repeatedly hardened after concrete failures.

The setup is nevertheless **not currently trustworthy enough for unattended execution involving consequential actions**. Four defects cut through the main safety story:

1. The shipped Docker wrapper can expose ignored `.env` and credential files to a bypass-mode agent.
2. Headless `autopilot.sh` does not stop before building a `Mode: supervised` phase; it stops only after the build, when side effects may already have happened.
3. The interactive/manual phase base can be advanced to a later valid ancestor, narrowing the secret/high-stakes scan window.
4. Test-command selection is mutable by the implementation agent and is not bound into the trusted control surface.

A second tier of issues weakens evaluation independence and failure recovery: ignored evaluator-created files are invisible to the snapshot system, malformed high-stakes regexes fail open, manual ticking accepts a dirty working tree, `/autopilot-parallel` contains contradictory evaluator-isolation instructions, and multi-file state transitions are not atomic.

## Strongest qualities

The strongest design decision is the **single mechanical completion gate** in `scripts/tick.sh`. A phase cannot be marked complete merely because an agent says it is done: the gate checks an exact-HEAD evaluator grade, exact-HEAD test evidence, the phase diff, secrets, high-stakes paths/content, and supervised approval. The headless path further derives a trusted base outside the builder and byte-compares gate-control files against launch state.

Other standout qualities are the manifest-based sync model, behavioral test style, small and composable skill layer, deterministic model configuration, bounded context injection, and clear distinction between project-owned and toolkit-owned files.

## Largest risks

The largest practical risk is that the project’s strongest prose—“supervised phases are not built unattended” and “the sandbox refuses secret-bearing mounts”—is contradicted by current execution paths. These are not theoretical policy gaps; they have concrete reproduction paths and are partially certified by tests that assert the unsafe behavior.

## Overall verdict

**Overall quality: 6.4/10.**

This is a strong personal Claude Code setup with excellent instincts and several genuinely robust mechanisms. It is safer and more auditable than most comparable setups, but its current unattended-execution claim is stronger than the implementation. Fixing the sandbox mount, pre-build supervised gate, manual phase-base trust, test-command integrity, and ignored-file evaluator isolation would move it close to 8/10 without turning it into an enterprise platform.

---

# 2. System overview

## 2.1 Repository layers

The repository has three clear layers, accurately described in `CONTRIBUTING.md:9-21`:

| Layer | Purpose | Main contents |
|---|---|---|
| Toolkit repository | Distribution, release history, contributor tooling | `README.md`, `CHANGELOG.md`, `VERSION`, `install.sh`, root `.github/`, `docs/dev/` |
| Installable scaffold | Files copied into a target project | `jaimitos-os/CLAUDE.md`, `.claude/`, `scripts/`, `docs/`, `sandbox/`, optional CI |
| Skill source | Portable Claude Code skills | `skills/*` |

This separation is sound. The installer’s “ship by directory” model is simple enough to reason about and is guarded by `.github/scripts/install-smoke.sh`.

## 2.2 Full lifecycle

### Installation

`install.sh`:

1. Resolves the target.
2. Refuses a subdirectory install inside an existing Git repository unless `--allow-subdir` is explicit.
3. Copies scaffold files without overwriting existing files unless `--force`.
4. Copies 17 per-project skills; optionally installs the global setup skill.
5. Merges missing scaffold ignore rules into an existing `.gitignore`.
6. Writes `.claude/.jaimitos-os-version`.
7. Writes `.claude/.jaimitos-manifest` for toolkit-owned files actually copied.
8. Fingerprints the shipped `HIGH_STAKES_RE`.
9. Makes scripts executable.
10. Runs `doctor.sh` when the target is already a Git repository, but does not make doctor failure fail the installation.

Existing `.claude/settings.json` is deliberately preserved rather than merged. The installer warns that hooks and deny rules remain inactive until manually reconciled (`install.sh:258-263` and `install.sh:79-83` in the later section).

### Project definition

The intended path is:

`grill` → `to-spec` → `roadmap`

- `grill` incrementally writes closed decisions into `docs/SPEC.md`.
- `to-spec` resolves open questions, extracts ADRs, records test seams, and marks the spec informationally ready.
- `roadmap` re-derives readiness from content, not the `status: ready` label, and creates bounded phases with observable `Done when:` conditions and `Mode: loopable|supervised`.

This is one of the repository’s best architectural sequences. It avoids a second tracker and keeps durable intent in project files.

### Session resumption

`/resume` reads:

- `docs/STATE.md`
- `docs/ROADMAP.md`
- `NEXT_FINDINGS.md`
- recent Git history

The SessionStart hook injects capped excerpts of state, findings, architecture, glossary, open roadmap items, and recent commits. This makes context loss recoverable without loading the whole project narrative into every session.

### Phase execution

`/phase`:

1. Selects the first open phase or an explicitly matched heading.
2. Records `.claude/.phase-base` for a new phase.
3. Delegates research, planning, execution, and evaluation to separate agents.
4. Runs evaluator snapshot/detection.
5. Leaves completion to `/wrap` or an autopilot.

The staged roles are conceptually clear:

- **Researcher:** read-only investigation and factual grounding.
- **Planner:** writes the phase plan and considers alternatives.
- **Executor:** implements with tests.
- **Evaluator:** independently grades criteria and test quality.

### Evidence and completion

The trust chain is:

`builder commit`  
→ `scripts/test-evidence.sh`  
→ `.claude/.tick-evidence.json` bound to HEAD  
→ evaluator output  
→ `scripts/record-grade.sh`  
→ `.claude/.phase-grade` bound to HEAD  
→ `scripts/tick.sh`  
→ roadmap checkbox + STATE auto-block

`tick.sh` is the single source of truth for whether a phase counts as complete.

### Headless autonomy

`scripts/autopilot.sh` adds:

- a single-run lock with stale-lock handling;
- a clean-tree precondition;
- a throwaway worktree by default;
- a watchdog around child Claude processes;
- fresh builder/evaluator processes;
- a trusted phase base derived in the orchestrator;
- byte-integrity checks for gate-control files;
- evaluator-change rollback;
- retry/thrash limits;
- optional PR push behavior;
- a kill-switch and steering channel.

This is the strongest execution mode in the project, but it contains the critical supervised-before-build defect.

### Parallel autonomy

`/autopilot-parallel` is a prompt-defined advanced workflow:

1. User identifies supposedly independent phases.
2. Worktrees/branches are created.
3. agents run phases in parallel.
4. branches are integrated sequentially.
5. each integration is evaluated and ticked.

It is explicitly experimental, lacks the headless watchdog/retry orchestration, and has contradictory evaluator-isolation instructions. It should not be part of the trusted core.

### Milestone closure

`close-milestone.sh`:

- refuses open roadmap tasks;
- refuses unresolved `NEXT_FINDINGS.md`;
- surfaces ownership gaps without blocking;
- archives the roadmap;
- creates a fresh roadmap;
- resets the STATE auto-block;
- behaves safely on rerun.

### Upgrades

`sync.sh` uses `.claude/.jaimitos-manifest`:

- unchanged managed file → eligible for batch update;
- locally modified managed file → never overwritten; diff/manual merge;
- locally deleted file → not recreated unless `--restore`;
- project-owned file → ignored;
- new toolkit file → installed and added to manifest;
- pre-manifest project → requires explicit `--adopt-manifest`.

This is conservative, understandable, and appropriately lean.

## 2.3 Sources of truth

| State | Source of truth | Notes |
|---|---|---|
| Product purpose and scope | `docs/SPEC.md` | Strong source; roadmap derives from it |
| Work remaining and phase mode | `docs/ROADMAP.md` | Mechanical queue |
| Current narrative/resume context | `docs/STATE.md` | Auto-block is generated; prose is human/model maintained |
| Current code | Git HEAD + working tree | Ultimate implementation truth |
| Phase implementation plan | `docs/plans/<phase>.md` | One plan per active phase |
| Architectural decisions | `docs/decisions/ADR-*.md` | Small immutable rationale records |
| Domain vocabulary | `docs/GLOSSARY.md` | Optional, capped in session context |
| Unresolved evaluator findings | `NEXT_FINDINGS.md` | Ephemeral and ignored; blocks milestone closure |
| Durable failure history | `docs/FAILURES.md` | Generated when needed |
| Test evidence | `.claude/.tick-evidence.json` | Exact-HEAD bound, ignored runtime artifact |
| Evaluator grade | `.claude/.phase-grade` | Exact-HEAD bound, ignored runtime artifact |
| Phase scan base | `TICK_BASE` in headless; `.claude/.phase-base` manually | Headless trusted; manual mutable |
| Managed-file baseline | `.claude/.jaimitos-manifest` | Checksums of toolkit-owned files |
| Enforced high-stakes paths | `.claude/lib/_high-stakes.sh` | Rule file is only a human-readable mirror |
| Model selection | `.claude/agents/*.md` frontmatter | Mutated through `scripts/models.sh` |

## 2.4 Competing sources of truth

1. **Test command:** `CLAUDE.md` tells users and agents the test command, but `_test-cmd.sh` reads only `LEAN_TEST_CMD`, `settings.json`, and ecosystem autodetection.
2. **High-stakes paths:** `_high-stakes.sh` enforces; `.claude/rules/high-stakes.md` mirrors. The installer’s printed next step tells users to edit the mirror, not the enforced regex.
3. **Progress:** ROADMAP checkboxes are mechanical; STATE prose can drift.
4. **Architecture:** `docs/ARCHITECTURE.md` is advisory and may drift from code; `mapme` correctly treats code as authoritative.
5. **Evaluator independence:** evaluator frontmatter removes direct edit tools, but Bash remains mutable; true independence depends on external snapshot/worktree behavior.
6. **Supervised semantics:** documentation says headless checks `Mode:` before building; implementation checks it only at tick time.
7. **Sandbox secret policy:** wrapper comments/tests distinguish ignored files from mount candidates, while Docker receives the entire physical directory.

---

# 3. What the setup does well

## 3.1 A single deterministic completion gate

**Rank: 1**

`scripts/tick.sh` is the architectural center of gravity. It requires:

- an evaluator grade bound to current HEAD;
- a PASS verdict;
- test evidence bound to current HEAD;
- either green tests or evaluator-confirmed no-test legitimacy;
- a valid phase base;
- a secret scan over the phase range;
- a high-stakes path/content check;
- explicit supervised approval when applicable.

The design prevents a command prompt from directly flipping checkboxes. `test-docs-invariants.sh:17-30` guards that commands continue to route through the script.

This is meaningful reliability, not decorative ceremony.

## 3.2 Trusted headless base and gate-control integrity

**Rank: 2**

`autopilot.sh` recognizes that builder-writable state is untrusted. It:

- derives `PHASE_BASE` in the parent shell;
- preserves it across retries;
- overwrites the builder-authored `.phase-base`;
- passes `TICK_BASE` to the gate;
- compares gate scripts, libraries, allowlist, and agent prompts byte-for-byte against `START_REF`.

`autopilot.sh:346-385` documents and implements the boundary. This directly addresses the classic “agent edits the guard that judges it” failure.

## 3.3 Conservative synchronization

**Rank: 3**

The current manifest model is much better than the earlier mixed-file merge design:

- locally modified files are user-owned in practice;
- updates are automatic only when the local checksum still equals the shipped baseline;
- deletion intent is preserved;
- adoption is explicit;
- dry-run is supported;
- project-owned files never enter the manifest.

`test-sync.sh` exercises real files in temporary repositories, including paths with spaces, exec bits, adoption, deletion, dry-run, and CI opt-in. This is an excellent proportionate design for a personal toolkit.

## 3.4 Behavioral tests against real shell scripts

**Rank: 4**

The guard suite is not limited to grep tests. It creates temporary Git repositories and runs the actual scripts. Strong examples include:

- `test-tick.sh`
- `test-autopilot-gates.sh`
- `test-checkpoint.sh`
- `test-sync.sh`
- `test-models.sh`
- `test-close-milestone.sh`
- `test-secret-scan.sh`

`run-guard-tests.sh:34-65` also contains a drift guard so a new `test-*.sh` cannot silently exist without entering CI.

The suite is imperfect, but its style is exemplary.

## 3.5 Clear spec-to-roadmap lifecycle

**Rank: 5**

The `grill`/`to-spec`/`roadmap` separation is well judged:

- one question per turn;
- write decisions only when closed;
- unresolved questions stay explicit;
- ready state is derived from content;
- phases require machine-observable completion;
- ticked phases are treated as immutable stable IDs.

This improves Claude behavior without introducing an external tracker or database.

## 3.6 Bounded context loading

**Rank: 6**

`session-start.sh` caps each injected artifact and prioritizes:

- unresolved findings;
- current state;
- architecture;
- glossary;
- open tasks;
- recent commits.

This is a practical response to token constraints. It avoids repeatedly injecting full docs while still enabling recovery after `/clear`.

## 3.7 Deterministic, narrow utility scripts

**Rank: 7**

`models.sh`, `next-adr.sh`, `lint-roadmap.sh`, `record-grade.sh`, and `close-milestone.sh` each have a small explicit contract. `models.sh` is especially strong: it validates the entire requested mutation before touching any file, preserves frontmatter/body boundaries, handles malformed files conservatively, and has extensive metacharacter tests.

## 3.8 Honest security caveats in several documents

**Rank: 8**

`SECURITY.md` and the GUIDE generally avoid claiming that Bash deny patterns or an environment marker are true sandboxes. The high-stakes rule explicitly says the native path filter is unreliable and names `_high-stakes.sh` as the enforcement source. This honesty is a strength even though several specific claims have drifted.

## 3.9 Installation protects existing project files

**Rank: 9**

Default install behavior is conservative:

- skip existing;
- preserve README;
- keep project docs out of the sync manifest;
- refuse nested repo installs by default;
- make CI opt-in;
- warn when settings are not merged.

This minimizes accidental data loss.

## 3.10 Ownership features are genuinely differentiated

**Rank: 10**

`teach-back`, `quizme`, and `mapme` are not three synonyms. They respectively test immediate understanding, cold recall, and architectural orientation. For a personal setup intended to prevent “AI wrote it, nobody owns it,” this is justified functionality.

---

# 4. Critical issues

## C1 — Ignored secrets are mounted into the bypass-mode sandbox

**Severity:** Critical  
**Affected files:** `jaimitos-os/sandbox/run-autopilot-sandboxed.sh`, `jaimitos-os/scripts/test-sandbox.sh`, `jaimitos-os/.gitignore`, `SECURITY.md`, sandbox documentation

### Current behavior

The wrapper enumerates tracked files plus **unignored** untracked files before scanning. It then mounts the entire physical repository directory:

```text
-v "$PWD:/workspace"
```

The scaffold explicitly ignores `.env`, `.env.*`, private keys, credentials JSON, `secrets/`, `.tfvars`, `.netrc`, and similar files (`jaimitos-os/.gitignore:49-71`).

Therefore an ignored `.env` is excluded from the scan but remains inside the bind mount. The agent runs with `--dangerously-skip-permissions` and can read it through Bash.

The test suite explicitly asserts that a gitignored `.env` should not block and notes that the mount still contains it (`test-sandbox.sh:96-119`).

### Why it matters

The sandbox is presented as the safe execution boundary for unattended bypass mode. Exposing credentials inside that boundary defeats the most important security property: “the loop has no credentials worth exfiltrating.”

### Reproduction

1. Add `.env` to `.gitignore`.
2. Write a real secret to `.env`.
3. Run the wrapper’s enumeration:
   - `.env` is absent.
4. Inspect the Docker bind source:
   - `.env` physically exists in `$PWD`.
5. Inside the container, `cat /workspace/.env` succeeds.

This was reproduced with an isolated Git repository: the wrapper-equivalent enumeration omitted `.env` while the physical file remained present and ignored.

### Recommended fix

Do not mount the live repository directory.

Leanest robust design:

1. Create a temporary clean worktree at HEAD.
2. Copy only explicitly allowed untracked inputs, after scanning them.
3. Do not copy ignored files.
4. Mount that temporary worktree.
5. Export the resulting branch/patch back after the run.
6. Make the wrapper fail if the clean export cannot be constructed.

At minimum, scan **all physically present files** under the mount, including ignored files, and refuse known credential paths. That is safer but less robust than a clean export because caches and large ignored trees still enter the container.

Invert the unsafe test: a gitignored `.env` must block or be absent from the mounted workspace.

### Effort

Medium.

### Complexity impact

Meaningful and justified. A temporary worktree already exists elsewhere in the project; reuse that mental model rather than introducing a framework.

---

## C2 — Headless autopilot builds supervised phases before stopping

**Severity:** Critical  
**Affected files:** `jaimitos-os/scripts/autopilot.sh`, `scripts/test-autopilot-gates.sh`, `test-docs-invariants.sh`, README, GUIDE

### Current behavior

The headless loop detects open work and launches the builder. It does not parse the selected phase’s `Mode:` before the builder starts. `tick.sh` later sees `Mode: supervised` and refuses completion, but execution has already happened.

The GUIDE promises the opposite: headless autopilot should stop before building a supervised phase.

### Why it matters

A supervised phase is used precisely for actions whose blast radius is not safely reversible: auth, money, migration, deletion, email, deploy, webhook, or other external effects. Refusing the checkbox after the action does not protect the system.

### Reproduction

Create a roadmap:

```md
## Phase 1 — Send production notification
- [ ] invoke the real notification path
Done when: notification exists
Mode: supervised
```

Use a builder stub that writes a marker or invokes a side-effect script. Run headless autopilot. The builder is invoked; only the later tick refuses.

The current test suite contains no fixture asserting that the builder invocation count remains zero for a supervised next phase.

### Recommended fix

Before every builder spawn:

1. Parse the first open phase heading.
2. Parse its exact `Mode:` within that phase block.
3. Fail closed if missing, malformed, duplicated, or `supervised`.
4. Print the exact manual command/path.
5. Add a test where the builder stub would create a marker; assert marker absent.

Use one shared phase parser in `tick.sh`, `autopilot.sh`, `close-milestone.sh`, and roadmap lint to prevent parser drift.

### Effort

Small to medium.

### Complexity impact

Low. This is missing enforcement for an existing field.

---

## H1 — Manual `.phase-base` can be advanced to hide earlier phase commits

**Severity:** High  
**Affected files:** `scripts/tick.sh`, `.claude/commands/phase.md`, `.claude/commands/wrap.md`, evaluator instructions, tests

### Current behavior

In manual mode, `tick.sh` reads builder-writable `.claude/.phase-base`. It verifies only that the value:

- resolves to a commit;
- is not HEAD;
- is an ancestor of HEAD.

Those checks reject an empty or unrelated base, but they do **not** prove it is the original phase start.

A builder can replace the original base A with later ancestor B. The range changes from `A..HEAD` to `B..HEAD`, hiding commits between A and B.

`tick.sh:176-205` claims strict ancestry prevents narrowing, but the validation does not establish origin.

### Why it matters

An earlier commit containing a secret, high-stakes change, or gate-control modification can be excluded from both evaluator and tick scans. Headless mode is protected by `TICK_BASE`; manual `/phase` and `/wrap` are not.

### Reproduction

Isolated repository:

- A: initial commit.
- B: commit adding `credentials.txt`.
- C: benign commit at HEAD.
- Rewrite `.phase-base` from A to B.

Results:

- B is a strict ancestor of C.
- `git diff A..C --name-only` includes `credentials.txt`.
- `git diff B..C --name-only` does not.
- Current validation accepts B.

This same weakness was identified as unresolved in the archived v2.3 audit (`AUDIT-JAIMITOS-OS-V2.3.md:154-160`).

### Recommended fix

Do not accept a builder-authored base as trustworthy.

A lean design is to add a deterministic `scripts/start-phase.sh` that:

1. requires a clean tree;
2. resolves the exact roadmap heading;
3. records the phase start in a durable, gate-protected record;
4. commits or otherwise anchors that record before implementation;
5. makes `tick.sh` derive the base from that anchor, not from a mutable ignored file.

Until that exists, manual `tick.sh` should explicitly be classified as human-reviewed rather than trust-equivalent to headless, and it should print the full range being judged.

### Effort

Medium.

### Complexity impact

Moderate but justified. Avoid cryptographic signing or a database; a Git-native phase-start anchor is sufficient.

---

## H2 — The implementation agent can weaken the test command

**Severity:** High  
**Affected files:** `.claude/lib/_test-cmd.sh`, `scripts/test-evidence.sh`, `scripts/autopilot.sh`, `.claude/settings.json`, project manifests, `CLAUDE.md`, setup/roadmap skills

### Current behavior

The mechanical resolver trusts, in order:

1. `LEAN_TEST_CMD` environment variable.
2. `.claude/settings.json` `env.LEAN_TEST_CMD`.
3. mutable project manifests and files such as `package.json`, `Makefile`, and ecosystem markers.

The headless gate-control integrity list does not include `.claude/settings.json`, `package.json`, `pyproject.toml`, `Makefile`, or equivalent test configuration.

An executor can change the selected command to `true`, a no-op script, or a narrowed suite, commit it, and generate green exact-HEAD evidence.

Separately, setup skills fill `CLAUDE.md` with Test/Typecheck/Lint commands, but `_test-cmd.sh` never reads `CLAUDE.md`. The human-visible configuration and gate configuration can diverge.

### Why it matters

Exact-HEAD binding proves when evidence was generated, not whether the command was trustworthy. A green run of a builder-controlled no-op is false confidence.

### Reproduction

1. Set `.claude/settings.json`:
   ```json
   {"env":{"LEAN_TEST_CMD":"true"}}
   ```
2. Run `scripts/test-evidence.sh`.
3. Evidence records `passed: true`.
4. If evaluator grades PASS, `tick.sh` accepts the evidence.

A focused resolver reproduction also confirmed that a custom command present only in `CLAUDE.md` resolves to no mechanical command.

### Recommended fix

Create one explicit machine-readable test command file, for example `.claude/test-command`, configured during setup and included in:

- the sync/project-owned contract;
- headless gate-control integrity;
- manual phase-start baseline;
- `doctor.sh`;
- evidence output.

Record both the command and a hash of its configuration in evidence. If the command changes during a phase, force supervised review.

Alternatively, parse a narrowly defined `Test:` field from `CLAUDE.md`, but this is more fragile than a one-line file.

### Effort

Medium.

### Complexity impact

Low to moderate. It removes a competing source of truth rather than adding a subsystem.

---

## H3 — Evaluator isolation ignores gitignored files

**Severity:** High  
**Affected files:** `.claude/lib/_eval-isolation.sh`, `test-eval-isolation.sh`, `/phase`, `autopilot.sh`

### Current behavior

The snapshot tracks:

- tracked changes via `git stash create`;
- untracked, non-ignored files via `git ls-files --others --exclude-standard`.

Ignored files are absent from both sets.

An evaluator or evaluator-run test can create or modify ignored fixtures, caches, databases, coverage artifacts, `.env`, or generated data. The isolation check reports clean and headless restore leaves them in place.

### Why it matters

Ignored state can influence subsequent test runs or application behavior. A complacent evaluator can accidentally create exactly the fixture that makes a later test pass, defeating the goal of independent evaluation.

### Reproduction

1. Ignore `generated/`.
2. Snapshot.
3. During “evaluation,” write `generated/fixture.json`.
4. `git status --porcelain` is empty.
5. `eval_changed_files` reports no change.
6. File persists.

The current tests cover tracked and ordinary untracked files, not ignored files.

### Recommended fix

Run the evaluator in a disposable worktree/container that starts from HEAD and is deleted wholesale afterward. That naturally excludes ignored state.

For interactive mode, create a temporary evaluator worktree instead of evaluating in the live checkout. This is cleaner than trying to hash every ignored cache.

### Effort

Medium.

### Complexity impact

Moderate but justified; it can simplify the current snapshot/detect split.

---

## H4 — Invalid high-stakes regex silently fails open

**Severity:** High  
**Affected files:** `.claude/lib/_high-stakes.sh`, `doctor.sh`, `test-high-stakes.sh`

### Current behavior

`high_stakes_match` suppresses `grep -E` errors and treats nonzero as no match. A syntactically invalid customized `HIGH_STAKES_RE` therefore disables path matching.

`doctor.sh` checks whether the value differs from the shipped fingerprint but does not compile/validate the regex.

### Why it matters

The project encourages users to customize this regex. A typo in the main enforcement source should block unattended execution, not silently remove the gate.

### Reproduction

```bash
HIGH_STAKES_RE='['
high_stakes_match auth/login.py
```

Raw `grep -E` returns 2 for invalid regex; the wrapper returns ordinary “no match.”

### Recommended fix

1. Validate once when sourcing or before matching:
   ```bash
   printf '' | grep -Eq "$HIGH_STAKES_RE"
   rc=$?
   [ "$rc" -le 1 ] || return 2
   ```
2. Give the matcher a three-state contract: clean, matched, invalid/error.
3. Make `tick.sh`, autopilot, and doctor fail closed on error.
4. Add malformed regex tests.

### Effort

Small.

### Complexity impact

Negligible.

---

## H5 — Manual tick can complete with uncommitted changes present

**Severity:** High  
**Affected files:** `scripts/tick.sh`, `/wrap`, manual workflow documentation

### Current behavior

The secret and high-stakes checks scan `BASE..HEAD`, which contains committed changes only. `tick.sh` does not require a clean working tree before mutating ROADMAP and STATE.

A developer can have uncommitted high-stakes code or a secret in the working tree while the committed HEAD passes all gates. The phase is ticked even though the checkout no longer corresponds to the judged revision.

### Why it matters

The exact-HEAD evidence model is only trustworthy when the working tree equals HEAD. Otherwise the user sees “phase complete” in a checkout containing unjudged work.

### Reproduction

1. Produce PASS grade/evidence for HEAD.
2. Add an uncommitted secret or auth change.
3. Invoke `tick.sh`.
4. Current code has no dirty-tree refusal before completion.

### Recommended fix

Require a clean tracked and untracked tree before manual ticking, with a narrow exception for known runtime artifacts. Print the offending files and refuse.

### Effort

Small.

### Complexity impact

Low.

---

## H6 — `/autopilot-parallel` contradicts itself about evaluator isolation

**Severity:** High  
**Affected files:** `.claude/commands/autopilot-parallel.md`, `test-autopilot-parallel.sh`

### Current behavior

The warning section says every integration grade must use `eval_snapshot` and `eval_changed_files`. The actual Step C workflow invokes the evaluator without those calls. A later section still states that there is no evaluator-change discard.

Because this is a command document, instruction order and proximity matter. The operational procedure does not consistently enforce the headline guarantee.

### Why it matters

Parallel integration is already the most conflict-prone mode. An evaluator that mutates the integrated tree can contaminate the next merge and grade.

### Reproduction

Follow Step C literally. There is no required snapshot call around the evaluator. The test suite checks the integration/tick idea with stubs, not live command adherence.

### Recommended fix

Preferred: remove `/autopilot-parallel` from the default shipped command set until it has a deterministic shell orchestrator.

Minimum: rewrite the document so there is one canonical integration procedure and add exact invariant tests asserting the isolation calls surround the evaluator.

### Effort

Small for removal/document correction; large for a real orchestrator.

### Complexity impact

Removing it lowers complexity.

---

# 5. Design weaknesses and inconsistencies

## 5.1 Prompt-level orchestration is mixed with shell-level guarantees

The setup is strongest when a shell script owns a state transition. It is weakest where a Markdown command asks the model to perform a multi-step protocol correctly:

- manual phase-start base capture;
- parallel worktree creation/integration;
- evaluator isolation around interactive or parallel grading;
- grade recording;
- STATE prose updates.

The design should continue moving only **load-bearing transitions** into narrow scripts. It should not turn every skill into code.

## 5.2 ROADMAP parsing is duplicated

Several components independently parse phase blocks and checkboxes:

- `/phase`
- `autopilot.sh`
- `tick.sh`
- `close-milestone.sh`
- `lint-roadmap.sh`
- SessionStart hook
- milestone/roadmap skills

Past changelog entries show real bugs caused by legend lines and unanchored checkbox matching. A single small phase-parser shell library would reduce risk without introducing a framework.

## 5.3 Two high-stakes representations drift by design

The regex is enforced; YAML `paths:` is advisory. The rule file correctly explains this, but installation output tells users to edit the advisory file. Synchronizing two manually maintained representations is error-prone.

Either:

- generate the human-readable list from a simpler data file; or
- keep only one explicit project-owned path list and derive the regex internally.

The current free-form regex is powerful but easy to invalidate.

## 5.4 Evidence authenticates revision, not provenance

`.phase-grade` and `.tick-evidence.json` are exact-HEAD bound, which is valuable. They are still ordinary ignored files writable by Bash. Headless autopilot re-derives them, but manual mode relies on the command following the procedure.

This is acceptable for supervised personal use if documented as such. It is not structural independent attestation.

## 5.5 STATE has mixed ownership

The auto-block is deterministic; `Now`, `Next action`, and `Open questions` are prose-maintained. That is reasonable, but documentation should explicitly state that ROADMAP is authoritative when STATE conflicts.

## 5.6 Installer completion semantics are ambiguous

`install.sh` exits successfully even when `doctor.sh` reports issues. This is reasonable for greenfield placeholders but dangerous if a user interprets installer success as unattended-readiness.

Use distinct final statuses:

- installed but unconfigured;
- installed and healthy;
- installed with blocking issues.

## 5.7 The checkpoint hook owns the whole index

`commit-on-stop.sh` stages everything, scans, commits, and resets the index on failure. The design assumes the user does not maintain a curated staging set. That assumption is not prominent and can surprise normal Git users.

## 5.8 Error recovery is mostly manual

There are many fail-closed stops, but fewer deterministic repair paths:

- partial ROADMAP/STATE update;
- interrupted milestone archive/reset;
- interrupted sync batch;
- stale or corrupted evidence artifacts;
- evaluator ignored-state contamination;
- partial install.

`doctor.sh --fix` repairs only safe local omissions, which is good, but a `doctor --state` or `repair-state.sh` could validate cross-file invariants.

## 5.9 Current CI is Linux-centric

Root CI is substantial, but portability claims rely on prior manual testing and changelog reports. There is no macOS/Bash 3.2 matrix. Shell code contains explicit BSD/GNU compatibility history, so a lightweight macOS job would provide real value.

## 5.10 Contributor documentation has drifted

`CONTRIBUTING.md:84-97` still lists a handful of behavior tests while CI now runs all 17 through `run-guard-tests.sh`. The actual implementation is better than the contributor guide.

---

# 6. Missing capabilities

## 6.1 A safe workspace exporter for sandbox runs

This is the highest-value missing capability. The wrapper needs a way to construct a workspace that contains code but not ignored credentials.

## 6.2 A trusted manual phase-start anchor

Headless mode has a trusted base; interactive mode does not. A deterministic start script would close the most important asymmetry.

## 6.3 Immutable test-command binding

The gate needs to know which command was authorized at phase start and whether its definition changed.

## 6.4 Dirty-tree completion refusal

Exact-HEAD evidence should imply checkout equals HEAD.

## 6.5 High-stakes regex validation

A simple missing fail-closed check.

## 6.6 Ignored-state evaluator isolation

A disposable evaluator checkout is preferable to more snapshot complexity.

## 6.7 Cross-file state invariant checker

Useful checks:

- every ticked phase has matching STATE auto status;
- active phase heading exists exactly once;
- phase base belongs to the active phase;
- grade/evidence HEAD matches;
- milestone archive and current roadmap are not half-transitioned;
- `NEXT_FINDINGS.md` state is coherent.

## 6.8 Complete roadmap schema lint

`lint-roadmap.sh` checks `Done when:` presence, but not:

- unique headings;
- exactly one valid `Mode:`;
- at least one task;
- no checkbox syntax in prose;
- no duplicate phase IDs;
- dependency references;
- supervised classification consistency.

## 6.9 Live Claude Code integration test

The suite validates shell behavior but not whether current Claude Code:

- loads each command/skill as expected;
- applies agent tool restrictions;
- dispatches hooks in the assumed order;
- honors frontmatter keys;
- blocks on hook exit codes;
- follows command documents.

A small opt-in live smoke test, not CI, would detect platform drift.

## 6.10 Release-state verification

`VERSION` is `2.6.0`, changelog says “not tagged,” and current fixes live under Unreleased. A release check could compare version, tags, changelog, and current HEAD before publishing.

---

# 7. Over-engineering and removable complexity

## 7.1 Remove or quarantine `/autopilot-parallel`

This is the clearest removable complexity. It adds:

- independence assertions;
- multiple worktrees;
- branch orchestration;
- merge conflict protocol;
- integration grading;
- another evaluator-isolation path;
- another test harness that cannot exercise the actual model workflow.

It is the least trustworthy mode and is explicitly experimental. Keep it out of the default install or move it to an examples/experimental directory.

## 7.2 Retain headless autopilot only if it is actually used

The changelog already includes a dated usage review. `autopilot.sh` is large because it owns real guarantees, not because it is carelessly written. The correct simplification is not shaving 100 lines; it is deleting the feature if real usage does not justify the permanent trust surface.

## 7.3 Do not merge the spec lifecycle skills

`grill`, `to-spec`, `roadmap`, and `milestone` look like multiple concepts, but each has a distinct state transition. Merging them would create a giant ambiguous skill and increase accidental triggering.

## 7.4 Consider making ownership skills optional, not removing them

`teach-back`, `mapme`, and `quizme` are useful but not needed in every target repository. An optional copy flag would reduce concept count for users who do not use the ownership workflow. This is a minor optimization, not a priority.

## 7.5 Consolidate duplicated security prose

Security details are repeated across README, GUIDE, SECURITY, rule files, command files, and agent prompts. Repetition has already produced contradictions. Keep:

- one authoritative security model in GUIDE/SECURITY;
- short operational summaries elsewhere;
- executable documentation invariants for key claims.

## 7.6 Do not add a database, service, event bus, or orchestration framework

The current state fits Git and files. The observed defects are narrow boundary mistakes, not evidence that a persistent service is needed.

## 7.7 Do not add cryptographic evidence signing

For a personal local workflow, signing `.phase-grade` would add ceremony without solving the more immediate problem that the same agent controls test configuration and working state.

---

# 8. Documentation versus reality

| Claim | Documentation source | Implementation evidence | Verdict |
|---|---|---|---|
| All completion marking routes through `tick.sh` | README, CLAUDE, command docs | `/wrap` and autopilots invoke `scripts/tick.sh`; invariant test guards prose | **Enforced** |
| Exact-HEAD grade and test evidence are required | GUIDE, tick help | `tick.sh` compares both `run_id` values to HEAD | **Enforced** |
| Headless phase base is outside builder trust | GUIDE/security docs | `autopilot.sh` derives `PHASE_BASE`, overwrites file, passes `TICK_BASE` | **Enforced** |
| Manual strict-ancestor validation prevents range narrowing | `tick.sh` comments | Any later ancestor passes and narrows `BASE..HEAD` | **Contradicted** |
| Supervised phases stop headless autopilot before build | GUIDE/README | `autopilot.sh` launches builder before mode is checked by `tick.sh` | **Contradicted** |
| Sandbox refuses secret-shaped files that would ride into mount | SECURITY, sandbox comments | Scan excludes ignored files; bind mount includes them | **Contradicted** |
| Adding a secret to `.gitignore` makes sandbox safer | wrapper remediation/test | It removes the file from enumeration while retaining it in mount | **Contradicted** |
| Evaluator changes are mechanically isolated in both modes | v2.6 changelog/GUIDE | Tracked and ordinary untracked changes detected; ignored changes invisible | **Partially enforced** |
| Evaluator is read-only | evaluator/skills docs | No direct Edit/Write tools, but Bash can mutate; external isolation required | **Partially enforced** |
| High-stakes gate fails closed | GUIDE/security docs | Missing library fails closed in tick; malformed regex silently becomes no-match | **Partially enforced** |
| `_high-stakes.sh` is the enforcement source | rule file/setup skill | Matcher is sourced by tick/autopilot | **Enforced** |
| Installer next steps correctly configure high-stakes enforcement | install output | Output points at rule `paths:` rather than explicitly at enforced regex | **Outdated/incomplete** |
| CLAUDE.md Test command configures mechanical evidence | CLAUDE/setup workflow implication | Resolver never reads CLAUDE.md | **Documentation-only** |
| Test command is independently trustworthy | Exact-HEAD evidence narrative | Builder can alter settings/manifests selecting the command | **Not enforced** |
| Sync never overwrites local customizations | README/changelog | Manifest classification and tests preserve modified/deleted/project-owned files | **Enforced** |
| Deleted managed files are not recreated silently | sync docs | Explicit `--restore` required | **Enforced** |
| Brownfield settings are protected | installer docs | Existing settings skipped; warning emitted | **Enforced** |
| Brownfield hooks remain active after install | Not directly promised | Existing settings are not merged, so hooks may remain inactive | **Correctly documented limitation** |
| Guard tests cannot silently fall out of CI | `run-guard-tests.sh` | Drift guard compares all `test-*.sh` scripts to list | **Enforced** |
| Contributor guide reflects CI test breadth | CONTRIBUTING | Guide names only a subset; CI runs 17 | **Outdated** |
| Parallel integration grades are isolated | `/autopilot-parallel` warning | Actual procedure omits mandatory calls and later denies discard | **Contradicted/inconsistent** |
| Milestone closure is gated and rerun-safe | milestone docs | `close-milestone.sh` and behavior tests | **Enforced** |
| Installer is idempotent | README/install smoke | Existing files skipped; ignore block not duplicated | **Enforced, with `--force` exception** |
| Installation success means unattended-ready | Implicit UX risk | doctor failures do not fail install; placeholders/warnings may remain | **Not enforced** |

---

# 9. Test and verification results

## 9.1 Repository inspection

**Completed**

- Resolved default branch and exact HEAD through GitHub.
- Inspected all tracked runtime-relevant files.
- Read all command, agent, hook, library, script, skill, CI, template, security, contributor, and update surfaces.
- Read historical plans/audits to identify intended guarantees and deferred findings.
- Compared current behavior to the repository’s own prior audit conclusions.

## 9.2 Focused adversarial reproductions executed

### Invalid high-stakes regex

**Result:** reproduced fail-open behavior.

- `HIGH_STAKES_RE='['`
- raw `grep -E` error code: 2
- wrapper outcome: ordinary no-match

### Ignored sandbox credential

**Result:** reproduced visibility mismatch.

- `.env` ignored by Git
- wrapper-equivalent tracked/unignored enumeration omitted it
- physical bind source still contained it

### Ignored evaluator artifact

**Result:** reproduced isolation blind spot.

- ignored generated file created after snapshot
- `git status` remained empty
- snapshot comparison had no path to report
- file persisted

### CLAUDE test command versus resolver

**Result:** reproduced competing sources.

- custom test command present only in `CLAUDE.md`
- `_test-cmd.sh` source model has no parser for that file
- mechanical resolution remained empty or relied on unrelated autodetection

### Later-ancestor phase-base narrowing

**Result:** reproduced.

- original phase range included a secret-bearing commit
- later strict ancestor passed current ancestry conditions
- narrowed range omitted the secret-bearing commit

## 9.3 Repository-reported checks

The current `CHANGELOG.md` reports:

- blocking shellcheck clean;
- actionlint fixed;
- all 17 guard suites passing;
- install smoke passing;
- portability fixes for BSD/GNU differences.

Root CI is configured to run:

1. Bash syntax checks.
2. Shellcheck.
3. Advisory shfmt.
4. actionlint.
5. settings JSON validation.
6. all 17 guard suites through `run-guard-tests.sh`.
7. install smoke.

These are strong checks, but the latest status was not independently executed here.

## 9.4 Checks not independently executed

| Check | Reason |
|---|---|
| Full `run-guard-tests.sh` | GitHub connector provides file contents but not a mounted repository archive; direct clone/download was unavailable |
| `install-smoke.sh` end to end | Same repository-mount limitation |
| shellcheck | Binary unavailable locally |
| actionlint | Binary unavailable locally |
| shfmt | Binary unavailable locally |
| Docker sandbox execution | Docker unavailable |
| Live Claude Code command/agent/hook flow | Claude CLI unavailable |
| GitHub Actions latest run logs | No directly available current run from the connector path used |
| macOS/Bash 3.2 behavior | Environment unavailable |

## 9.5 Unexpected behavior found in tests

1. `test-sandbox.sh` asserts the unsafe ignored-`.env` behavior as correct.
2. `test-checkpoint.sh` asserts that secret-scan failure empties the index, encoding loss of staging selection.
3. `test-docs-invariants.sh` checks pre-build supervised mode only in the in-session command, not in headless `autopilot.sh`.
4. `test-eval-isolation.sh` omits ignored files.
5. `test-high-stakes.sh` omits malformed regex.
6. `test-autopilot-parallel.sh` tests a shell approximation of integration gating, not the actual Markdown-command orchestration.
7. `test-test-cmd.sh` thoroughly tests resolver precedence but does not test command integrity across a phase.

## 9.6 Does the documented end-to-end workflow work?

**Manual, low-stakes workflow:** probably yes, with meaningful safeguards. The shell-level pieces compose coherently, and historical dogfood reports support that conclusion.

**Headless, low-stakes, no-credentials workflow:** works within a narrower threat model than documented. It has strong worktree/base/control integrity, but test-command mutability and supervised pre-build handling remain defects.

**Headless with the shipped Docker wrapper and real ignored credentials in the repo:** unsafe.

**Consequential or irreversible unattended execution:** no.

**Parallel workflow:** not sufficiently reliable to count as a trusted product surface.

---

# 10. Scores

| Category | Score | Reasoning | What raises it by one point |
|---|---:|---|---|
| **Overall quality** | **6.4** | Strong architecture and tests, but multiple release-blocking contradictions in the unattended safety model | Fix C1, C2, H1, H2, H3, and H4 with regression tests |
| Architecture | 7.6 | Clear layers, lifecycle, one completion gate, Git-native state; some duplicated parsers and prompt-owned transitions | Centralize phase parsing and trusted phase-start/test configuration |
| Claude Code effectiveness | 7.5 | Good role separation, bounded context, verification culture, useful skills | Add live compatibility smoke test and eliminate contradictory command protocols |
| Reliability | 5.9 | Exact-HEAD evidence, locks, watchdog, retry and sync safety; dirty/manual/atomicity gaps | Clean-tree tick, transactional state update, recovery checker |
| Security | 4.8 | Honest threat modeling and several fail-closed gates, but sandbox exposes ignored secrets and regex can fail open | Replace live bind mount and validate high-stakes configuration |
| Evaluation independence | 5.5 | Separate evaluator, no direct edit tools, headless rollback; Bash/ignored files/provenance/manual gaps | Evaluate in disposable worktree and bind test config |
| Testing | 7.4 | Large behavioral suite with drift guard and real temp repos | Add tests for every critical gap and mutation-test core security properties |
| Documentation | 6.5 | Excellent depth and historical honesty; several high-impact contradictions and contributor drift | Correct supervised/sandbox/base/test-command claims and generate invariant checks |
| Installation and upgrades | 7.7 | Conservative install, manifest sync, idempotency, deletion preservation | Add transaction/rollback status and make enforced high-stakes config explicit |
| Maintainability | 7.2 | Consistent shell style and narrow utilities; large autopilot and duplicated parsing/prose | Shared phase parser, remove experimental parallel mode, reduce duplicated claims |
| Leanness | 6.9 | Most abstractions earn their cost; 18 skills remain small | Quarantine parallel mode and delete headless mode if usage review fails |
| Token efficiency | 7.4 | Capped session injection and small skill bodies | Reduce duplicated instructions and optionally install ownership skills |
| User experience | 6.7 | Clear commands and useful doctor; too many modes and ambiguous “installed versus ready” state | Add readiness summary and simplify mode choice |
| Extensibility | 7.2 | Skills and scripts are easy to add; manifest and drift checks help | Define a small shared parser/config contract for future gates |

## Score interpretation

The project’s earlier 8+ self/third-party audits were reasonable for the narrower defects then under review, but the current repository-wide score must account for the sandbox and supervised-mode contradictions. Ambitious design and extensive documentation do not compensate for a safety promise that fails on the exact path it is meant to protect.

---

# 11. Prioritized improvement roadmap

## Immediate — correctness, security, and false-confidence risks

### I1. Replace the live sandbox bind mount

- **Problem solved:** ignored credentials exposed to bypass-mode agent.
- **Change:** mount a clean temporary worktree/export; do not include ignored files.
- **Affected:** sandbox wrapper, Docker docs, sandbox tests, SECURITY, GUIDE.
- **Effort:** Medium.
- **Benefit:** Critical.
- **Complexity cost:** Moderate, justified.
- **Dependencies:** Git worktree available.
- **Validation:** ignored `.env`, `.pem`, `.netrc`, credentials JSON physically absent in container; clean source changes export correctly.

### I2. Enforce `Mode: supervised` before headless builder invocation

- **Problem solved:** irreversible actions run before refusal.
- **Change:** parse next phase before spawn; fail closed on missing/invalid/supervised.
- **Affected:** `autopilot.sh`, shared parser, gate tests, docs.
- **Effort:** Small.
- **Benefit:** Critical.
- **Complexity cost:** Low.
- **Dependencies:** none.
- **Validation:** supervised fixture leaves builder marker absent.

### I3. Establish a trusted manual phase-start anchor

- **Problem solved:** later-ancestor range narrowing.
- **Change:** deterministic start script and Git-native anchored base; tick derives it.
- **Affected:** `/phase`, `/wrap`, `tick.sh`, evaluator, tests.
- **Effort:** Medium.
- **Benefit:** High.
- **Complexity cost:** Moderate.
- **Dependencies:** phase parser.
- **Validation:** rewrite ignored base to later ancestor; gate still scans original range or refuses.

### I4. Bind and integrity-protect the test command

- **Problem solved:** no-op or narrowed test suite accepted.
- **Change:** one machine-readable command source, included in phase integrity and evidence.
- **Affected:** setup skill, roadmap skill, `_test-cmd.sh`, evidence, autopilot, doctor.
- **Effort:** Medium.
- **Benefit:** High.
- **Complexity cost:** Low to moderate.
- **Dependencies:** migration/default behavior.
- **Validation:** changing command during phase forces supervised/refusal; CLAUDE and machine config cannot diverge silently.

### I5. Run evaluation in a disposable checkout

- **Problem solved:** ignored evaluator state and Bash writes.
- **Change:** evaluator reads/tests a temporary worktree at candidate HEAD; discard whole directory.
- **Affected:** `/phase`, autopilot, eval isolation library/tests.
- **Effort:** Medium.
- **Benefit:** High.
- **Complexity cost:** Moderate.
- **Dependencies:** clean worktree helper.
- **Validation:** evaluator creates tracked, untracked, ignored, and committed artifacts; none affect candidate checkout.

### I6. Validate `HIGH_STAKES_RE` fail closed

- **Problem solved:** typo disables gate.
- **Change:** three-state matcher + doctor check.
- **Affected:** high-stakes library, tick, autopilot, doctor, tests.
- **Effort:** Small.
- **Benefit:** High.
- **Complexity cost:** Negligible.
- **Dependencies:** none.
- **Validation:** malformed regex returns configuration error and blocks.

### I7. Refuse manual tick on dirty tree

- **Problem solved:** checkout differs from exact-HEAD evidence.
- **Change:** clean-tree check excluding known runtime artifacts.
- **Affected:** `tick.sh`, `/wrap`, tests.
- **Effort:** Small.
- **Benefit:** High.
- **Complexity cost:** Low.
- **Dependencies:** define runtime-file exclusions.
- **Validation:** tracked/untracked code change causes refusal; only evidence artifacts do not.

## Next — high-value reliability and usability

### N1. Add a shared roadmap phase parser

- **Problem solved:** duplicated parsing and past legend bugs.
- **Change:** narrow shell library for headings, tasks, mode, done condition.
- **Affected:** autopilot, tick, close, lint, hooks.
- **Effort:** Medium.
- **Benefit:** High.
- **Complexity cost:** Moderate but reduces total complexity.
- **Validation:** one fixture corpus consumed by all callers.

### N2. Make tick/STATE transition recoverable

- **Problem solved:** partial update can leave ROADMAP and STATE inconsistent.
- **Change:** prepare both temporary files, validate, replace, and add repair check.
- **Affected:** tick, close milestone, doctor.
- **Effort:** Medium.
- **Benefit:** Medium-high.
- **Complexity cost:** Low.
- **Validation:** injected failure between replacements is detected and repaired.

### N3. Preserve the user’s staging selection

- **Problem solved:** secret-scan abort resets index.
- **Change:** snapshot index or avoid staging live index for scan.
- **Affected:** commit-on-stop, checkpoint tests.
- **Effort:** Small to medium.
- **Benefit:** Medium.
- **Complexity cost:** Low.
- **Validation:** pre-staged subset remains identical after abort.

### N4. Expand roadmap lint

- **Problem solved:** malformed modes/headings reach runtime.
- **Change:** validate schema and uniqueness.
- **Affected:** `lint-roadmap.sh`, roadmap skill, CI.
- **Effort:** Small.
- **Benefit:** Medium.
- **Complexity cost:** Low.
- **Validation:** malformed/duplicate fixtures fail strict mode.

### N5. Correct installer readiness output

- **Problem solved:** user edits advisory high-stakes mirror and assumes installation is safe.
- **Change:** name `_high-stakes.sh` first; summarize “installed, not configured.”
- **Affected:** install output, README, setup skill.
- **Effort:** Small.
- **Benefit:** Medium.
- **Complexity cost:** Negligible.
- **Validation:** install smoke asserts wording.

### N6. Add a macOS/Bash 3.2 CI job

- **Problem solved:** portability regressions.
- **Change:** syntax + guards or representative subset on macOS.
- **Affected:** root CI.
- **Effort:** Small.
- **Benefit:** Medium.
- **Complexity cost:** Low.
- **Validation:** CI matrix green.

### N7. Move `/autopilot-parallel` out of default install

- **Problem solved:** weak experimental surface presented alongside trusted core.
- **Change:** experimental directory or explicit install flag.
- **Affected:** installer, docs, skills cross-reference, tests.
- **Effort:** Small.
- **Benefit:** Medium-high.
- **Complexity cost:** Reduces complexity.
- **Validation:** default install excludes it; opt-in copy works.

## Later — useful refinements

### L1. Pin/rebuild sandbox image dependencies

Pin base digest and Claude Code package version; rebuild when Dockerfile hash changes.

### L2. Add resource limits to sandbox

Memory, CPU, process count, and optional network policy.

### L3. Add opt-in live Claude Code compatibility smoke test

Exercise hooks, agent restrictions, command loading, and skill invocation outside CI.

### L4. Add release consistency check

Version/changelog/tag/HEAD consistency before release.

### L5. Optional ownership-skill install flag

Only if users regularly omit those skills.

## Avoid — disproportionate complexity

1. Database-backed state.
2. Hosted orchestration service.
3. General workflow engine.
4. Cryptographic evidence ledger.
5. Enterprise role/access model.
6. Generic YAML framework for all configuration.
7. Per-stack template explosion.
8. Full run-ledger analytics until a real incident proves the need.
9. Replacing Git with a second tracker.
10. Adding more agents before current trust boundaries are fixed.

---

# 12. Top ten improvements

1. **Stop mounting ignored credentials into the sandbox.**
2. **Block supervised phases before the headless builder runs.**
3. **Replace manual builder-writable `.phase-base` with a trusted phase-start anchor.**
4. **Bind the test command and protect it from in-phase mutation.**
5. **Run the evaluator in a disposable checkout that includes no persistent ignored state.**
6. **Make malformed `HIGH_STAKES_RE` a fail-closed configuration error.**
7. **Refuse manual completion when the working tree differs from HEAD.**
8. **Remove `/autopilot-parallel` from the default trusted surface.**
9. **Centralize roadmap phase parsing and strengthen strict lint.**
10. **Make ROADMAP/STATE completion updates atomic or mechanically repairable.**

---

# 13. Final verdict

## Is this a strong Claude Code setup?

**Yes.** It is unusually coherent, tested, and self-critical for a personal setup. The specification lifecycle, deterministic tick gate, sync model, and behavioral guard suite are real strengths.

## Is it trustworthy enough for unattended execution?

**Not yet.** It is suitable for low-stakes, reversible unattended work only when:

- the workspace contains no credentials;
- no supervised phase is next;
- test configuration is reviewed;
- the user accepts the current evaluator/test trust limits;
- the headless worktree mode is used.

It is not trustworthy for auth, money, migrations, deletion, deploys, email/webhooks, production credentials, or other irreversible effects.

## Is it appropriately lean for a personal workflow?

**Mostly.** The core is proportionate. The largest unnecessary complexity is `/autopilot-parallel`. Headless autopilot is justified only if it is used often enough to earn its maintenance burden.

## Single biggest strength

**The one-gate completion model:** a phase counts only through `tick.sh`, with evidence tied to the judged revision.

## Single biggest weakness

**The safety boundary is inconsistent across modes:** the strongest guarantees apply to headless worktree execution, while manual, parallel, and sandbox paths each retain different gaps that the documentation sometimes flattens into one trust story.

## What should change before the next release?

At minimum:

1. sandbox ignored-secret handling;
2. supervised pre-build blocking;
3. malformed high-stakes regex handling;
4. manual dirty-tree refusal;
5. regression tests for those four defects.

The phase-base, test-command, and ignored evaluator-state fixes should follow immediately if unattended execution remains a headline feature.

## What should deliberately remain unchanged?

- Git/file-based state.
- One deterministic tick gate.
- Manifest-based conservative sync.
- Small composable skills.
- Four-stage researcher/planner/executor/evaluator flow.
- Capped session context.
- Explicit human approval for high-stakes work.
- The project’s bias toward narrow shell scripts rather than a framework.

---

# Appendix A — Architectural dependency map

```text
install.sh
 ├─ copies jaimitos-os/*
 ├─ copies skills/* → .claude/skills/*
 ├─ writes .jaimitos-manifest
 ├─ writes version/high-stakes fingerprint
 └─ invokes doctor.sh non-fatally

docs/SPEC.md
 ├─ grill
 ├─ to-spec
 └─ roadmap → docs/ROADMAP.md

docs/ROADMAP.md
 ├─ /resume
 ├─ /phase
 ├─ /autopilot
 ├─ autopilot.sh
 ├─ close-milestone.sh
 ├─ lint-roadmap.sh
 └─ tick.sh → checkbox mutation

/phase
 ├─ researcher
 ├─ planner → docs/plans/<phase>.md
 ├─ executor → code/tests/commits
 └─ evaluator
     └─ _eval-isolation.sh

test-evidence.sh
 ├─ _test-cmd.sh
 └─ .tick-evidence.json

record-grade.sh
 └─ .phase-grade

tick.sh
 ├─ .phase-grade
 ├─ .tick-evidence.json
 ├─ _secret-scan.sh
 ├─ _high-stakes.sh
 ├─ ROADMAP mode
 └─ ROADMAP + STATE update

autopilot.sh
 ├─ worktree + lock + watchdog
 ├─ trusted PHASE_BASE
 ├─ gate-control integrity
 ├─ fresh builder/evaluator
 ├─ test-evidence.sh
 ├─ record-grade.sh
 └─ tick.sh

sync.sh
 ├─ toolkit checkout
 ├─ .jaimitos-manifest
 └─ managed-file update classification
```

# Appendix B — Failure-mode summary

| Failure | Current outcome |
|---|---|
| Missing evaluator grade | Tick refuses |
| Stale grade/evidence | Tick refuses |
| Failed tests | Tick refuses |
| No tests without evaluator confirmation | Tick refuses |
| Secret in committed phase diff | Tick refuses |
| High-stakes path/content in committed phase diff | Supervised/refusal |
| Gate-control file changed in headless | Headless refuses |
| Builder forges `.phase-base=HEAD` in headless | Trusted parent base overrides |
| Builder advances manual `.phase-base` to later ancestor | **Accepted; range narrows** |
| Dirty manual checkout after evidence | **Tick can proceed** |
| Malformed high-stakes regex | **No-match/fail-open** |
| Ignored evaluator-created fixture | **Invisible and persists** |
| Ignored `.env` before sandbox | **Not scanned, still mounted** |
| Supervised phase next in headless | **Builder runs, tick later refuses** |
| Existing settings during install | Preserved; hooks remain unwired; warning |
| Local modification during sync | Never overwritten |
| Local deletion during sync | Preserved unless explicit restore |
| Secret scan fails in checkpoint hook | No commit, but index selection reset |
| Milestone close with open tasks/findings | Refuses |
| Interrupted multi-file completion | Potential cross-file inconsistency; manual recovery |

# Appendix C — Evidence anchors

The most load-bearing implementation anchors are:

- `jaimitos-os/scripts/tick.sh:150-230`
- `jaimitos-os/scripts/autopilot.sh:295-385` and main loop after that section
- `jaimitos-os/.claude/lib/_eval-isolation.sh`
- `jaimitos-os/.claude/lib/_test-cmd.sh`
- `jaimitos-os/.claude/lib/_high-stakes.sh`
- `jaimitos-os/.claude/lib/_secret-scan.sh`
- `jaimitos-os/sandbox/run-autopilot-sandboxed.sh:54-95`
- `jaimitos-os/scripts/test-sandbox.sh:96-119`
- `jaimitos-os/.claude/commands/autopilot-parallel.md:17-20,93-109,139-141`
- `jaimitos-os/scripts/run-guard-tests.sh:34-65`
- `.github/scripts/install-smoke.sh`
- `jaimitos-os/scripts/test-sync.sh`
- `skills/roadmap/SKILL.md:14-102`
- `skills/README.md:19-52,105-129`
- `install.sh:180-280`
- `CHANGELOG.md:9-84`
