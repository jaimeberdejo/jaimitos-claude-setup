# Security Policy

This is a personal, MIT-licensed open-source project. The guidance below is honest about
what it does and does not protect — read the **Scope** section before relying on any guard.

## Supported versions

Only the **latest release** is supported. The current version is in
[`VERSION`](VERSION) (and stamped into installed projects as
`.claude/.lean-stack-version`). Fixes land on the newest release; older tags get nothing.
If you installed an older copy, re-run `install.sh --force` from a fresh clone to update.

## Reporting a vulnerability

Please **do not open a public issue for anything sensitive** (a way to exfiltrate secrets,
bypass the high-stakes gate, defeat the secret-scan, etc.). Instead:

- Open a **private GitHub security advisory** on the repo (Security → "Report a
  vulnerability"), **or**
- Open a private issue / email the maintainer ([@jaimeberdejo](https://github.com/jaimeberdejo))
  with enough detail to reproduce.

This is a side project: **no SLA, no bounty, best-effort response only.** Non-sensitive bugs
and hardening ideas are welcome as normal public issues or PRs (see
[`CONTRIBUTING.md`](CONTRIBUTING.md)). A matching test for any safety fix is appreciated.

## Scope

**What this project tries to do:** ship deterministic shell hooks, a headless-loop control
flow, and sensible defaults that make a *good* automated run likely and a *bad* one loud.
Read the GUIDE's ["Enforcement reality"](lean-stack/toolkit-docs/GUIDE.md#enforcement-reality-deterministic-layer-vs-advisory-layer)
section — the deterministic layer (hooks + `autopilot.sh`) fails closed; the advisory layer
(`CLAUDE.md`, `rules/`, the evaluator prompt) only *asks* a model to comply.

**What it explicitly does NOT guarantee — your responsibility:**

- **The secret-scan is a best-effort commit-time guard, NOT a secret scanner.** It matches
  secret-y filenames plus high-confidence token regexes (AWS `AKIA`, PEM blocks, OpenAI `sk-`,
  Stripe `sk_live_`/`rk_live_`, GitHub `ghp_…`, Slack `xox*`, Google `AIza…`, and URLs with an
  embedded `user:password`) over the staged diff. It will miss novel or encoded secrets. Use a
  real scanner (gitleaks, trufflehog, GitHub secret scanning) and pre-commit hooks for coverage.
- **`permissions.deny` is defense-in-depth, not a boundary.** The `Read(...)` denies are a
  real boundary; the `Bash(...)` denies are a bypassable speed-bump (`less`, `source`,
  `python -c …`). The real boundary for unattended runs is the **environment**: a
  sandbox/container with **no production credentials** and constrained egress, plus
  `permission_mode: default`. This scaffold can't sandbox itself.
- **The high-stakes gate only protects paths YOU point it at.** Out of the box,
  `HIGH_STAKES_RE` in `_high-stakes.sh` and `paths:` in `high-stakes.md` are generic
  examples. If you don't edit them to match your real auth/migration/money/delete dirs, a
  loop can auto-tick and commit those paths. Editing only the advisory rule (not the enforced
  regex) silently disables enforcement — `doctor.sh` warns when the default is untouched.
- **Autopilot is for low-stakes, reversible code only.** Worktree isolation and the kill-switch
  reduce blast radius; they do not make irreversible actions safe. Set a hard budget cap as the
  outer backstop.

In short: the guards here make mistakes *visible and bounded*. Containment is on you.
