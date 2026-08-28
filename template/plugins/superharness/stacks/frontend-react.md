# Frontend stack: React

This project's frontend is **React**. Apply these conventions when working here.

## Layout
- `src/components/` reusable components (one component per file, PascalCase).
- `src/pages/` or `src/routes/` route-level components.
- `src/hooks/` custom hooks (`useX` naming). `src/lib/` framework-agnostic helpers.

## Testing (TDD — write the failing test first)
- Test runner: **Vitest**. Component tests: **@testing-library/react** + `@testing-library/jest-dom`.
- Run all: `npm run test`. Single file: `npx vitest run src/components/Foo.test.tsx`.
- Test behavior through the rendered DOM (roles, text, user events), not implementation details.
- User interaction via `@testing-library/user-event`, not raw `fireEvent` where avoidable.

## Standards
- TypeScript, strict mode. Function components + hooks only (no class components).
- Keep components small and pure; lift side effects into hooks. Co-locate `Foo.tsx` + `Foo.test.tsx`.
- Lint/format with ESLint + Prettier; run `npm run lint` before claiming done.

## Verify commands against the project
The commands above are defaults, not repo facts. Before first use, check
`package.json` scripts and the lockfile (npm/pnpm/yarn/bun) and use what the
project actually defines. Never install an alternative runner to make a command
work.

## Test boundaries & mocking
- Do not mock what you are testing: render the real component tree with real
  children; mock only true externalities.
- Network -> **msw** handlers returning realistic payloads, not module-mocked
  axios/fetch. Time -> injectable clock, not global fake timers where avoidable.
- Test hooks with `renderHook` and real dependencies; stub a provider/context
  only when it is owned elsewhere in the app.

## Key libraries (verify versions against package.json)
- React 18/19; router: React Router v6/v7 (or the project's framework router).
- Data: TanStack Query. Forms: react-hook-form + zod. State: component state
  first, then Context/Zustand — no global store by default.
