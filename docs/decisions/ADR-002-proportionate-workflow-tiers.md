# ADR-002: Proportionate workflow tiers (TINY / STANDARD / DEEP)

Date: 2026-07-16
Decision: Add three workflow tiers recommended by an inspectable `scripts/classify-work.sh` from explicit risk/complexity signals and recorded (overridably) in `docs/SPEC.md` `tier:`, governing how much specification, mapping, plan-check, and UAT ceremony a unit of work carries — rather than applying one fixed ceremony to every change. TINY stays compact; STANDARD uses native REQ/AC + PLAN_CHECK; DEEP adds research, architecture, ownership, and the enforcement ledger.
Why: One-size ceremony either over-taxes tiny reversible work or under-protects high-stakes work; a visible, overridable, signal-driven tier makes ceremony proportionate to risk while keeping the decision inspectable. The rejected alternative — opaque or model-selected routing — hides authority and cannot be audited, which the "don't overstate enforcement" discipline forbids.
