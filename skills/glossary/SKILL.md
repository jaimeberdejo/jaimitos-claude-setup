---
name: glossary
description: Creates/updates docs/GLOSSARY.md when domain vocabulary crystallizes — one-line definitions plus the terms rejected. Use when naming settles — "glossary", "define el término", "cómo llamamos a", "we call this X, not Y", "add that to the glossary".
---

# Glossary

Capture the project's domain vocabulary the moment it crystallizes — "we call this X, not Y" is
a decision that evaporates unless written down. The artifact is `docs/GLOSSARY.md`, optional and
created lazily on the first resolved term.

## Format (docs/GLOSSARY.md)
```md
# Glossary

**Order** — a customer's request to buy, from placement to fulfillment.
_Avoid_: purchase, transaction

**Customer** — a person or organization that places orders.
_Avoid_: client, buyer, account (account is the login, not the person)
```

## Rules
- **Be opinionated.** When several words exist for one concept, pick the best and list the
  others under `_Avoid_` — the avoid-list is half the value. Record *why* a term lost, in
  four words, when the reason isn't obvious.
- **One line per definition.** What the term IS, not what the code does with it — keep
  implementation detail out of a canonical definition entirely.
- **Domain terms only.** General programming concepts (timeout, retry, cache) don't belong,
  however often the project uses them.
- **Update inline, as it happens.** Don't batch terms up for later; capture each one the moment
  it's resolved.

## Sharpen the vocabulary — don't just transcribe it
Interrogate the language while it's being spoken:
- **Challenge drift on the spot.** A term used against its entry gets called out immediately:
  "the glossary says 'cancellation' means X, but you seem to mean Y — which is it?"
- **Sharpen fuzzy or overloaded words.** Propose a precise canonical one: "you said 'account' —
  do you mean the Customer or the User? Those are different things."
- **One name, two concepts?** Split it and name both. **Two names, one concept?** Pick the
  winner, send the loser to `_Avoid_`.
- **Stress-test with edge cases.** Invent a concrete scenario the definition must survive — "a
  partial refund on a cancelled order: still an Order?" Boundaries only show up under pressure.
- **Cross-reference the code.** When what's stated contradicts what's written, surface it: "the
  code cancels whole Orders, but you said partial cancellation exists — which is right?"

## When a name hides a decision
Naming often exposes a real architectural choice. Offer an ADR — written by the `adr` skill, into
`docs/decisions/` — only when **all three** hold:
1. **Hard to reverse** — changing your mind later costs real work.
2. **Surprising without context** — a future reader will ask "why on earth did they do it this way?"
3. **A genuine trade-off** — there were real alternatives and one was picked for reasons.

Any one missing → **skip the ADR.** An easy-to-reverse, unsurprising, alternative-free "decision"
is just the glossary entry you already wrote.

## What this skill does NOT do
- It never writes ADRs. An architectural decision that surfaces while naming things goes to
  `docs/decisions/` via the `adr` skill — this file is a glossary and nothing else.
- No bounded-context machinery (context maps, per-context files). One `docs/GLOSSARY.md` per
  repo; if a term genuinely means two things in two areas, give it two entries that say where.

The session-start hook injects the first 30 lines of `docs/GLOSSARY.md` into every session, so
keep it tight — the most load-bearing terms first.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
