# Implementation Plan: Account Recovery

## Technical Context
Python 3.12, FastAPI, Postgres. Sends email via the existing transactional provider.

## Project Structure
```
src/auth/reset.py             # token issue + redeem
src/auth/sessions.py          # session invalidation
migrations/0007_reset_token.sql
tests/test_reset.py
```
