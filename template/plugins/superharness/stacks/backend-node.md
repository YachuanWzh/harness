# Backend stack: Node

This project's backend is **Node** (TypeScript). Apply these conventions when working here.

## Layout
- `src/` application code; routes thin (Express/Fastify), logic in `src/services/`.
- `src/**/*.test.ts` co-located or a `tests/` tree mirroring `src/`.

## Testing (TDD — write the failing test first)
- Test runner: **Jest** (ts-jest) or **Vitest** — follow whatever the repo already uses.
- Run all: `npm run test`. Single: `npx jest src/services/foo.test.ts` (or the vitest equivalent).
- HTTP layer: **supertest** against the real app instance. Assert on responses, not internals.

## Standards
- TypeScript, strict mode. `async/await` over raw promises; handle errors explicitly.
- Lint/format with ESLint + Prettier; run `npm run lint` and the full test suite before done.

## Verify commands against the project
The commands above are defaults, not repo facts. Read `package.json` scripts
and the lockfile first (npm/pnpm/yarn/bun; jest vs vitest vs `node:test`) and
use exactly what the project defines.

## Test boundaries & mocking
- Inject dependencies (constructor/factory); in unit tests replace them at the
  boundary instead of reaching for module-level `jest.mock` hoisting hacks.
- Outbound HTTP -> `nock` or undici `MockAgent`; never mock the module under
  test itself.
- Database: supertest against the real app instance backed by a temp/fixture DB
  — keep repositories real in service tests.

## Key libraries (verify versions against package.json)
- Node 20/22 LTS; TypeScript 5.x strict. HTTP: Fastify or Express.
- Validation: zod. DB: Prisma / Drizzle / Kysely (follow the repo's choice).
