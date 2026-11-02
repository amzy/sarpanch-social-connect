const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('Firestore rules isolate user documents and deny client access to social credentials', () => {
  const rules = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');
  assert.match(rules, /allow read: if owns\(uid\)/);
  assert.match(rules, /match \/private\/{document=\*\*}\s*\{\s*allow read, write: if false;/);
});

test('AI and publishing triggers use the required queue status names', () => {
  const source = fs.readFileSync(path.join(__dirname, '../src/index.ts'), 'utf8');
  for (const status of ['pending_ai', 'pending_approval', 'approved_to_publish', 'published', 'failed']) {
    assert.ok(source.includes(status), `missing status ${status}`);
  }
});

test('only the approved transition is dispatched to social channels', () => {
  const source = fs.readFileSync(path.join(__dirname, '../src/index.ts'), 'utf8');
  assert.match(source, /before\.status === 'approved_to_publish' \|\| after\.status !== 'approved_to_publish'/);
});
