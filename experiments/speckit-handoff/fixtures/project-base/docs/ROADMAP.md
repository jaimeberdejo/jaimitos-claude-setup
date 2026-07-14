# Roadmap

> `- [ ]` = todo, `- [x]` = done. Each phase must leave the app working and demoable.

## Phase 1 — Browse the widget catalogue
- [x] list widgets from the database
- [x] widget detail page
Done when: `pytest tests/test_catalogue.py` is green and the list renders 100 widgets
Mode: loopable

## Phase 2 — Paginate the catalogue
- [ ] page the widget list at 25 per page
Done when: `pytest tests/test_pagination.py` is green
Mode: loopable
