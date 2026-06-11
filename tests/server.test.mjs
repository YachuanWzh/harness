import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';

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

// Minimal WebSocket client: handshake + unmasked server frame parsing (len < 64KB).
function wsConnect(port) {
  return new Promise((resolve, reject) => {
    const socket = net.connect(port, '127.0.0.1');
    const messages = [];
    const waiters = [];
    let handshakeDone = false;
    let buf = Buffer.alloc(0);
    socket.on('error', reject);
    socket.on('connect', () => {
      socket.write(
        'GET / HTTP/1.1\r\nHost: 127.0.0.1:' + port + '\r\n' +
        'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
        'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n');
    });
    socket.on('data', chunk => {
      buf = Buffer.concat([buf, chunk]);
      if (!handshakeDone) {
        const end = buf.indexOf('\r\n\r\n');
        if (end === -1) return;
        handshakeDone = true;
        buf = buf.slice(end + 4);
        resolve({
          socket,
          nextMessage(timeoutMs = 3000) {
            return new Promise((res, rej) => {
              if (messages.length) return res(messages.shift());
              const timer = setTimeout(() => rej(new Error('ws message timeout')), timeoutMs);
              waiters.push(msg => { clearTimeout(timer); res(msg); });
            });
          },
        });
      }
      while (buf.length >= 2) {
        let len = buf[1] & 0x7f;
        let offset = 2;
        if (len === 126) {
          if (buf.length < 4) return;
          len = buf.readUInt16BE(2);
          offset = 4;
        }
        if (buf.length < offset + len) return;
        const payload = buf.slice(offset, offset + len).toString('utf-8');
        buf = buf.slice(offset + len);
        if (waiters.length) waiters.shift()(payload);
        else messages.push(payload);
      }
    });
  });
}

test('WS client receives the latest snapshot on connect', async t => {
  const { info } = await startServer(t);
  const ws = await wsConnect(info.port);
  t.after(() => ws.socket.destroy());
  const snap = JSON.parse(await ws.nextMessage());
  assert.equal(snap.type, 'mindmap:snapshot');
  assert.equal(snap.rev, 0);
});

test('writing mindmap.json pushes the new snapshot and clears events', async t => {
  const { info, session } = await startServer(t);
  const ws = await wsConnect(info.port);
  t.after(() => ws.socket.destroy());
  await ws.nextMessage(); // initial snapshot

  // stale event that must be cleared on next push
  fs.writeFileSync(path.join(session, 'state', 'events'), '{"type":"node:click","id":"old"}\n');

  const snapshot = {
    type: 'mindmap:snapshot', rev: 1, topic: '测试', status: 'exploring',
    root: { id: 'root', label: '测试', kind: 'topic' },
  };
  fs.writeFileSync(path.join(session, 'content', 'mindmap.json'), JSON.stringify(snapshot));

  const pushed = JSON.parse(await ws.nextMessage());
  assert.equal(pushed.rev, 1);
  assert.equal(pushed.topic, '测试');
  assert.equal(fs.readFileSync(path.join(session, 'state', 'events'), 'utf-8'), '');
});

test('idle server exits and writes server-stopped', async t => {
  const { session, child } = await startServer(t, { SUPERHARNESS_IDLE_TIMEOUT_MS: '300' });
  const exited = new Promise(resolve => child.on('exit', resolve));
  await exited;
  assert.ok(fs.existsSync(path.join(session, 'state', 'server-stopped')), 'server-stopped marker written');
  assert.ok(!fs.existsSync(path.join(session, 'state', 'server-info')), 'server-info removed');
});
