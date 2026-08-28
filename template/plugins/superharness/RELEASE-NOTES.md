### Latest update (v1.1.0)

- Added an npm-distributed, cross-platform `superharness` command for Windows and macOS/Linux.
- Installing through `@flavor-code/plugin-manager` now initializes `FLAVOR.md`, `CLAUDE.md`, or both and can expose the CLI globally.
- Added `receiving-code-review`: verify review findings before implementation instead of applying feedback blindly.
- Added `converge`: audit the implementation against the specification and plan before finishing.
- Added living specifications so verified behavior survives across sessions as durable project context.
- Strengthened stack guidance for command verification, test boundaries, contract-first full-stack changes, and end-to-end testing.
