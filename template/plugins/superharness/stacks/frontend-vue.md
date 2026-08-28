# Frontend stack: Vue

This project's frontend is **Vue 3**. Apply these conventions when working here.

## Layout
- `src/components/` reusable components (`<script setup>` SFCs, PascalCase filenames).
- `src/views/` route-level views. `src/composables/` composition functions (`useX`).
- `src/stores/` Pinia stores. `src/lib/` framework-agnostic helpers.

## Testing (TDD — write the failing test first)
- Test runner: **Vitest**. Component tests: **@vue/test-utils** + `@testing-library/jest-dom`.
- Run all: `npm run test`. Single file: `npx vitest run src/components/Foo.spec.ts`.
- Mount the component and assert on rendered output and emitted events, not internal refs.

## Standards
- TypeScript + `<script setup>`. Composition API only (no Options API for new code).
- Keep components small; extract logic into composables. Co-locate `Foo.vue` + `Foo.spec.ts`.
- Lint/format with ESLint + Prettier; run `npm run lint` before claiming done.

## Verify commands against the project
The commands above are defaults, not repo facts. Check `package.json` scripts
and the lockfile (pnpm is common in Vue projects) and use what the project
actually defines before running anything.

## Test boundaries & mocking
- Mount real child components; `global.stubs` only for leaf externalities.
- Network -> **msw** handlers, not module-mocked axios/fetch.
- Pinia: use real stores (`createPinia()` / `createTestingPinia`), never
  hand-mock store internals.
- Router: install the real router with memory history instead of mocking
  `$route`.

## Key libraries (verify versions against package.json)
- Vue 3.4+ Composition API; vue-router 4; Pinia for state.
- Utils: VueUse. Data: TanStack Query (Vue adapter) or a thin fetch layer.
- Validation: vee-validate + zod (or `useVuelidate` + zod).
