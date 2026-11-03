// Page behaviour: section entrances, the link switch, the theme crossfade, the video and the install sheet.
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');

// Entrances: once per element, and never leave content hidden if the observer doesn't fire.
const revealed = document.querySelectorAll<HTMLElement>('[data-reveal]');
if ('IntersectionObserver' in window) {
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('is-in');
      io.unobserve(entry.target);
    }
  }, { rootMargin: '0px 0px -10% 0px', threshold: 0.08 });
  revealed.forEach((el) => io.observe(el));
  addEventListener('load', () => setTimeout(() => {
    revealed.forEach((el) => { const r = el.getBoundingClientRect(); if (r.top < innerHeight && r.bottom > 0) el.classList.add('is-in'); });
  }, 2500));
} else {
  revealed.forEach((el) => el.classList.add('is-in'));
}

// The link switch: swaps the field between the terminal's violet and the folder's coral.
const showcase = document.querySelector<HTMLElement>('[data-showcase]');
const toggle = showcase?.querySelector<HTMLButtonElement>('[data-switch]');
if (showcase && toggle) {
  toggle.addEventListener('click', () => {
    const linked = toggle.getAttribute('aria-checked') !== 'true';
    toggle.setAttribute('aria-checked', String(linked));
    showcase.dataset.linked = String(linked);
    showcase.querySelector('[data-word]')!.textContent = linked ? 'together' : 'apart';
    showcase.querySelector('[data-state]')!.textContent = linked ? 'linked to the pane' : 'unlinked';
    showcase.querySelector<HTMLElement>('[data-copy="on"]')!.hidden = !linked;
    showcase.querySelector<HTMLElement>('[data-copy="off"]')!.hidden = linked;
  });
}

// The signature move: the same window crossfades through its themes, like light shifting in a room.
const stage = document.querySelector<HTMLElement>('[data-crossfade]');
if (stage && !reduceMotion.matches) {
  const pictures = [...stage.querySelectorAll<HTMLElement>('picture')];
  const label = document.querySelector<HTMLElement>('[data-theme-name]');
  let index = 0;
  let timer: number | undefined;
  const step = () => {
    pictures[index].classList.remove('is-shown');
    index = (index + 1) % pictures.length;
    pictures[index].classList.add('is-shown');
    if (label) label.textContent = pictures[index].dataset.name ?? '';
  };
  const start = () => { if (timer === undefined) timer = window.setInterval(step, 5600); };
  const stop = () => { window.clearInterval(timer); timer = undefined; };
  // Load the other themes only when the band comes near, then run while it is on screen.
  const io = new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) {
      stage.querySelectorAll('img[loading="lazy"]').forEach((img) => img.setAttribute('loading', 'eager'));
      start();
    } else stop();
  }, { threshold: 0.25 });
  io.observe(stage);
  document.addEventListener('visibilitychange', () => (document.hidden ? stop() : null));
}

// The recording plays only while it is visible, and not at all under reduced motion.
document.querySelectorAll<HTMLVideoElement>('video[data-autoplay]').forEach((video) => {
  if (reduceMotion.matches) return;
  const io = new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) video.play().catch(() => {});
    else video.pause();
  }, { threshold: 0.35 });
  io.observe(video);
});

// The install sheet: two tabs, a clone folder that rewrites the commands, and a copy button.
const sheet = document.querySelector<HTMLElement>('[data-sheet]');
if (sheet) {
  const tabs = [...sheet.querySelectorAll<HTMLButtonElement>('[role="tab"]')];
  const select = (tab: HTMLButtonElement) => {
    tabs.forEach((t) => {
      const on = t === tab;
      t.setAttribute('aria-selected', String(on));
      t.tabIndex = on ? 0 : -1;
      sheet.querySelector<HTMLElement>(`[data-panel="${t.dataset.tab}"]`)!.hidden = !on;
    });
  };
  tabs.forEach((tab, i) => {
    tab.addEventListener('click', () => select(tab));
    tab.addEventListener('keydown', (event) => {
      if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return;
      const next = tabs[(i + (event.key === 'ArrowRight' ? 1 : tabs.length - 1)) % tabs.length];
      select(next);
      next.focus();
    });
  });

  const field = sheet.querySelector<HTMLInputElement>('[data-clone-dir]');
  const commands = sheet.querySelector<HTMLElement>('[data-commands]');
  const copy = sheet.querySelector<HTMLButtonElement>('[data-copy]');
  if (field && commands) {
    const lines = commands.textContent!.split('\n');
    const clone = lines[0].slice(0, lines[0].indexOf('.git ') + 4);
    const original = field.value;
    field.addEventListener('input', () => {
      const dir = field.value.trim() || original;
      const quoted = /[\s'"$`\\]/.test(dir) ? `'${dir.replace(/'/g, `'\\''`)}'` : dir;
      lines[0] = `${clone} ${quoted}`;
      lines[1] = `cd ${quoted}`;
      commands.textContent = lines.join('\n');
    });
  }
  copy?.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(commands!.textContent!);
      copy.textContent = 'Copied';
    } catch {
      copy.textContent = 'Select the text to copy';
    }
    setTimeout(() => (copy.textContent = 'Copy commands'), 1800);
  });
}
