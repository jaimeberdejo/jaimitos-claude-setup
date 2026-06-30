# my-claude-code-setup

A lean, **project-neutral operating system for Claude Code**: auto-maintained docs,
deterministic hooks, an independent grader, two autonomous loops (one you can watch, one
for overnight), path-scoped rules, and a pack of portable skills — at a fraction of the
token cost of heavyweight planning frameworks.

It reproduces what big multi-agent frameworks automate — spec, roadmap, persistent state,
decision log, phase execution, independent verification — with **one context at a time, no
research fan-out**, so you keep full visibility and a 1-experienced-dev token budget.

> **The one idea:** `CLAUDE.md` advises · **hooks enforce** · **docs hold knowledge**.
> Never ask one to do another's job. And **match ceremony to stakes**: tiny/reversible →
> just prompt; medium → supervised; big/mechanical/low-stakes → autopilot; high-stakes →
> human-on-the-loop.

---

## Repository layout

```
my-claude-code-setup/
├── README.md              ← you are here (the master guide)
├── install.sh             ← one-command installer (deterministic copy + doctor)
├── PRACTICE-PROJECT.md    ← standalone hands-on tutorial (delete after you've learned the stack)
├── CHANGELOG.md · VERSION · LICENSE · .editorconfig
├── lean-stack/            ← the scaffold you drop into a repo
│   ├── CLAUDE.md                    # lean constitution (edit placeholders per project)   [installed]
│   ├── SCAFFOLD.md                  # scaffold quick-start (ships as SCAFFOLD.md, never clobbers README) [installed]
│   ├── GUIDE.md                     # the full manual                          [toolkit doc — NOT copied into targets]
│   ├── LOOP-ENGINEERING.md          # the theory of safe autonomous loops      [toolkit doc — NOT copied into targets]
│   ├── docs/                        # SPEC · ROADMAP · STATE · ARCHITECTURE · decisions/ · plans/
│   ├── scripts/                     # autopilot.sh · doctor.sh · test-hooks.sh
│   ├── .github/workflows/lean-stack-ci.yml   # OPT-IN CI (install.sh --with-ci)
│   └── .claude/
│       ├── settings.json            # hooks → events + permissions.deny
│       ├── commands/                # /resume /wrap /phase /autopilot
│       ├── agents/evaluator.md      # independent grader
│       ├── rules/high-stakes.md     # path-scoped extra care
│       └── hooks/                   # 7 deterministic shell hooks + 2 shared libs (_secret-scan, _high-stakes)
└── skills/                ← 10 portable skills (9 workflow/ownership + setup-lean-stack)
```

> The repo-root `README.md`, `GUIDE.md`, and `LOOP-ENGINEERING.md` document the **toolkit**, so
> `install.sh` never copies them into your project (they'd just be noise). Only `SCAFFOLD.md` —
> a short, clearly-named quick-start — ships alongside the working files.

There are **two parts**: the **`lean-stack/` scaffold** (drop its contents into any repo)
and the **`skills/` pack** (copy any skill into `.claude/skills/` per-project, or
`~/.claude/skills/` globally). They're designed to work together but each stands alone.

---

## Install

### Prerequisites

Install these before running `install.sh` or any unattended loop:

| Tool | Required? | Install | Why |
|---|---|---|---|
| `git` | **required** | preinstalled / `brew install git` / `apt-get install git` | hooks, `commit-on-stop`, and autopilot all assume a git repo |
| `jq` | **required** | `brew install jq` / `apt-get install jq` | the hooks and `autopilot.sh` parse JSON with it — **autopilot's preflight hard-fails without `jq`** |
| `claude` CLI | **required** | see [Claude Code docs](https://docs.claude.com/en/docs/claude-code) | runs the loops, subagents, and the headless `autopilot.sh` |
| `gh` | optional | `brew install gh` / `apt-get install gh` | only needed for `autopilot.sh --pr` (opening a PR) |

`bash scripts/doctor.sh` checks for these and reports anything missing.

First, clone this repo somewhere stable:

```bash
git clone https://github.com/jaimeberdejo/my-claude-code-setup ~/my-claude-code-setup
```

Then pick one of three ways to get it into a project, from most to least automated:

### Option A — one command (recommended)
```bash
bash ~/my-claude-code-setup/install.sh /path/to/your-repo
```
`install.sh` does the **deterministic** part: copies the scaffold, copies all skills into
`.claude/skills/`, `chmod +x`s the hooks/scripts, and runs `doctor.sh`. It's **idempotent** —
re-running skips files that already exist, so it never clobbers a `CLAUDE.md` you've
customized. It does **not** copy the toolkit docs (GUIDE/LOOP-ENGINEERING/README) into your
project. Flags: `--force` (overwrite existing files), `--global-skills` (also install the
skills into `~/.claude/skills/` for all projects), `--with-ci` (also drop the opt-in
`lean-stack-ci.yml` CI workflow).

### Option B — the `setup-lean-stack` skill (install **and** customize)
Install the skills globally once (`install.sh --global-skills`, or copy `skills/*` into
`~/.claude/skills/`), then in any project just say *"set up the lean stack here."* The
`setup-lean-stack` skill runs `install.sh` for the copy, then does the **intelligent** part a
blind copy can't: detects your stack, fills `CLAUDE.md`'s test/lint/run commands, points
`high-stakes.md` at your real sensitive dirs, and runs the health checks.

### Option C — manual copy
```bash
cp -r ~/my-claude-code-setup/lean-stack/. /path/to/your-repo/
mkdir -p /path/to/your-repo/.claude/skills && cp -r ~/my-claude-code-setup/skills/*/ /path/to/your-repo/.claude/skills/
cd /path/to/your-repo && chmod +x .claude/hooks/*.sh scripts/*.sh && bash scripts/doctor.sh
```

After any option: edit `CLAUDE.md`'s placeholders (your real commands) if the skill didn't,
then describe the project → `docs/SPEC.md`, run the `roadmap` skill → `docs/ROADMAP.md`, and loop.

> **Why a script and not an "init" skill that writes the files?** Copying static files must
> be deterministic — having a model regenerate ~40 files risks drift, costs tokens, and is
> the exact bug this setup avoids elsewhere. So `install.sh` owns the copy; the skill only
> owns the judgment (filling placeholders). Deterministic work stays deterministic.

> **Model note:** don't blanket-set `CLAUDE_CODE_SUBAGENT_MODEL=haiku` — it *overrides*
> the evaluator's `model: sonnet` and would downgrade your grader (the one place you want
> the strong model).

---

## The core loop

```
SPEC once  →  ROADMAP once  →  [ /resume → /phase → review → teach-back → /wrap → /clear ] × N  →  ship
```

- **SPEC once** — describe the project; write `docs/SPEC.md` with a *measurable* success criterion.
- **ROADMAP once** — the `roadmap` skill breaks the spec into phases, each with a checklist
  and a machine-checkable `Done when:` line.
- **The bracket, per phase** — orient, build one phase (research → plan → TDD → independent
  grade), capture ownership + decisions, update docs, clear context.
- **Ship** — full test pass, README, tag.

You drive each arrow manually for stakes that warrant it, or hand the bracket to an autopilot.

---

## Commands

| Command | What it does |
|---|---|
| `/resume` | Reads SPEC+ROADMAP+STATE, states the single next action, then waits. Orientation only. |
| `/phase` | Builds one roadmap phase: research-if-needed → plan → TDD → evaluator self-check. **Does not tick the roadmap** (that's gated on an independent grade). |
| `/autopilot N` | **Watchable** in-session loop: runs N phases in your terminal, grading each via the evaluator subagent. Accepts `N`, `3-5`, or `all`. |
| `/wrap` | Session close-out: update STATE, tick ROADMAP (only evaluator-confirmed items), append an ADR. |

## Agent & rules

| File | Role |
|---|---|
| `agents/evaluator.md` | Independent grader — fresh context, **no edit tools**, default-FAIL contract. Grades only; never ticks. The sole gate on "done." |
| `rules/high-stakes.md` | Native `.claude/rules/` file scoped to auth/migrations/money/etc. paths. Path-scoped loading is currently unreliable in Claude Code, so the **same constraints are also kept in `CLAUDE.md`** (which loads every turn) — don't rely on the rule auto-loading. Point its `paths:` at *your* sensitive dirs. |

## Hooks (deterministic enforcement)

Seven deterministic shell hooks (session-start, steer, kill-switch, format-on-edit, test-gate,
commit-on-stop, ownership-nudge) plus two sourced libraries (`_secret-scan.sh`,
`_high-stakes.sh`) shared by `commit-on-stop.sh` and `autopilot.sh`. **The full per-hook table
lives in [`lean-stack/GUIDE.md`](lean-stack/GUIDE.md)** under "The seven hooks" (single source —
kept there so it can't drift), alongside the **"Enforcement reality"** section on what enforces
vs what merely advises.

## Skills (`skills/`)

Six workflow skills (roadmap, adr, ship-check, scope-guard, explain-diff, unstick), three
ownership skills (teach-back, mapme, quizme), and the `setup-lean-stack` meta-skill. The three
review skills are **report-only** (`disallowed-tools: Edit, Write, …`); a clean pre-commit chain
is **`scope-guard → explain-diff → ship-check`**.

**The full skills catalog lives in [`skills/README.md`](skills/README.md)** (workflow) and
**[`skills/OWNERSHIP.md`](skills/OWNERSHIP.md)** (ownership) — single source, so this list never
drifts from it.

---

## Autonomy

Three ways to run, in order of trust:

| Mode | How | When |
|---|---|---|
| Manual | `/phase`, you review each diff | medium stakes, your daily default |
| Watchable loop | `/autopilot N` (in-session) | a few phases you want to *see* run |
| Headless loop | `bash scripts/autopilot.sh N [--no-worktree] [--pr] [--allow-dirty] [--max-minutes N]` | long/overnight, low-stakes, reversible |

`scripts/autopilot.sh` accepts `N` (up to N), `N-M` (aim for N, cap M), or `all` (malformed
counts are rejected, not ignored). **Worktree isolation is the default** — a bad run can't touch
your checkout; `--no-worktree` opts out (runs in-place, warned loudly). `--pr` opens a PR at the
end and never touches main (secret-scanned before any push); `--allow-dirty` skips the clean-tree
preflight (use sparingly — it removes a safety check); `--max-minutes N` adds a wall-clock ceiling.

**The guardrails** (see `lean-stack/LOOP-ENGINEERING.md` for the full theory):
verifiable signal · bounded stop · bounded retries (3-strike thrash cap) · blast-radius
limit · **independent verifier as the sole roadmap-ticker** · evaluator-change cleanup ·
**high-stakes gate** (auth/money/migrations → supervised stop, never auto-ticked) ·
secret-scan before commit/push · kill-switch · budget cap. The builder *never* marks its own
work done — a fresh-context, no-edit-tools evaluator always gates the tick.

---

## Security

**Enforcement reality — know which tier you're trusting** (full version in
[`GUIDE.md` → "Enforcement reality"](lean-stack/GUIDE.md#enforcement-reality-deterministic-layer-vs-advisory-layer)):
the **deterministic** layer (shell hooks + `autopilot.sh` control flow — kill-switch, strict
verdict parsing, secret-scan, high-stakes gate, evaluator-change cleanup) actually enforces and
fails closed; the **advisory** layer (`CLAUDE.md`, `rules/`, the evaluator prompt) only asks a
model to comply.

- `.gitignore` stops *committing* `.env`; it does **not** stop *reading* it. `settings.json`
  ships a `permissions.deny` block for `.env*`, `secrets/**`, `*.pem`, `*.key`, credentials.
- The `Read(...)` denies are a **real boundary**. The `Bash(...)` denies are a **best-effort
  speed-bump** (bypassable via `less`, `source`, `python -c …`), not containment — the real shell
  boundary is a sandbox/no-creds container + `permission_mode: default` for sensitive work.
- High-stakes code (auth/migrations/money/deletes/external effects): supervised only, smallest
  phases, audit trail. The `high-stakes.md` rule advises it **and** `autopilot.sh`'s high-stakes
  gate enforces it (a graded phase touching those paths is never auto-ticked/committed/pushed).

---

## Health & maintenance

- `bash scripts/doctor.sh` — one-command health check (run before any unattended run).
- `bash scripts/test-hooks.sh` — hook smoke tests (incl. the secret-scan guard).
- **Repo CI** `.github/workflows/ci.yml` — on push/PR, runs shell-syntax + `settings.json`
  validation against `lean-stack/`, lints `install.sh`, and runs the **install smoke test**
  (`.github/scripts/install-smoke.sh`: no tool-doc pollution, no README clobber, idempotent,
  `.gitignore` merge). The scaffold's own `lean-stack-ci.yml` is opt-in for installed projects.

---

## Troubleshooting

| Symptom | One-line fix |
|---|---|
| `doctor.sh` prints a ✗ | It names the missing piece — run the matching install step (e.g. `brew install jq`, install the `claude` CLI) and re-run `doctor.sh`. |
| Hooks not firing | `chmod +x .claude/hooks/*.sh scripts/*.sh`, and confirm they're wired in `.claude/settings.json`. |
| `format-on-edit` silently skips a file | Expected — there's no project-local formatter for that file type. Install/configure one (ruff, prettier+eslint) if you want formatting. |
| Evaluator verdict "unrecognized" | By design the loop stops rather than guess — read the evaluator's output and fix the phase (or the criteria) so it emits a clean PASS/FAIL. |
| Leftover autopilot worktree | `git worktree remove <path>` (add `--force` if it refuses); `git worktree list` shows them. |
| `autopilot.sh` preflight aborts | Most often missing `jq` (hard-fail) or a dirty tree — install `jq`, commit/stash, or pass `--allow-dirty` knowingly. |

---

## Where to read more

- **`lean-stack/GUIDE.md`** — the full manual: install, the per-phase research→plan→execute→verify
  cycle, five worked use cases, autonomy in depth, and step-by-step tutorials.
- **`lean-stack/LOOP-ENGINEERING.md`** — designing and running autonomous loops safely (the theory).
- **`PRACTICE-PROJECT.md`** — a standalone, throwaway tutorial to learn the whole stack hands-on,
  then delete. Lives at the repo root so `install.sh` never copies it into your real projects.

## License

[MIT](LICENSE) © 2026 Jaime Berdejo ([@jaimeberdejo](https://github.com/jaimeberdejo)).
