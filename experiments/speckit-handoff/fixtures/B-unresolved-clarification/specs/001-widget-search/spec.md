# Feature Specification: Widget Search

## Requirements

### Functional Requirements

- **FR-001**: System MUST return widgets whose name contains the query, case-insensitively.
- **FR-002**: System MUST order results by [NEEDS CLARIFICATION: relevance not defined — trigram similarity, popularity, or recency?]
- **FR-003**: System MUST show an empty state when nothing matches.

### Success Criteria / Measurable Outcomes

- **SC-001**: p95 search latency is under 200 ms against the 10k-widget fixture.
