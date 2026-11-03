// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';
import syncUserGuide from './src/integrations/sync-user-guide.mjs';

export default defineConfig({
  site: 'https://fileterm.bimurto.io',
  trailingSlash: 'always',
  integrations: [
    syncUserGuide(),
    starlight({
      title: 'FileTerm',
      description: 'User guide for FileTerm, a dual-pane file manager for macOS with a built-in terminal.',
      favicon: '/favicon.png',
      logo: { src: './src/assets/icon.png', alt: '' },
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/bimurto/file-term' }],
      sidebar: [{ label: 'User guide', items: [{ autogenerate: { directory: 'docs' } }] }],
      customCss: ['@fontsource-variable/hanken-grotesk/index.css', './src/styles/starlight.css'],
      editLink: { baseUrl: 'https://github.com/bimurto/file-term/edit/main/docs/user-guide/' },
      lastUpdated: false,
      plugins: [starlightLinksValidator()],
    }),
  ],
});
