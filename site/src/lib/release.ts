// The latest GitHub release, read once at build time. Null until the first release exists
// (or while the repository is private), so the page can fall back to building from source.
const repo = 'bimurto/file-term';
export const repoUrl = `https://github.com/${repo}`;
export const releasesUrl = `${repoUrl}/releases`;

export interface Release {
  version: string;
  url: string;
  notesUrl: string;
  date: string;
  sizeMB: number | null;
  sha256: string | null;
}

let cached: Promise<Release | null> | undefined;

export function getRelease(): Promise<Release | null> {
  cached ??= load();
  return cached;
}

async function load(): Promise<Release | null> {
  const token = process.env.GITHUB_TOKEN;
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'fileterm-site',
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  let response: Response;
  try {
    response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, { headers });
  } catch (error) {
    if (token) throw error;
    console.warn(`[release] GitHub is unreachable, building without a release: ${error}`);
    return null;
  }
  if (response.status === 404) return null;
  if (!response.ok) {
    const message = `[release] GitHub answered ${response.status} for the latest release`;
    if (token) throw new Error(message);
    console.warn(message);
    return null;
  }

  const release = await response.json();
  const dmg = release.assets?.find((asset: { name: string }) => asset.name === 'FileTerm.dmg');
  if (!dmg) throw new Error(`[release] ${release.tag_name} has no FileTerm.dmg asset`);
  const checksum = release.assets?.find((asset: { name: string }) => asset.name === 'FileTerm.dmg.sha256');

  let sha256: string | null = null;
  if (checksum) {
    const text = await (await fetch(checksum.browser_download_url, { headers: { 'User-Agent': 'fileterm-site' } })).text();
    sha256 = text.trim().split(/\s+/)[0] || null;
  }

  return {
    version: String(release.tag_name).replace(/^v/, ''),
    url: dmg.browser_download_url,
    notesUrl: release.html_url,
    date: new Date(release.published_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' }),
    sizeMB: dmg.size ? Math.round(dmg.size / 1_000_000) : null,
    sha256,
  };
}
