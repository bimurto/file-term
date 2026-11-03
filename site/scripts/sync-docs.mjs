// Copies docs/user-guide into Starlight's content folder so the guide has one source.
// Adds frontmatter, drops the top heading and points chapter links at site pages.
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const guideDir = resolve(here, '../../docs/user-guide');
export const outDir = resolve(here, '../src/content/docs/docs');
const editBase = 'https://github.com/bimurto/file-term/edit/main/docs/user-guide/';

export function slugFor(file) {
  if (file === 'README.md') return '';
  return file.replace(/\.md$/, '').replace(/^\d+-/, '');
}

function orderFor(file) {
  if (file === 'README.md') return 0;
  if (file === 'commands.md') return 14;
  return Number(file.match(/^(\d+)-/)?.[1] ?? 99);
}

const pagePath = (file) => `/docs/${slugFor(file) ? `${slugFor(file)}/` : ''}`;

export function transform(file, source, files) {
  const heading = source.match(/^# (.+)\n/);
  if (!heading) throw new Error(`${file}: the page needs a top heading`);
  const title = heading[1].replace(/^\d+ /, '').trim();
  let body = source.slice(heading[0].length).replace(/^\s*\n/, '');

  body = body.replace(/\]\(([^)\s]+?\.md)(#[^)\s]*)?\)/g, (_, target, anchor = '') => {
    if (!files.includes(target)) throw new Error(`${file}: link to ${target}, which isn't in the guide`);
    return `](${pagePath(target)}${anchor})`;
  });
  if (/\.md[)#]/.test(body)) throw new Error(`${file}: a link to a markdown file was left unconverted`);

  const firstParagraph = body.split(/\n\s*\n/).find((block) => block.trim() && !/^[#|<-]/.test(block.trim())) ?? '';
  const description = firstParagraph.replace(/\s+/g, ' ').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').trim();

  const sidebar = [`  order: ${orderFor(file)}`];
  if (file === 'commands.md') sidebar.push(`  label: ${JSON.stringify('Command reference')}`);
  if (file === 'README.md') sidebar.push(`  label: ${JSON.stringify('Introduction')}`);

  const frontmatter = [
    '---',
    `title: ${JSON.stringify(title)}`,
    `description: ${JSON.stringify(description)}`,
    'sidebar:',
    ...sidebar,
    `editUrl: ${JSON.stringify(editBase + file)}`,
    '---',
    '',
  ].join('\n');
  return frontmatter + body;
}

export function syncDocs() {
  const files = readdirSync(guideDir).filter((name) => name.endsWith('.md')).sort();
  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });
  for (const file of files) {
    const out = transform(file, readFileSync(join(guideDir, file), 'utf8'), files);
    writeFileSync(join(outDir, `${slugFor(file) || 'index'}.md`), out);
  }
  return files.length;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  console.log(`Synced ${syncDocs()} guide pages into ${outDir}`);
}
