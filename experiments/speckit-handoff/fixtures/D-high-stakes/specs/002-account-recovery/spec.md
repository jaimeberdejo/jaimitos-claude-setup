# Feature Specification: Account Recovery

## Requirements

### Functional Requirements

- **FR-001**: System MUST let a user request a password reset by email address.
- **FR-002**: System MUST issue a single-use reset token that expires in 15 minutes.
- **FR-003**: System MUST NOT reveal whether an email address is registered.
- **FR-004**: System MUST invalidate all active sessions when a password is reset.

### Success Criteria / Measurable Outcomes

- **SC-001**: A reset token is unusable more than 15 minutes after issue.
- **SC-002**: A reset token cannot be used twice.
- **SC-003**: Response time for a reset request is within 50 ms of the same request for an unknown address.
