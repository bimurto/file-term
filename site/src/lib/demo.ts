// The folder tree behind the live demo. Shared by the server-rendered snapshot and the browser script.
import data from '../data/demo-tree.json';

type FileInfo = [size: string, kind: string, modified: string];
type Folder = { [name: string]: Folder | FileInfo };

export const home = data.home;
export const startPaths = data.start as [string, string];
export const gitRepo = data.git.repo;
export const gitLog = data.git.log;
const root: Folder = { Users: { you: data.tree as Folder } };

export interface Entry { name: string; folder: boolean; size: string; kind: string }

function node(path: string): Folder | FileInfo | undefined {
  let current: Folder | FileInfo = root;
  for (const part of path.split('/').filter(Boolean)) {
    if (Array.isArray(current)) return undefined;
    current = current[part];
    if (current === undefined) return undefined;
  }
  return current;
}

export const isFolder = (path: string) => {
  const found = node(path);
  return found !== undefined && !Array.isArray(found);
};

export function list(path: string): Entry[] {
  const folder = node(path);
  if (!folder || Array.isArray(folder)) return [];
  return Object.entries(folder)
    .map(([name, value]) => Array.isArray(value)
      ? { name, folder: false, size: value[0], kind: value[1] }
      : { name, folder: true, size: '—', kind: 'Folder' })
    .sort((a, b) => Number(b.folder) - Number(a.folder) || a.name.localeCompare(b.name, 'en', { sensitivity: 'base' }));
}

/** Resolves a shell argument against the working folder. Returns null when it isn't a folder. */
export function resolve(cwd: string, arg: string, previous: string): string | null {
  let target = arg.trim().replace(/^['"]|['"]$/g, '');
  if (target === '' || target === '~') return home;
  if (target === '-') return previous;
  if (target.startsWith('~/')) target = home + target.slice(1);
  const parts = (target.startsWith('/') ? target : `${cwd}/${target}`).split('/');
  const out: string[] = [];
  for (const part of parts) {
    if (!part || part === '.') continue;
    if (part === '..') out.pop();
    else out.push(part);
  }
  const path = '/' + out.join('/');
  return isFolder(path) ? path : null;
}

export const baseName = (path: string) => (path === home ? '~' : path.split('/').filter(Boolean).pop() ?? '/');
export const inRepo = (path: string) => path === gitRepo || path.startsWith(gitRepo + '/');

/** Breadcrumbs start at the home folder, the way the app shows them. */
export function crumbs(path: string): { name: string; path: string }[] {
  const relative = path.startsWith(home) ? path.slice(home.length) : path;
  const items = [{ name: 'you', path: home }];
  let built = home;
  for (const part of relative.split('/').filter(Boolean)) {
    built += '/' + part;
    items.push({ name: part, path: built });
  }
  return items;
}
