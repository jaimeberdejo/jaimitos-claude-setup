# Feature Specification: Widget Search

## Clarifications

### Session 2026-07-14
- Q: Should search match widget descriptions as well as names? → A: Names only for v1; descriptions are a follow-up.
- Q: What should an empty result set show? → A: An empty state with the query echoed back and a "clear search" action.

## User Scenarios

### User Story 1 - Find a widget by name (Priority: P1)
A user types part of a widget's name and sees matching widgets ranked by relevance.

### User Story 2 - Recover from a bad search (Priority: P2)
A user whose search returns nothing is told so plainly and can clear it in one action.

## Requirements

### Functional Requirements

- **FR-001**: System MUST return widgets whose name contains the query, case-insensitively.
- **FR-002**: System MUST order results by relevance, most relevant first.
- **FR-003**: System MUST show an empty state, echoing the query, when nothing matches.
- **FR-004**: System MUST expose search at `GET /widgets?q=<query>`.

### Success Criteria / Measurable Outcomes

- **SC-001**: p95 search latency is under 200 ms against the 10k-widget fixture.
- **SC-002**: A user finds a known widget in under 10 seconds from the home page.
- **SC-003**: Searching a term with no matches returns HTTP 200 and 0 results, never a 404.
