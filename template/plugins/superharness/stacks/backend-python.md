# Backend stack: Python

This project's backend is **Python**. Apply these conventions when working here.

## Layout
- `src/<package>/` application code. `tests/` mirrors the package tree.
- API layer (FastAPI routers / Django views) thin; business logic in service modules.

## Testing (TDD — write the failing test first)
- Test runner: **pytest**. Run all: `pytest`. Single test: `pytest tests/test_foo.py::test_bar -v`.
- Use fixtures for setup; parametrize for input variations. Assert on behavior/return values.
- HTTP layer: FastAPI `TestClient` / Django test client against real routes.

## Standards
- Type hints everywhere; check with `mypy`. Format with `black`, lint with `ruff`.
- Manage deps with the project's tool (`pyproject.toml` + uv/poetry, or `requirements.txt`).
- Run `ruff check` and the full `pytest` suite before claiming done.

## Verify commands against the project
The commands above are defaults, not repo facts. Check how the project is meant
to run: bare `pytest` vs `uv run pytest` vs `poetry run pytest`, and any
`tox.ini`/`noxfile.py` env definitions. Use the project's own invocation.

## Test boundaries & mocking
- Never mock the unit under test; mock only true seams (external HTTP, clock,
  filesystem) via fixtures or `monkeypatch` at the point of use.
- Outbound HTTP -> `responses` or `respx` against real request code.
- Database: session-scoped in-memory SQLite or a test fixture DB with real
  repositories — do not mock your own repository layer inside service tests
  unless speed demonstrably demands it.
- FastAPI: `app.dependency_overrides` for auth/session dependencies; run
  `TestClient` against the real ASGI app.

## Key libraries (verify versions against pyproject/requirements)
- Python 3.11+; FastAPI 0.11x + Pydantic v2 (or Django 5 where the project
  uses it). HTTP client: httpx. DB: SQLAlchemy 2.x.
