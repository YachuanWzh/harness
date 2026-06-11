import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const SERVER = path.resolve('template/plugins/superharness/skills/brainstorm/scripts/server.cjs');

function tempSession() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'sh-brainstorm-'));
}

async function startServer(t, extraEnv = {}) {
  const session = tempSession();
  const child = spawn(process.execPath, [SERVER], {
    env: { ...process.env, SUPERHARNESS_SESSION_DIR: session, ...extraEnv },
    stdio: 'ignore',
  });
  t.after(() => { try { child.kill(); } catch {} });
  t.after(() => { try { fs.rmSync(session, { recursive: true, force: true }); } catch {} });
  const infoPath = path.join(session, 'state', 'server-info');
  for (let i = 0; i < 50; i++) {
    if (fs.existsSync(infoPath)) break;
    await new Promise(r => setTimeout(r, 100));
  }
  assert.ok(fs.existsSync(infoPath), 'server-info should appear within 5s');
  const info = JSON.parse(fs.readFileSync(infoPath, 'utf-8'));
  return { session, child, info };
}

test('writes server-info with port, url and pid', async t => {
  const { info, child } = await startServer(t);
  assert.equal(info.type, 'server-started');
  assert.ok(info.port > 0);
  assert.match(info.url, /^http:\/\/localhost:\d+$/);
  assert.equal(info.pid, child.pid);
  assert.ok(info.content_dir.endsWith('content'));
  assert.ok(info.state_dir.endsWith('state'));
});

test('GET / serves the mind map page', async t => {
  const { info } = await startServer(t);
  const res = await fetch(info.url + '/');
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.match(html, /MindmapLayout/);
});

test('GET /mindmap.json returns a default empty snapshot before any push', async t => {
  const { info } = await startServer(t);
  const snap = await (await fetch(info.url + '/mindmap.json')).json();
  assert.equal(snap.type, 'mindmap:snapshot');
  assert.equal(snap.rev, 0);
});

test('POST /event appends a JSONL line to state/events', async t => {
  const { info, session } = await startServer(t);
  const evt = { type: 'node:click', id: 'q1-a', label: 'JWT', kind: 'option', timestamp: 1760000000 };
  const res = await fetch(info.url + '/event', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(evt),
  });
  assert.equal(res.status, 204);
  const lines = fs.readFileSync(path.join(session, 'state', 'events'), 'utf-8').trim().split('\n');
  assert.equal(lines.length, 1);
  assert.deepEqual(JSON.parse(lines[0]), evt);
});

test('POST /event rejects invalid JSON with 400', async t => {
  const { info } = await startServer(t);
  const res = await fetch(info.url + '/event', { method: 'POST', body: 'not json' });
  assert.equal(res.status, 400);
});
