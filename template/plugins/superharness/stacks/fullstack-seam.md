# Fullstack seam rules

This project is **fullstack**: a frontend app and a backend API. Apply the frontend
and backend conventions above plus the seam rules below.

## Layout
- `frontend/` frontend app; `backend/` backend app. Keep them independently testable.

## The seam (frontend <-> backend)
- **API contract is the contract.** Define request/response shapes once; mirror them as types
  on the frontend. Change them in lockstep and update tests on both sides in the same task.
- **CORS:** backend allows the dev frontend origin; do not disable CORS globally.
- **Dev proxy:** frontend dev server proxies `/api` to the backend to avoid origin mismatch.
- **End-to-end:** cover at least one real frontend->backend flow with an e2e/integration test.

## Discipline
- TDD on both sides. Run the frontend and backend test suites before claiming done.
