// Tests for the flavor-code plugin (template/plugins/superharness/plugin/).
// Simulates flavor-code's PluginHost + HookBus semantics:
//   - manifest hook names must be valid HOOK_EVENT_NAMES
//   - every declared hook must be registered by activate() (and vice versa)
//   - every hook result must be a valid HookDecision ({decision, additionalContext?})
// Run: node --test tests/flavor-plugin.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const TEMPLATE = path.join(REPO_ROOT, 'template', 'plugins', 'superharness');

// flavor-code's HOOK_EVENT_NAMES (src/hooks/types.ts) — keep in sync manually.
const HOOK_EVENT_NAMES = [
  'SessionStart', 'UserPromptSubmit', 'Stop', 'SessionEnd',
  'BeforePlan', 'AfterPlan', 'SubagentStart', 'SubagentStop',
  'BeforeModelCall', 'AfterModelCall', 'PreToolUse', 'PermissionRequest',
  'PostToolUse', 'PostToolUseFailure', 'PreCompact', 'PostCompact',
  'PluginLoad', 'PluginUnload', 'Notification',
];

const DECISIONS = ['allow', 'deny', 'ask'];

function assertHookDecision(decision) {
  assert.ok(decision !== null && typeof decision === 'object', 'decision must be an object');
  assert.ok(DECISIONS.includes(decision.decision), `decision.decision must be allow/deny/ask, got ${decision.decision}`);
  if (decision.reason !== undefined) assert.equal(typeof decision.reason, 'string');
  if (decision.additionalContext !== undefined) assert.equal(typeof decision.additionalContext, 'string');
}

// Simulate the installed flavor plugin layout (.flavor/plugins/superharness/)
// the same way lib/install.ps1 and lib/install.sh do.
function installFlavorPlugin(stackDoc) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sh-flavor-plugin-'));
  fs.copyFileSync(path.join(TEMPLATE, 'plugin', 'flavor-plugin.json'), path.join(root, 'flavor-plugin.json'));
  fs.copyFileSync(path.join(TEMPLATE, 'plugin', 'index.js'), path.join(root, 'index.js'));
  fs.copyFileSync(path.join(TEMPLATE, 'HARNESS.md'), path.join(root, 'HARNESS.md'));
  if (stackDoc) fs.copyFileSync(path.join(TEMPLATE, 'stacks', stackDoc), path.join(root, 'STACK.md'));
  fs.cpSync(path.join(TEMPLATE, 'skills'), path.join(root, 'skills'), { recursive: true });
  return root;
}

// Fake PluginContext mirroring flavor-code's host.ts registration rules:
// contributions must be declared in the manifest; hooks track declared names.
function createFakeHost(pluginRoot) {
  const manifest = JSON.parse(fs.readFileSync(path.join(pluginRoot, 'flavor-plugin.json'), 'utf8'));
  const declared = {
    hook: new Set(manifest.contributes.hooks.map(h => h.name)),
    skillRoot: new Map(manifest.contributes.skillRoots.map(s => [s.name, s.path])),
  };
  const registered = { hook: new Map(), skillRoot: new Map() };
  const context = {
    signal: new AbortController().signal,
    config: {},
    logger: { debug() {}, info() {}, warn() {}, error() {} },
    registerHook(name, handler, options) {
      if (!declared.hook.has(name)) throw new Error(`hook contribution "${name}" was not declared`);
      if (registered.hook.has(name)) throw new Error(`hook contribution conflict for "${name}"`);
      registered.hook.set(name, { handler, options });
      return () => registered.hook.delete(name);
    },
    registerSkillRoot(name, rootPath) {
      const declaredPath = declared.skillRoot.get(name);
      if (declaredPath === undefined) throw new Error(`skillRoot contribution "${name}" was not declared`);
      assert.equal(path.resolve(pluginRoot, rootPath), path.resolve(pluginRoot, declaredPath),
        'registered skill root must match its declaration');
      registered.skillRoot.set(name, rootPath);
      return () => registered.skillRoot.delete(name);
    },
  };
  return { manifest, declared, registered, context };
}

async function activateInstalled(pluginRoot) {
  const host = createFakeHost(pluginRoot);
  const mod = await import(pathToFileURL(path.join(pluginRoot, 'index.js')).href);
  const deactivate = await mod.activate(host.context);
  return { host, mod, deactivate };
}

test('manifest declares exactly the three superharness hooks with valid names', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(TEMPLATE, 'plugin', 'flavor-plugin.json'), 'utf8'));
  const names = manifest.contributes.hooks.map(h => h.name);
  assert.deepEqual([...names].sort(), ['SessionStart', 'Stop', 'UserPromptSubmit']);
  for (const name of names) assert.ok(HOOK_EVENT_NAMES.includes(name), `${name} must be a flavor-code HOOK_EVENT_NAME`);
});

test('activate() registers every declared hook and the skill root (host consistency)', async () => {
  const root = installFlavorPlugin();
  try {
    const { host, deactivate } = await activateInstalled(root);
    assert.deepEqual([...host.registered.hook.keys()].sort(), ['SessionStart', 'Stop', 'UserPromptSubmit'],
      'every declared hook must be registered (host rejects partial registration)');
    assert.equal(host.registered.skillRoot.get('superharness'), './skills');
    for (const { options } of host.registered.hook.values()) {
      assert.equal(options?.failurePolicy, 'allow', 'superharness hooks must never block (failurePolicy=allow)');
    }
    deactivate();
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('SessionStart returns a HookDecision injecting HARNESS.md as additionalContext', async () => {
  const root = installFlavorPlugin();
  try {
    const { host } = await activateInstalled(root);
    const { handler } = host.registered.hook.get('SessionStart');
    const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'sh-flavor-ws-'));
    try {
      const decision = await handler({ version: 1, type: 'SessionStart', payload: { workspace } }, new AbortController().signal);
      assertHookDecision(decision);
      assert.equal(decision.decision, 'allow');
      assert.match(decision.additionalContext, /EXTREMELY_IMPORTANT/);
      assert.match(decision.additionalContext, /superharness/i);
      assert.ok(!decision.additionalContext.includes('tech stack'), 'no stack block without STACK.md');
    } finally {
      fs.rmSync(workspace, { recursive: true, force: true });
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('SessionStart appends STACK.md guidance when present', async () => {
  const root = installFlavorPlugin('frontend-vue.md');
  try {
    const { host } = await activateInstalled(root);
    const { handler } = host.registered.hook.get('SessionStart');
    const decision = await handler({ version: 1, type: 'SessionStart', payload: { workspace: root } }, new AbortController().signal);
    assertHookDecision(decision);
    assert.match(decision.additionalContext, /Vue/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('UserPromptSubmit auto-bootstraps ralph state on a /go invocation (workspace from SessionStart cache)', async () => {
  const root = installFlavorPlugin();
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'sh-flavor-ws-'));
  try {
    const { host } = await activateInstalled(root);
    const signal = new AbortController().signal;
    const sessionStart = host.registered.hook.get('SessionStart').handler;
    const submit = host.registered.hook.get('UserPromptSubmit').handler;
    const stop = host.registered.hook.get('Stop').handler;

    assertHookDecision(await sessionStart({ version: 1, type: 'SessionStart', payload: { workspace } }, signal));

    // a go invocation bootstraps the ralph files under the cached workspace
    const decision = await submit({ version: 1, type: 'UserPromptSubmit', payload: { prompt: '/go fix the widget' } }, signal);
    assertHookDecision(decision);
    assert.equal(decision.decision, 'allow');
    const ralph = path.join(workspace, '.claude', 'superharness', 'ralph');
    assert.ok(fs.existsSync(path.join(ralph, '.current-task')), '.current-task created');
    assert.match(fs.readFileSync(path.join(ralph, '.current-task'), 'utf8'), /^\d{4}-\d{2}-\d{2}-fix-the-widget$/);
    assert.ok(fs.existsSync(path.join(ralph, 'task.json')), 'task.json created');
    assert.match(fs.readFileSync(path.join(ralph, 'trace.jsonl'), 'utf8'), /"event":"task:started"/);
    assert.ok(fs.existsSync(path.join(ralph, '.pending-prompt.json')), 'pending prompt stashed');

    // Stop records the round heartbeat and consumes the pending prompt
    assertHookDecision(await stop({ version: 1, type: 'Stop', payload: { outcome: 'completed' } }, signal));
    const trace = fs.readFileSync(path.join(ralph, 'trace.jsonl'), 'utf8').trim().split('\n');
    const last = JSON.parse(trace[trace.length - 1]);
    assert.equal(last.event, 'round');
    assert.equal(last.detail, '/go fix the widget');
    assert.ok(!fs.existsSync(path.join(ralph, '.pending-prompt.json')), 'pending prompt consumed');

    // a normal prompt does not repoint the task but still stashes the round
    await submit({ version: 1, type: 'UserPromptSubmit', payload: { prompt: 'what now?' } }, signal);
    assert.match(fs.readFileSync(path.join(ralph, '.current-task'), 'utf8'), /fix-the-widget$/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
    fs.rmSync(workspace, { recursive: true, force: true });
  }
});

test('Stop without an active task is a no-op allow; hooks never throw on malformed events', async () => {
  const root = installFlavorPlugin();
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'sh-flavor-ws-'));
  try {
    const { host } = await activateInstalled(root);
    const signal = new AbortController().signal;
    await host.registered.hook.get('SessionStart').handler({ version: 1, type: 'SessionStart', payload: { workspace } }, signal);

    const stop = host.registered.hook.get('Stop').handler;
    const decision = await stop({ version: 1, type: 'Stop', payload: {} }, signal);
    assertHookDecision(decision);
    assert.ok(!fs.existsSync(path.join(workspace, '.claude', 'superharness', 'ralph', 'trace.jsonl')),
      'no trace without an active task');

    // malformed events must not throw (guards return allow)
    for (const handler of host.registered.hook.values()) {
      assertHookDecision(await handler.handler(undefined, signal));
      assertHookDecision(await handler.handler({ version: 1, type: 'UserPromptSubmit', payload: { prompt: 42 } }, signal));
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
    fs.rmSync(workspace, { recursive: true, force: true });
  }
});
