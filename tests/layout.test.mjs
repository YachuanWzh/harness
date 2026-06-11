import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { layout, leafCount } = require('../template/plugins/superharness/skills/brainstorm/scripts/layout.js');

const tree = {
  id: 'root', label: '主题', kind: 'topic',
  children: [
    { id: 'q1', label: '问题1', kind: 'question', children: [
      { id: 'q1-a', label: 'A', kind: 'option' },
      { id: 'q1-b', label: 'B', kind: 'option' },
    ]},
    { id: 'q2', label: '问题2', kind: 'question', children: [
      { id: 'q2-a', label: 'C', kind: 'option' },
    ]},
    { id: 'd1', label: '决策1', kind: 'decision' },
  ],
};

test('leafCount counts leaves', () => {
  assert.equal(leafCount(tree), 4); // q1-a, q1-b, q2-a, d1
  assert.equal(leafCount({ id: 'x', label: 'x' }), 1);
});

test('root sits at the origin', () => {
  const { nodes } = layout(tree);
  const root = nodes.find(n => n.id === 'root');
  assert.equal(root.x, 0);
  assert.equal(root.y, 0);
  assert.equal(root.side, 0);
});

test('all input nodes appear exactly once with links to parents', () => {
  const { nodes, links } = layout(tree);
  const ids = nodes.map(n => n.id).sort();
  assert.deepEqual(ids, ['d1', 'q1', 'q1-a', 'q1-b', 'q2', 'q2-a', 'root']);
  assert.deepEqual(
    links.map(l => `${l.from}->${l.to}`).sort(),
    ['q1->q1-a', 'q1->q1-b', 'q2->q2-a', 'root->d1', 'root->q1', 'root->q2'],
  );
});

test('root children are split across both sides', () => {
  const { nodes } = layout(tree);
  const sides = new Set(nodes.filter(n => ['q1', 'q2', 'd1'].includes(n.id)).map(n => n.side));
  assert.ok(sides.has(1) && sides.has(-1), 'expected children on both sides');
});

test('children inherit their branch side and move outward', () => {
  const { nodes } = layout(tree);
  const q1 = nodes.find(n => n.id === 'q1');
  const q1a = nodes.find(n => n.id === 'q1-a');
  assert.equal(q1a.side, q1.side);
  assert.ok(Math.abs(q1a.x) > Math.abs(q1.x), 'child is further from the root');
});

test('same column nodes never overlap vertically', () => {
  const { nodes } = layout(tree);
  const cols = {};
  for (const n of nodes) (cols[`${n.side}:${n.x}`] ||= []).push(n.y);
  for (const ys of Object.values(cols)) {
    const sorted = [...ys].sort((a, b) => a - b);
    for (let i = 1; i < sorted.length; i++) {
      assert.ok(sorted[i] - sorted[i - 1] >= 36, `vertical gap too small: ${sorted[i] - sorted[i - 1]}`);
    }
  }
});

test('layout is deterministic', () => {
  assert.deepEqual(layout(tree), layout(tree));
});

test('empty root yields empty layout', () => {
  assert.deepEqual(layout(null), { nodes: [], links: [] });
});
