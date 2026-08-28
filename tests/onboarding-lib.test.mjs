// Tests for the onboarding skill's deterministic analysis library
// (template/plugins/superharness/skills/onboarding/scripts/onboarding-lib.cjs).
// Covers: engine detection (astgraph with mandatory fallback), incremental
// refresh planning, stale-document checking, and the CLI wrapper.
// Run: node --test tests/onboarding-lib.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LIB = path.join(REPO_ROOT, 'template', 'plugins', 'superharness', 'skills', 'onboarding', 'scripts', 'onboarding-lib.cjs');

const { detectEngine, planRefresh, staleCheck } = await import(pathToFileURL(LIB));

// ---------------------------------------------------------------- detectEngine

test('detectEngine picks astgraph when tools and index are both available', () => {
  const r = detectEngine({ astToolsAvailable: true, indexDbExists: true });
  assert.equal(r.engine, 'astgraph');
  assert.notEqual(r.suggestAstInit, true);
});

test('detectEngine falls back when astgraph tools are missing (Claude Code host / plugin not installed)', () => {
  const r = detectEngine({ astToolsAvailable: false, indexDbExists: false });
  assert.equal(r.engine, 'fallback');
  assert.notEqual(r.suggestAstInit, true, 'no plugin installed: nothing to suggest /ast init for');
});

test('tools present but index missing: fallback now, suggest /ast init, never block', () => {
  const r = detectEngine({ astToolsAvailable: true, indexDbExists: false });
  assert.equal(r.engine, 'fallback', 'must continue with the fallback engine immediately');
  assert.equal(r.suggestAstInit, true);
});

test('index present but tools missing still falls back (index without live tools is unusable)', () => {
  const r = detectEngine({ astToolsAvailable: false, indexDbExists: true });
  assert.equal(r.engine, 'fallback');
});

// ------------------------------------------------------------------ planRefresh

const cache = {
  gitHash: 'aaa111',
  modules: {
    lib: { files: ['lib/install.ps1', 'lib/install.sh'], stale: false },
    hooks: { files: ['template/plugins/superharness/hooks/session-start.ps1'], stale: false },
    ghost: { files: ['deleted/dir/*'], stale: false },
  },
};

test('planRefresh with same hash and no changed files re-analyzes nothing', () => {
  const r = planRefresh({ cache, headHash: 'aaa111', changedFiles: [] });
  assert.deepEqual(r.changed, []);
  assert.equal(r.headHash, 'aaa111');
});

test('planRefresh marks only modules owning a changed file', () => {
  const r = planRefresh({ cache, headHash: 'bbb222', changedFiles: ['lib/install.ps1'] });
  assert.deepEqual(r.changed, ['lib']);
});

test('planRefresh on hash change re-analyzes modules whose files changed per git diff', () => {
  const r = planRefresh({ cache, headHash: 'bbb222', changedFiles: ['template/plugins/superharness/hooks/session-start.ps1', 'lib/install.sh'] });
  assert.deepEqual(r.changed.sort(), ['hooks', 'lib']);
});

test('planRefresh without a cache plans a full initial pass', () => {
  const r = planRefresh({ cache: null, headHash: 'ccc333', changedFiles: [] });
  assert.equal(r.full, true);
  assert.equal(r.headHash, 'ccc333');
});

test('planRefresh reports unknown files as affecting no cached module', () => {
  const r = planRefresh({ cache, headHash: 'bbb222', changedFiles: ['README.md'] });
  assert.deepEqual(r.changed, []);
});

test('planRefresh matches file paths case-insensitively and normalizes backslashes', () => {
  const r = planRefresh({ cache, headHash: 'bbb222', changedFiles: ['LIB\\Install.ps1'] });
  assert.deepEqual(r.changed, ['lib']);
});

// ------------------------------------------------------------------- staleCheck

test('staleCheck flags modules whose doc file no longer exists', () => {
  const c = {
    modules: {
      ok: { doc: 'docs/onboarding/ok.md' },
      gone: { doc: 'docs/onboarding/gone.md' },
    },
  };
  const exists = new Set(['docs/onboarding/ok.md']);
  const r = staleCheck(c, { fileExists: (p) => exists.has(p) });
  assert.deepEqual(r.stale, ['gone']);
});

test('staleCheck flags flows whose anchor file was deleted', () => {
  const c = {
    modules: {},
    flows: { install: { anchors: ['lib/install.ps1#Install', 'lib/removed.sh#Go'] } },
  };
  const exists = new Set(['lib/install.ps1']);
  const r = staleCheck(c, { fileExists: (p) => exists.has(p) });
  assert.deepEqual(r.stale, ['flow:install']);
});

test('staleCheck flags flows whose generated doc was deleted', () => {
  const c = {
    modules: {},
    flows: { login: { doc: 'docs/onboarding/login-flow.md', anchors: ['lib/a.ps1#X'] } },
  };
  const exists = new Set(['lib/a.ps1']);
  const r = staleCheck(c, { fileExists: (p) => exists.has(p) });
  assert.deepEqual(r.stale, ['flow:login']);
});

test('staleCheck on an empty cache reports nothing stale', () => {
  const r = staleCheck({ modules: {}, flows: {} }, { fileExists: () => false });
  assert.deepEqual(r.stale, []);
});

// --------------------------------------------------------------------------- CLI

function cli(command, input) {
  return JSON.parse(
    execFileSync(process.execPath, [LIB, command], {
      input: JSON.stringify(input),
      encoding: 'utf-8',
    }),
  );
}

test('CLI engine command reads JSON on stdin and prints JSON result', () => {
  const r = cli('engine', { astToolsAvailable: true, indexDbExists: false });
  assert.equal(r.engine, 'fallback');
  assert.equal(r.suggestAstInit, true);
});

test('CLI refresh command plans from cache + head + changedFiles', () => {
  const r = cli('refresh', { cache, headHash: 'zzz', changedFiles: ['lib/install.ps1'] });
  assert.deepEqual(r.changed, ['lib']);
});

test('CLI stale command checks file existence against a path list', () => {
  const r = cli('stale', { cache: { modules: { m: { doc: 'x/missing.md' } }, flows: {} }, existingFiles: [] });
  assert.deepEqual(r.stale, ['m']);
});

test('CLI rejects an unknown command with non-zero exit', () => {
  assert.throws(() => cli('bogus', {}), (e) => e.status !== 0);
});
