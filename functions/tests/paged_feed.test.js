// The instafeed reads posts in pages of creation-time ranges (see
// lib/features/tour_group/data/paged_post_feed.dart). These tests run the same
// queries against the Firestore emulator and check that the pages meet: every
// post appears once, in order, with no gap between two pages.
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "npx jest --runInBand tests/paged_feed"
const { initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, setDoc, collection, getDocs, query, where, orderBy, limit, Timestamp } = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 'paged';
const PAGE = 60;
// Millisecond-aligned times, as the app's DateTime boundaries are.
const BASE = Date.UTC(2026, 0, 1);

describe('paged feed queries', () => {
  let env;

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: 'rules_version = "2"; service cloud.firestore { match /databases/{database}/documents { match /{document=**} { allow read, write: if true; } } }',
        host: '127.0.0.1',
        port: 8080,
      },
    });
  });

  afterAll(async () => {
    await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
  });

  // Mirrors PagedPostFeed._open: the page's lower bound comes from the 60th
  // newest post below `upper`, or null when fewer than 60 remain.
  async function boundary(db, upper) {
    const parts = [];
    if (upper) parts.push(where('createdAt', '<', upper));
    parts.push(orderBy('createdAt', 'desc'), limit(PAGE));
    const snap = await getDocs(query(collection(db, 'tours', TOUR, 'posts'), ...parts));
    if (snap.docs.length < PAGE) return null;
    return snap.docs[snap.docs.length - 1].data().createdAt;
  }

  // Mirrors TourGroupRepository.watchPostRange, read once.
  async function pageBetween(db, upper, lower) {
    const parts = [];
    if (upper) parts.push(where('createdAt', '<', upper));
    if (lower) parts.push(where('createdAt', '>=', lower));
    parts.push(orderBy('createdAt', 'desc'));
    const snap = await getDocs(query(collection(db, 'tours', TOUR, 'posts'), ...parts));
    return snap.docs.map((d) => d.id);
  }

  // Mirrors PagedPostFeed.loadMore until the last page. Returns the pages'
  // ids and the bounds that define them, which the live listeners keep.
  async function loadFeed(db) {
    const pages = [];
    const bounds = [];
    let upper = null;
    for (;;) {
      const lower = await boundary(db, upper);
      bounds.push({ upper, lower });
      pages.push(await pageBetween(db, upper, lower));
      if (lower === null) break;
      upper = lower;
    }
    return { pages, bounds };
  }

  // withSecurityRulesDisabled does not return the callback's value, so the
  // result is taken from a closure.
  async function readFeed() {
    let result;
    await env.withSecurityRulesDisabled(async (ctx) => {
      result = await loadFeed(ctx.firestore());
    });
    return result;
  }

  async function rereadPages(bounds) {
    let result;
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      result = [];
      for (const b of bounds) result.push(await pageBetween(db, b.upper, b.lower));
    });
    return result;
  }

  async function seed(posts) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const p of posts) {
        await setDoc(doc(db, 'tours', TOUR, 'posts', p.id), { caption: p.id, createdAt: Timestamp.fromMillis(p.at) });
      }
    });
  }

  function postsAt(count, startIndex = 0) {
    return Array.from({ length: count }, (_, i) => ({
      id: `p${String(startIndex + i).padStart(4, '0')}`,
      at: BASE + (startIndex + i) * 1000,
    }));
  }

  test('pages of 60 cover 150 posts once each, newest first', async () => {
    await seed(postsAt(150));
    const { pages } = await readFeed();

    expect(pages.map((p) => p.length)).toEqual([60, 60, 30]);
    const all = pages.flat();
    expect(new Set(all).size).toBe(150);
    expect(all).toEqual(postsAt(150).map((p) => p.id).reverse());
  });

  test('a multiple of the page size ends with an empty last page', async () => {
    await seed(postsAt(120));
    const { pages } = await readFeed();

    expect(pages.map((p) => p.length)).toEqual([60, 60, 0]);
    expect(pages.flat()).toHaveLength(120);
  });

  test('posts sharing a timestamp across a boundary are neither lost nor doubled', async () => {
    const posts = postsAt(70).map((p, i) => (i >= 58 && i <= 63 ? { ...p, at: BASE + 58 * 1000 } : p));
    await seed(posts);
    const { pages } = await readFeed();

    const all = pages.flat();
    expect(all).toHaveLength(70);
    expect(new Set(all)).toEqual(new Set(posts.map((p) => p.id)));
  });

  test('a new post joins the newest page; older pages keep their bounds and contents', async () => {
    await seed(postsAt(130));
    const { pages: before, bounds } = await readFeed();

    await seed([{ id: 'fresh', at: BASE + 130 * 1000 }]);
    // The live listeners keep each page's bounds, so re-read with the same ones.
    const after = await rereadPages(bounds);

    expect(after[0][0]).toBe('fresh');
    expect(after[0]).toHaveLength(before[0].length + 1);
    expect(after.slice(1)).toEqual(before.slice(1));
    expect(new Set(after.flat()).size).toBe(131);
  });
});
