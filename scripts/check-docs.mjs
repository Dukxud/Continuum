import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import MarkdownIt from 'markdown-it';

const markdown = new MarkdownIt({ html: true });

function headingAnchors(content) {
  const tokens = markdown.parse(content, {});
  const anchors = new Set();
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].type !== 'heading_open') continue;
    const text = tokens[i + 1].children
      .filter((token) => token.type === 'text' || token.type === 'code_inline')
      .map((token) => token.content)
      .join('');
    const base = text
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s_-]/gu, '')
      .replace(/\s/g, '-');
    let anchor = base;
    for (let suffix = 1; anchors.has(anchor); suffix++) anchor = `${base}-${suffix}`;
    anchors.add(anchor);
  }
  return anchors;
}

/** Check tracked Markdown links against repository paths and GitHub heading IDs. */
export function checkDocumentation(root, files) {
  const tracked = new Set(files);
  const documents = files.filter((file) => file.endsWith('.md'));
  const anchors = new Map();
  const errors = [];
  let links = 0;

  function checkLink(file, url) {
    if (!url || /^[a-z][a-z0-9+.-]*:/i.test(url) || url.startsWith('//')) return;
    links++;
    let destination;
    try {
      destination = decodeURIComponent(url);
    } catch {
      errors.push(`${file}: invalid URL encoding in ${url}`);
      return;
    }
    const [name, anchor] = destination.split('#');
    const target = name
      ? path.posix.normalize(path.posix.join(path.posix.dirname(file), name))
      : file;
    const directory = files.some((entry) => entry.startsWith(`${target.replace(/\/$/, '')}/`));
    if (target.startsWith('../') || (!tracked.has(target) && !directory)) {
      errors.push(`${file}: missing or incorrectly cased path ${url}`);
      return;
    }
    if (anchor && target.endsWith('.md')) {
      if (!anchors.has(target)) {
        anchors.set(target, headingAnchors(fs.readFileSync(path.join(root, target), 'utf8')));
      }
      if (!anchors.get(target).has(anchor)) errors.push(`${file}: missing heading ${url}`);
    }
  }

  for (const file of documents) {
    const visit = (tokens) => {
      for (const token of tokens) {
        if (token.type === 'link_open') checkLink(file, token.attrGet('href'));
        if (token.type === 'image') checkLink(file, token.attrGet('src'));
        if (token.children) visit(token.children);
      }
    };
    visit(markdown.parse(fs.readFileSync(path.join(root, file), 'utf8'), {}));
  }
  return { documents: documents.length, links, errors };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
  const files = execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8' })
    .split('\0')
    .filter(Boolean);
  const result = checkDocumentation(root, files);
  for (const error of result.errors) console.error(error);
  console.log(
    `${result.documents} Markdown files, ${result.links} relative links, ${result.errors.length} errors.`,
  );
  process.exitCode = result.errors.length ? 1 : 0;
}
