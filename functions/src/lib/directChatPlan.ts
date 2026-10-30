/** The id of the one-to-one chat between two accounts: their ids sorted and joined. */
export function chatIdFor(a: string, b: string): string {
  return [a, b].sort().join('_');
}

/** The Storage folders that hold files from one-to-one chats. */
const CHAT_STORAGE_FOLDERS = [
  'chat_docs/',
  'chat_voice/',
  'chat_media/',
  'chat_media_thumbs/',
];

/** Whether a Storage path is a chat file. Only those are removed by a chat purge. */
export function isChatStoragePath(path: string): boolean {
  return (
    !path.includes('..') &&
    CHAT_STORAGE_FOLDERS.some((folder) => path.startsWith(folder))
  );
}

/** The Storage path behind a Firebase download URL, or null for any other URL. */
export function storagePathFromUrl(url: unknown): string | null {
  if (typeof url !== 'string') return null;
  const marker = '/o/';
  const at = url.indexOf(marker);
  if (at < 0) return null;
  const encoded = url.slice(at + marker.length).split('?')[0];
  try {
    return decodeURIComponent(encoded);
  } catch {
    return null;
  }
}

/** A media file on the media server, named by its URL. Other values are not files. */
export function isHttpUrl(value: unknown): value is string {
  return typeof value === 'string' && /^https?:\/\//.test(value);
}
