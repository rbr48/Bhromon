import { getFirestore } from 'firebase-admin/firestore';

const CLOUDFLARE_API = 'https://api.cloudflare.com/client/v4';
/** Cloudflare accepts this many file URLs in one purge request. */
const MAX_FILES_PER_REQUEST = 30;
const MEDIA_BASE_URL = 'https://bhromon.fun/media';

/** The public URLs of media files, from their paths on the media server. */
export function mediaUrlsFor(paths: string[]): string[] {
  return paths.map((path) => `${MEDIA_BASE_URL}/${path}`);
}

/** The URLs split into the batches Cloudflare accepts. */
export function chunkUrls(urls: string[], size = MAX_FILES_PER_REQUEST): string[][] {
  const batches: string[][] = [];
  for (let i = 0; i < urls.length; i += size) batches.push(urls.slice(i, i + size));
  return batches;
}

/**
 * Removes cached copies of deleted media from the CDN, so they stop being served at
 * once rather than when the cache expires. Does nothing until the zone and token are
 * set in config/cdn. Returns how many URLs were purged.
 */
export async function purgeCdnPaths(paths: string[]): Promise<number> {
  if (paths.length === 0) return 0;
  const config = (await getFirestore().collection('config').doc('cdn').get()).data() ?? {};
  const zone = typeof config.zoneId === 'string' ? config.zoneId : '';
  const token = typeof config.apiToken === 'string' ? config.apiToken : '';
  if (!zone || !token) return 0;

  let purged = 0;
  for (const files of chunkUrls(mediaUrlsFor(paths))) {
    const response = await fetch(`${CLOUDFLARE_API}/zones/${encodeURIComponent(zone)}/purge_cache`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ files }),
    });
    if (!response.ok) throw new Error(`CDN purge answered HTTP ${response.status}`);
    purged += files.length;
  }
  return purged;
}
