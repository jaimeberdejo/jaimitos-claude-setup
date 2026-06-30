---
description: Extra care for high-stakes or hard-to-reverse code — auth, data migrations, anything that moves money or can't be cleanly undone.
paths:
  - "**/auth/**"
  - "**/migrations/**"
  - "**/payments/**"
  - "**/billing/**"
  - "**/*migration*"
  - "**/*money*"
  - "**/*payment*"
---

# High-stakes code (loaded only when these paths are touched)

Edit the `paths:` above to match wherever YOUR irreversible/consequential code lives —
auth, schema migrations, billing, deletion paths, external-effect calls, anything where
a bug costs more than a re-run. This rule is path-scoped and re-injected on compaction,
so it stays in force while you work in these files.

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
