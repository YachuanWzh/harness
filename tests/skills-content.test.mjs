// Content assertions for the 1.0.4 skill/template additions:
//   - receiving-code-review skill (ported from superpowers, adapted)
//   - converge skill (spec-convergence audit + living-spec sink)
//   - analyze findings gate in writing-plans + go
//   - stack template upgrades (command verification, mocking boundaries, key libraries)
// Run: node --test tests/skills-content.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const TEMPLATE = path.join(REPO_ROOT, 'template', 'plugins', 'superharness');

const read = (...parts) => fs.readFileSync(path.join(TEMPLATE, ...parts), 'utf8');
const exists = (...parts) => fs.existsSync(path.join(TEMPLATE, ...parts));

function assertFrontmatter(doc, name) {
  const m = doc.match(/^---\n([\s\S]*?)\n---/);
  assert.ok(m, `${name}: SKILL.md must start with a YAML frontmatter block`);
  assert.ok(m[1].includes(`name: ${name}`), `${name}: frontmatter name must be "${name}"`);
  assert.match(m[1], /description: Use when /, `${name}: description must start with "Use when "`);
}

// ---------------------------------------------------------------- receiving-code-review

test('receiving-code-review skill ships and enforces verify-before-implementing', () => {
  assert.ok(exists('skills', 'receiving-code-review', 'SKILL.md'), 'skills/receiving-code-review/SKILL.md missing');
  const doc = read('skills', 'receiving-code-review', 'SKILL.md');
  assertFrontmatter(doc, 'receiving-code-review');
  assert.match(doc, /verify before implementing/i);
  assert.match(doc, /push back/i);
  assert.match(doc, /absolutely right/, 'must explicitly ban the performative-agreement example');
  assert.match(doc, /YAGNI/, 'must keep the YAGNI check for suggested features');
  assert.ok(!doc.includes('superpowers:'), 'ported skill must not reference the superpowers namespace');
});

// ---------------------------------------------------------------- converge

test('converge skill audits implementation against spec and sinks a living spec', () => {
  assert.ok(exists('skills', 'converge', 'SKILL.md'), 'skills/converge/SKILL.md missing');
  const doc = read('skills', 'converge', 'SKILL.md');
  assertFrontmatter(doc, 'converge');
  assert.match(doc, /CONVERGED/, 'must define a converged verdict');
  assert.match(doc, /done\/partial\/missing\/divergent|partial.*missing.*divergent/s, 'must classify each requirement');
  assert.match(doc, /append/i, 'must append remaining work as new tasks instead of silently passing');
  assert.match(doc, /<state-root>\/superharness\/specs\//, 'must sink the living spec under the host state root');
  assert.match(doc, /retry|cap|exhaust/i, 'must bound the converge loop (no infinite loops)');
});

// ---------------------------------------------------------------- analyze gate

test('writing-plans self-review produces a mandatory Analysis Findings block', () => {
  const doc = read('skills', 'writing-plans', 'SKILL.md');
  assert.match(doc, /Analysis Findings/, 'self-review must emit a named findings block');
  assert.match(doc, /coverage matrix/i, 'findings must include a requirement→task coverage matrix');
  assert.match(doc, /contradiction/i);
  assert.match(doc, /ambigu/i);
});

test('go gates Phase 2 on the findings block and runs converge before finishing', () => {
  const doc = read('skills', 'go', 'SKILL.md');
  assert.match(doc, /Analysis Findings/, 'go must require the findings block from writing-plans');
  assert.match(doc, /Phase 4\.5/, 'go must run convergence after review, before finishing');
  assert.match(doc, /superharness:converge/, 'go must reference the converge skill');
  assert.match(doc, /converge:pass|converge:gap/, 'go must record converge trace events');
  assert.match(doc, /receiving-code-review/, 'go Phase 4 must handle feedback via receiving-code-review');
});

// ---------------------------------------------------------------- HARNESS bootstrap

test('HARNESS.md lists the two new skills', () => {
  const doc = read('HARNESS.md');
  assert.match(doc, /superharness:receiving-code-review/);
  assert.match(doc, /superharness:converge/);
});

// ---------------------------------------------------------------- stack templates

const STACK_DOCS = ['frontend-react.md', 'frontend-vue.md', 'backend-python.md', 'backend-node.md', 'backend-java.md'];

for (const file of STACK_DOCS) {
  test(`stack doc ${file} gains command verification, mocking boundaries, key libraries`, () => {
    const doc = read('stacks', file);
    assert.match(doc, /## Verify commands against the project/, `${file}: hardcoded commands must be project-verified`);
    assert.match(doc, /## Test boundaries & mocking/, `${file}: needs stack-specific mock guidance`);
    assert.match(doc, /## Key libraries/, `${file}: needs anchored key-library list`);
  });
}

test('fullstack seam strengthens contract-first, versioning, and e2e guidance', () => {
  const doc = read('stacks', 'fullstack-seam.md');
  assert.match(doc, /contract-first|OpenAPI/i, 'seam must prescribe contract-first evolution');
  assert.match(doc, /versioning|idempot/i, 'seam must cover API versioning/idempotency');
  assert.match(doc, /Playwright|Cypress/, 'seam must recommend a concrete e2e tool');
  assert.match(doc, /contract test/i, 'seam must order contract tests first in TDD terms');
});
