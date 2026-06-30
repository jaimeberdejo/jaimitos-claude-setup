# Lean Stack — the scaffold

> Part of **[my-claude-code-setup](../README.md)** — the repo-root README is the master
> guide. This file is the self-contained quick-start for when only this folder is dropped
> into a project.

Complete scaffold + guides. Drop the contents into any repo.

- **GUIDE.md** — start here. Install, the per-phase cycle, use cases, autonomy, tutorials.
  (Hands-on practice project lives at the repo root: `PRACTICE-PROJECT.md`.)
- **LOOP-ENGINEERING.md** — designing/running autonomous loops safely.
- **CLAUDE.md** — lean constitution (edit placeholders). Includes Ownership section.
- **.claude/** — hooks, commands (/resume /wrap /phase), evaluator subagent.
- **docs/** — SPEC/ROADMAP/STATE/ARCHITECTURE templates + decisions/ for ADRs.
- **scripts/autopilot.sh** — guarded autonomous loop runner.

## Quick start
    npx skills@latest add mattpocock/skills
    npm i -g @fission-ai/openspec && openspec init
    chmod +x .claude/hooks/*.sh scripts/*.sh
    # NOTE: don't blanket-set CLAUDE_CODE_SUBAGENT_MODEL=haiku — it OVERRIDES the
    # evaluator's sonnet frontmatter and downgrades your grader. See GUIDE.md §setup.
    # ENABLE_TOOL_SEARCH is unverified against current docs — confirm before relying on it.
    bash scripts/doctor.sh        # verify tooling, scaffold, settings, hooks
    bash scripts/test-hooks.sh    # smoke-test the hooks
Then open GUIDE.md.

## Safety note
`.claude/settings.json` ships with `permissions.deny` rules so Claude can't read
`.env`/secrets/keys (`.gitignore` alone does NOT prevent reads). Extend them per project.
The autopilot loop has preflight checks, strict evaluator-verdict parsing, and a
per-phase thrash cap — run `doctor.sh` green before any unattended run.

## Pair with the skill packs
- personal-skills.zip — roadmap, adr, ship-check, scope-guard, explain-diff, unstick
- ownership pack (in skills/) — teach-back, mapme, quizme
Copy any of these into .claude/skills/ (per project) or ~/.claude/skills/ (global).
