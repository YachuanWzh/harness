# Fullstack seam rules

This project is **fullstack**: a frontend app and a backend API. Apply the frontend
and backend conventions above plus the seam rules below.

## Layout
- `frontend/` frontend app; `backend/` backend app. Keep them independently testable.

## The seam (frontend <-> backend)
- **API contract is the contract.** Define request/response shapes once; mirror
  them as types on the frontend. Change them in lockstep and update tests on
  both sides in the same task.
- **Contract-first evolution.** The schema (OpenAPI spec, or the shared
  types/zod/pydantic source of truth with generated frontend types) is edited
  first; frontend types are generated or checked against it in CI — hand-synced
  duplicates drift.
- **TDD order for seam changes:** write the failing contract test first
  (backend response vs schema, frontend type/API mock vs schema), then
  implement both sides to green.
- **Versioning & idempotency:** breaking response changes get a versioned route
  or additive fields (old clients keep working); retried mutating endpoints are
  idempotent (client-generated request key or natural idempotency).
- **CORS:** backend allows the dev frontend origin; do not disable CORS globally.
- **Dev proxy:** frontend dev server proxies `/api` to the backend to avoid origin mismatch.
- **End-to-end:** cover at least one real frontend->backend flow with an
  e2e/integration test; **Playwright** is the default choice (Cypress if the
  repo already uses it).

## Discipline
- TDD on both sides. Run the frontend and backend test suites before claiming done.
