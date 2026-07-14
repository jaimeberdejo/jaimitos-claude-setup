---
status: ready
---
# Spec

## What & why
A catalogue app. Users browse widgets and find the one they need fast.

## Success criterion (measurable)
A user can locate a known widget in under 10 seconds from the home page.

## In scope
- Browsing the widget catalogue
- Searching the widget catalogue
- Widget detail pages

## Non-goals (explicitly NOT building)
- User accounts, login, or any authentication
- Payments or checkout
- Social features (comments, sharing, follows)

## Constraints
- Python 3.12 + FastAPI. Postgres. No new services.

## Open questions
-

## Test seams
- `search_widgets(query, limit)` — pure, no I/O
