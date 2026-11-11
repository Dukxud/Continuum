import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { checkDocumentation } from '../scripts/check-docs.mjs';

function fixture(t, content) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'continuum-doc-links-'));
  t.after(() => {
    assert.equal(path.dirname(root), path.resolve(os.tmpdir()));
    assert.ok(path.basename(root).startsWith('continuum-doc-links-'));
    fs.rmSync(root, { recursive: true, force: true });
  });
  for (const [name, text] of Object.entries(content)) {
    const file = path.join(root, name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  }
  return checkDocumentation(root, Object.keys(content));
}

test('Markdown check resolves directories, encoded paths, and repeated headings', (t) => {
  const result = fixture(t, {
    'README.md':
      '[Guide](docs/Guide%20One.md#build--run-1)\n[Docs](docs/)\n![View](docs/view.png)\n',
    'docs/Guide One.md': '# Build — run\n# Build — run\n[Home](../README.md)\n',
    'docs/view.png': '',
  });
  assert.equal(result.links, 4);
  assert.deepEqual(result.errors, []);
});

test('Markdown check detects casing, missing headings, and paths outside the repo', (t) => {
  const result = fixture(t, {
    'README.md': '[Wrong case](guide.md)\n[Absent](Guide.md#absent)\n[Outside](../secret.md)\n',
    'Guide.md': '# Setup\n',
  });
  assert.equal(result.errors.length, 3);
});

test('Markdown check ignores code examples and external links', (t) => {
  const result = fixture(t, {
    'README.md': '```md\n[Example](missing.md)\n```\n[External](https://example.com)\n',
  });
  assert.equal(result.links, 0);
  assert.deepEqual(result.errors, []);
});
