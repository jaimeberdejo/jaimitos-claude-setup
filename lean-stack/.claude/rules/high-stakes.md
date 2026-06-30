---
description: Extra care for high-stakes or hard-to-reverse code — auth, data migrations, anything that moves money or can't be cleanly undone.
paths:
  - "**/auth/**"
  - "**/payments/**"
  - "**/billing/**"
  - "**/transactions/**"
  - "**/migrations/**"
  - "**/compliance/**"
  - "**/suitability/**"
  - "**/secrets/**"
  - "**/*migration*"
  - "**/*money*"
  - "**/*payment*"
  - "**/*credential*"
---

# High-stakes code

This is a native `.claude/rules/` file. **Path-scoped (`paths:`) triggering is
currently unreliable in Claude Code** — known bugs mean it can load globally
regardless of the `paths:` filter, or fail to load even on matching files. So do
NOT rely on the `paths:` filter for enforcement. For GUARANTEED enforcement, either
remove the `paths:` filter (the rule will then always load) or keep these same
constraints in CLAUDE.md as well.

Edit the `paths:` above to match wherever YOUR irreversible/consequential code lives —
auth, schema migrations, billing, deletion paths, external-effect calls, anything where
a bug costs more than a re-run.

**The real enforcement lives in `.claude/hooks/_high-stakes.sh`** (`HIGH_STAKES_RE`):
`scripts/autopilot.sh` sources it and REFUSES to auto-tick/commit/push a phase whose
diff touches these paths — it stops for supervised review instead. The `paths:` list
above mirrors that regex; if you change one, change the other so the advisory rule and
the enforced gate stay in sync.

- **No autopilot here.** This is human-on-the-loop work: a loop may *surface* a diff,
  but a human approves it before it lands. Keep `permission_mode: default`.
- **Smallest possible phases.** One reviewable change at a time. No drive-by refactors.
- **Explainable line by line.** Record real decisions (and the alternative rejected)
  with the `adr` skill so the change is defensible later.
- **Never** run migrations against shared/prod data, perform irreversible deletes, or
  trigger external side effects (payments, emails) as part of an automated loop. Keep
  those outside the loop's blast radius (e.g. no prod credentials in the loop's env).
- **Money:** never use `float` for currency — use `Decimal` / integer minor units, and
  document the rounding.

If a task in these paths is ambiguous, STOP and ask rather than guessing.
