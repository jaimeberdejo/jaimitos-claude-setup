# Tasks: Widget Search

- [ ] T001 [P] [US1] add a GIN trigram index on widget.name
- [ ] T002 [US1] implement search_widgets(query, limit) in src/search/query.py
- [ ] T003 [US1] implement relevance ordering in src/search/ranking.py
- [ ] T004 [US1] expose GET /widgets?q= in src/api/widgets.py
- [ ] T005 [US2] empty-state response when there are no matches
