import assert from 'node:assert/strict';
import { test } from 'node:test';
import { slugFor, transform } from './sync-docs.mjs';

const files = ['README.md', '01-navigation-and-panes.md', '13-limits-and-known-gaps.md', 'commands.md'];

test('slugs drop the chapter number', () => {
  assert.equal(slugFor('README.md'), '');
  assert.equal(slugFor('01-navigation-and-panes.md'), 'navigation-and-panes');
  assert.equal(slugFor('commands.md'), 'commands');
});

test('frontmatter comes from the heading and the first paragraph', () => {
  const out = transform('01-navigation-and-panes.md', '# 1 Navigation and panes\n\nPanes show "folders".\n\n## Panes\n\nText.\n', files);
  assert.match(out, /^---\ntitle: "Navigation and panes"\n/);
  assert.match(out, /description: "Panes show \\"folders\\"."/);
  assert.match(out, /sidebar:\n {2}order: 1\n/);
  assert.match(out, /editUrl: "https:\/\/github.com\/bimurto\/file-term\/edit\/main\/docs\/user-guide\/01-navigation-and-panes.md"/);
  assert.doesNotMatch(out, /^# 1 Navigation/m);
  assert.match(out, /## Panes/);
});

test('the index and the command reference get fixed places in the sidebar', () => {
  assert.match(transform('README.md', '# FileTerm user guide\n\nIntro.\n', files), /order: 0\n/);
  const commands = transform('commands.md', '# Command reference\n\nEvery command.\n', files);
  assert.match(commands, /order: 14\n/);
  assert.match(commands, /label: "Command reference"/);
});

test('links between chapters point at site pages and keep their anchors', () => {
  const out = transform(
    'README.md',
    '# Guide\n\nSee [one](01-navigation-and-panes.md), [gaps](13-limits-and-known-gaps.md#not-built) and [new tab](commands.md#file.newTab).\n',
    files,
  );
  assert.match(out, /\[one\]\(\/docs\/navigation-and-panes\/\)/);
  assert.match(out, /\[gaps\]\(\/docs\/limits-and-known-gaps\/#not-built\)/);
  assert.match(out, /\[new tab\]\(\/docs\/commands\/#file.newTab\)/);
  assert.doesNotMatch(out, /\.md[)#]/);
});

test('inline anchors pass through untouched', () => {
  const out = transform('commands.md', '# Command reference\n\nIntro.\n\n| <a id="file.newTab"></a>New Tab | `⌘T` |\n', files);
  assert.match(out, /<a id="file.newTab"><\/a>New Tab/);
});

test('a link to a page that is not in the guide fails the build', () => {
  assert.throws(() => transform('README.md', '# Guide\n\n[x](missing.md)\n', files), /missing\.md/);
  assert.throws(() => transform('README.md', '# Guide\n\n[x](../README.md)\n', files), /\.\.\/README\.md/);
});

test('a page without a top heading fails the build', () => {
  assert.throws(() => transform('README.md', 'No heading\n', files), /heading/);
});
