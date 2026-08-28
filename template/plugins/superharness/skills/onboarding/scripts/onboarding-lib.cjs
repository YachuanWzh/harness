// Superharness onboarding skill — deterministic analysis helpers.
// The agent (SKILL.md) drives the semantic deep dives; this library owns the
// mechanical decisions so they are testable and stable across hosts:
//   engine   — pick astgraph vs. fallback (fallback is mandatory-capable)
//   refresh  — what actually needs re-analysis given cache + changed files
//   stale    — cached docs/anchors that no longer match the working tree
//
// CLI: node onboarding-lib.cjs <engine|refresh|stale>   (reads JSON on stdin)

'use strict';

const STALE_PREFIX = 'flow:';

function normalizeRel(p) {
  return String(p || '').replace(/\\/g, '/').replace(/^\.\//, '').toLowerCase();
}

// Double detection (spec): ast_* tool availability AND .flavor/astgraph/index.db
// existence. Tools without an index never block the run: fall back immediately
// and merely suggest `/ast init` for future precision.
function detectEngine({ astToolsAvailable = false, indexDbExists = false } = {}) {
  if (astToolsAvailable && indexDbExists) return { engine: 'astgraph' };
  const result = { engine: 'fallback' };
  if (astToolsAvailable && !indexDbExists) result.suggestAstInit = true;
  return result;
}

// Module membership: a cached module owns the file when its recorded file list
// contains it (prefix rules like "dir/*" match by directory).
function moduleOwnsFile(module, file) {
  const f = normalizeRel(file);
  return (module.files || []).some((owned) => {
    const o = normalizeRel(owned);
    if (o.endsWith('/*')) return f.startsWith(o.slice(0, -1));
    if (o.endsWith('/')) return f.startsWith(o);
    return f === o;
  });
}

// cache: { gitHash, modules: { id: { files: [...] } } } | null
// changedFiles: workspace-relative paths (git diff --name-only HEAD <hash> etc.)
function planRefresh({ cache, headHash, changedFiles = [] } = {}) {
  if (!cache || !cache.modules) {
    return { full: true, headHash, changed: [] };
  }
  if (cache.gitHash === headHash && changedFiles.length === 0) {
    return { full: false, headHash, changed: [] };
  }
  const changed = new Set();
  for (const file of changedFiles) {
    for (const [id, module] of Object.entries(cache.modules)) {
      if (moduleOwnsFile(module, file)) changed.add(id);
    }
  }
  return { full: false, headHash, changed: [...changed] };
}

// Walk cached docs and flow anchors; anything the fileExists probe rejects is
// reported as stale (flows are prefixed with "flow:" to keep ids unique).
function staleCheck(cache, { fileExists } = {}) {
  const stale = [];
  const exists = typeof fileExists === 'function' ? fileExists : () => true;
  const modules = (cache && cache.modules) || {};
  const flows = (cache && cache.flows) || {};
  for (const [id, m] of Object.entries(modules)) {
    if (m && typeof m.doc === 'string' && !exists(m.doc)) stale.push(id);
  }
  for (const [id, f] of Object.entries(flows)) {
    if (f && typeof f.doc === 'string' && !exists(f.doc)) { stale.push(STALE_PREFIX + id); continue; }
    const anchors = (f && f.anchors) || [];
    const broken = anchors.some((a) => {
      const file = String(a).split('#')[0];
      return file.length > 0 && !exists(file);
    });
    if (broken) stale.push(STALE_PREFIX + id);
  }
  return { stale };
}

function readStdin() {
  return new Promise((resolve, reject) => {
    let text = '';
    process.stdin.on('data', (chunk) => { text += chunk; });
    process.stdin.on('end', () => resolve(text));
    process.stdin.on('error', reject);
  });
}

const COMMANDS = {
  engine: detectEngine,
  refresh: planRefresh,
  stale: (input) => staleCheck(input.cache, { fileExists: (p) => new Set((input.existingFiles || []).map(normalizeRel)).has(normalizeRel(p)) }),
};

if (require.main === module) {
  (async () => {
    const command = process.argv[2];
    const run = COMMANDS[command];
    if (run === undefined) {
      process.stderr.write(`unknown command "${command ?? ''}"; expected one of: ${Object.keys(COMMANDS).join(', ')}\n`);
      process.exit(2);
      return;
    }
    const input = JSON.parse((await readStdin()) || '{}');
    process.stdout.write(JSON.stringify(run(input)));
  })().catch((err) => {
    process.stderr.write(`${err.message}\n`);
    process.exit(1);
  });
}

module.exports = { detectEngine, planRefresh, staleCheck, normalizeRel };
