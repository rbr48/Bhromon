import { chunkUrls, mediaUrlsFor } from '../lib/cdnPurge';

describe('CDN purge', () => {
  it('names each deleted file by its public media URL', () => {
    expect(mediaUrlsFor(['tour/posts/a.jpg', 'chat_x/chat_media/b.m4a'])).toEqual([
      'https://bhromon.fun/media/tour/posts/a.jpg',
      'https://bhromon.fun/media/chat_x/chat_media/b.m4a',
    ]);
  });

  it('sends the URLs in batches Cloudflare accepts', () => {
    const urls = Array.from({ length: 65 }, (_, i) => `u${i}`);
    const batches = chunkUrls(urls);
    expect(batches.map((batch) => batch.length)).toEqual([30, 30, 5]);
    expect(batches.flat()).toEqual(urls);
  });

  it('sends nothing when there is nothing to purge', () => {
    expect(chunkUrls([])).toEqual([]);
  });
});
