// Makes the hero's app fragment work: the panes and the terminal follow each other, like FileTerm.
import { baseName, crumbs, gitLog, home, inRepo, list, resolve, startPaths } from '../lib/demo';

const escape = (text: string) => text.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const icon = (folder: boolean) =>
  `<svg class="ico ${folder ? 'ico-folder' : 'ico-file'}" aria-hidden="true"><use href="#i-${folder ? 'folder' : 'file'}"></use></svg>`;

export function mountApp(root: HTMLElement) {
  const panes = [...root.querySelectorAll<HTMLElement>('[data-pane]')];
  const out = root.querySelector<HTMLElement>('[data-out]')!;
  const screen = root.querySelector<HTMLElement>('[data-screen]')!;
  const form = root.querySelector<HTMLFormElement>('[data-prompt]')!;
  const input = form.querySelector('input')!;
  const label = root.querySelector<HTMLElement>('[data-prompt-label]')!;
  const linkButton = root.querySelector<HTMLButtonElement>('[data-link]')!;
  const termName = root.querySelector<HTMLElement>('[data-term-name]')!;
  const title = root.querySelector<HTMLElement>('[data-title]')!;

  const state = { paths: [...startPaths], active: 0, cwd: startPaths[0], previous: startPaths[0], linked: true };
  const history: string[] = [];
  let historyIndex = 0;

  const promptHTML = (path: string) => {
    const git = inRepo(path)
      ? ` <span class="c-git">git:(</span><span class="c-branch">main</span><span class="c-git">)</span> <span class="c-dirty g-dirty" aria-hidden="true"></span>`
      : '';
    return `<span class="c-ok g-arrow" aria-hidden="true"></span>  <span class="c-dir">${escape(baseName(path))}</span>${git}`;
  };

  const print = (html: string) => {
    const line = document.createElement('p');
    line.innerHTML = html;
    out.append(line);
    while (out.children.length > 60) out.firstElementChild?.remove();
    screen.scrollTop = screen.scrollHeight;
  };

  const renderPrompt = () => { label.innerHTML = `<samp>${promptHTML(state.cwd)}</samp>`; };

  const renderPane = (index: number) => {
    const pane = panes[index];
    const path = state.paths[index];
    const entries = list(path);
    pane.querySelector('[data-crumbs]')!.innerHTML = crumbs(path)
      .map((c, i) => `${i ? '<span class="sep" aria-hidden="true">›</span>' : ''}<button type="button" data-go="${escape(c.path)}">${icon(true)}${escape(c.name)}</button>`)
      .join('');
    pane.querySelector('[data-list]')!.innerHTML = entries
      .map((e) => `<li><button type="button" class="ft-row" data-name="${escape(e.name)}"${e.folder ? ` data-folder aria-label="Open folder ${escape(e.name)}"` : ' aria-pressed="false"'}>${icon(e.folder)}<span class="name">${escape(e.name)}</span><span class="size">${escape(e.size)}</span></button></li>`)
      .join('');
    pane.querySelector('[data-count]')!.textContent = `${entries.length} items`;
    if (index === state.active) title.textContent = `FileTerm — ${baseName(path)}`;
  };

  const setActive = (index: number) => {
    state.active = index;
    panes.forEach((p, i) => p.classList.toggle('is-active', i === index));
    termName.firstChild!.textContent = `${index === 0 ? 'First' : 'Second'} pane · Tab 1`;
    title.textContent = `FileTerm — ${baseName(state.paths[index])}`;
  };

  // The pane moved: at an idle prompt a linked terminal follows, the way the app types `cd -- '…'`.
  const terminalFollows = (path: string) => {
    if (!state.linked || path === state.cwd || input.value.trim()) return;
    print(`${promptHTML(state.cwd)}  <span class="c-cmd">cd</span> -- <span class="c-str">'${escape(path)}'</span>`);
    state.previous = state.cwd;
    state.cwd = path;
    renderPrompt();
  };

  const openInPane = (index: number, path: string) => {
    state.paths[index] = path;
    renderPane(index);
    if (index === state.active) terminalFollows(path);
  };

  const run = (raw: string) => {
    const command = raw.trim();
    print(`${promptHTML(state.cwd)} ${escape(raw)}`);
    if (!command) return;
    history.push(command);
    historyIndex = history.length;
    const [name, ...args] = command.split(/\s+/);
    const arg = args.join(' ');
    switch (name) {
      case 'cd': {
        const target = resolve(state.cwd, arg, state.previous);
        if (!target) return print(`<span class="c-err">cd: no such file or directory: ${escape(arg)}</span>`);
        state.previous = state.cwd;
        state.cwd = target;
        if (state.linked) {
          state.paths[state.active] = target;
          renderPane(state.active);
        }
        return;
      }
      case 'ls': {
        const target = arg ? resolve(state.cwd, arg, state.previous) : state.cwd;
        if (!target) return print(`<span class="c-err">ls: ${escape(arg)}: No such file or directory</span>`);
        const names = list(target).map((e) => (e.folder ? `<span class="c-dir">${escape(e.name)}</span>` : escape(e.name)));
        return print(`<span class="ls">${names.map((n) => `<span>${n}</span>`).join('')}</span>`);
      }
      case 'pwd': return print(escape(state.cwd));
      case 'clear': out.innerHTML = ''; return;
      case 'whoami': return print('you');
      case 'git':
        if (!inRepo(state.cwd)) return print('<span class="c-err">fatal: not a git repository (or any of the parent directories): .git</span>');
        if (args[0] === 'status') return print('On branch main<br>Untracked files:<br>  <span class="c-err">src/lib/motion.ts</span>');
        return gitLog.forEach((line) => print(escape(line).replace(/^(\w+)/, '<span class="c-hash">$1</span>').replace('(HEAD -&gt; main)', '(<span class="c-head">HEAD -&gt; main</span>)')));
      case 'help':
        return print('<span class="c-soft">This is a small copy of FileTerm. Try cd, cd .., cd -, ls, pwd, git log or clear, or click a folder in either pane.</span>');
      default:
        return print(`<span class="c-err">zsh: command not found: ${escape(name)}</span>`);
    }
  };

  // Rows and breadcrumbs: one click opens a folder (thumb friendly) or selects a file.
  panes.forEach((pane, index) => {
    pane.addEventListener('click', (event) => {
      const target = event.target as HTMLElement;
      if (index !== state.active) {
        setActive(index);
        terminalFollows(state.paths[index]);
      }
      const go = target.closest<HTMLElement>('[data-go]');
      if (go) return openInPane(index, go.dataset.go!);
      const row = target.closest<HTMLElement>('.ft-row');
      if (!row) return;
      if (row.hasAttribute('data-folder')) {
        const path = state.paths[index];
        return openInPane(index, `${path === '/' ? '' : path}/${row.dataset.name}`);
      }
      pane.querySelectorAll('.ft-row[aria-pressed="true"]').forEach((r) => r.setAttribute('aria-pressed', 'false'));
      row.setAttribute('aria-pressed', 'true');
    });
  });

  linkButton.addEventListener('click', () => {
    state.linked = !state.linked;
    linkButton.setAttribute('aria-pressed', String(state.linked));
    linkButton.textContent = state.linked ? 'Linked' : 'Unlinked';
    if (state.linked) terminalFollows(state.paths[state.active]);
  });

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    run(input.value);
    input.value = '';
    input.placeholder = '';
    renderPrompt();
  });

  input.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowUp' && history.length) {
      event.preventDefault();
      historyIndex = Math.max(0, historyIndex - 1);
      input.value = history[historyIndex];
    } else if (event.key === 'ArrowDown' && history.length) {
      event.preventDefault();
      historyIndex = Math.min(history.length, historyIndex + 1);
      input.value = history[historyIndex] ?? '';
    } else if (event.key === 'Tab' && !event.shiftKey) {
      // Complete a folder name only when there is exactly one match; otherwise Tab moves focus as usual.
      const match = input.value.match(/^(cd|ls)\s+(.*)$/);
      if (!match) return;
      const typed = match[2];
      const slash = typed.lastIndexOf('/');
      const base = slash >= 0 ? resolve(state.cwd, typed.slice(0, slash) || '/', state.previous) : state.cwd;
      if (!base) return;
      const prefix = typed.slice(slash + 1);
      const options = list(base).filter((e) => e.folder && e.name.toLowerCase().startsWith(prefix.toLowerCase()));
      if (options.length !== 1) return;
      event.preventDefault();
      input.value = `${match[1]} ${typed.slice(0, slash + 1)}${options[0].name}/`;
    }
  });

  root.querySelector('.ft-term')!.addEventListener('click', (event) => {
    if (!(event.target as HTMLElement).closest('button, a') && !getSelection()?.toString()) input.focus({ preventScroll: true });
  });

  form.hidden = false;
  input.placeholder = state.cwd === home ? 'try: cd Projects' : 'try: cd src';
  renderPrompt();
}
