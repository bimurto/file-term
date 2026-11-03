// Post-build checks on dist/: in-app Help anchors exist, internal links resolve, ids are unique.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dist = resolve(here, '../dist');
const commandsSource = resolve(here, '../../docs/user-guide/commands.md');
const problems = [];

const htmlFiles = (dir) =>
  readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return htmlFiles(path);
    return name.endsWith('.html') ? [path] : [];
  });

const pages = new Map(); // URL path -> { html, ids }
for (const file of htmlFiles(dist)) {
  const html = readFileSync(file, 'utf8');
  const url = '/' + relative(dist, file).replace(/index\.html$/, '').replace(/\\/g, '/');
  const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]);
  pages.set(url, { html, ids: new Set(ids) });
  const seen = new Set();
  for (const id of ids) {
    if (seen.has(id)) problems.push(`${url}: duplicate id "${id}"`);
    seen.add(id);
  }
  if (/forklift/i.test(html)) problems.push(`${url}: mentions another product's name`);
}

// Every anchor the app's Help menu links to must exist on the command reference page.
const anchors = [...readFileSync(commandsSource, 'utf8').matchAll(/<a id="([^"]+)"><\/a>/g)].map((m) => m[1]);
const commands = pages.get('/docs/commands/');
if (!commands) problems.push('/docs/commands/ was not built');
else for (const id of anchors) if (!commands.ids.has(id)) problems.push(`/docs/commands/: missing anchor #${id}`);

// Internal links must point at a built page, file or anchor.
for (const [url, { html }] of pages) {
  for (const [, href] of html.matchAll(/\shref="([^"]+)"/g)) {
    if (/^(https?:|mailto:|data:|#$)/.test(href) || href.startsWith('//')) continue;
    const target = new URL(href.replace(/&amp;/g, '&'), `https://site${url}`);
    const path = decodeURIComponent(target.pathname);
    const page = pages.get(path);
    if (!page && !existsSync(join(dist, path))) {
      problems.push(`${url}: broken link ${href}`);
      continue;
    }
    const id = decodeURIComponent(target.hash.slice(1));
    if (id && page && !page.ids.has(id)) problems.push(`${url}: link ${href} has no target #${id}`);
  }
}

if (problems.length) {
  console.error(`check-site: ${problems.length} problem(s)\n` + problems.map((p) => `  - ${p}`).join('\n'));
  process.exit(1);
}
console.log(`check-site: ${pages.size} pages, ${anchors.length} Help anchors, all links resolve`);
