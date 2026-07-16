# ADR-003: All repository mapping stays inside the `mapme` skill

Date: 2026-07-16
Decision: Brownfield onboarding, ownership mapping, dependency/test/risk maps, stated-vs-actual architecture, and staleness all ship as bounded MODES of the existing `mapme` skill (`--brownfield`, `--ownership`, `--refresh`), writing GENERATED VIEW documents that never become canonical state — not as new skills.
Why: A separate brownfield-onboard / ownership-map / architecture skill would fragment the single "read the code as it is, map it, flag friction but never fix it" capability, duplicate its guardrails, and grow the always-loaded skill-description surface. Folding the modes into `mapme` keeps one owner and near-zero always-loaded cost. The rejected alternative — dedicated per-mode skills — was overlap the toolkit's derive-don't-duplicate discipline rules out.
