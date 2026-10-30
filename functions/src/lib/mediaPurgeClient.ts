/** The media server's purge routes, called by the back end with the purge key. */
export const MEDIA_PURGE_URL =
  process.env.MEDIA_PURGE_URL ?? 'https://bhromon.fun/api/media/purge';

/**
 * POSTs [body] to a purge route under [MEDIA_PURGE_URL]: '' for the tour's
 * files, '/chat' for a person's chat messages. Throws when the call fails, so
 * the purge job stays pending and is retried.
 */
export async function postToMediaPurge<T>(
  route: '' | '/chat',
  body: unknown,
): Promise<T> {
  const key = process.env.MEDIA_PURGE_KEY;
  if (!key) throw new Error('MEDIA_PURGE_KEY is not configured');
  const response = await fetch(`${MEDIA_PURGE_URL}${route}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Purge-Key': key },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    throw new Error(`Media purge answered HTTP ${response.status}`);
  }
  return (await response.json()) as T;
}
