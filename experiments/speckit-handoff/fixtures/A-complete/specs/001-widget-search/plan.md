# Implementation Plan: Widget Search

## Technical Context
Python 3.12, FastAPI, Postgres. No new services.

## Constitution Check
PASS — no new project, no new service, test-first.

## Project Structure
```
src/search/query.py       # search_widgets(query, limit) — pure
src/search/ranking.py     # relevance scoring
src/api/widgets.py        # GET /widgets?q=
tests/test_search.py
```

## Phase 1 — Design
Ranking is trigram similarity on the name column, backed by a GIN index.
