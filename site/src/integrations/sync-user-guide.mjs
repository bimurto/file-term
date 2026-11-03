import { guideDir, syncDocs } from '../../scripts/sync-docs.mjs';

/** Regenerates the docs pages from docs/user-guide before every build and on edits in dev. */
export default function syncUserGuide() {
  return {
    name: 'sync-user-guide',
    hooks: {
      'astro:config:setup': ({ logger }) => {
        logger.info(`Synced ${syncDocs()} user guide pages`);
      },
      'astro:server:setup': ({ server, logger }) => {
        server.watcher.add(guideDir);
        server.watcher.on('change', (path) => {
          if (path.startsWith(guideDir)) logger.info(`Re-synced ${syncDocs()} pages`);
        });
      },
    },
  };
}
