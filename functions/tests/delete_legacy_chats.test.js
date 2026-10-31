// Deleting the chats made before tours tied them. A dry run deletes nothing; --apply
// deletes every chat without a sharedTourId, with its messages, and keeps the rest.
// Needs the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/delete_legacy_chats"
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { findLegacyChats, deleteLegacyChats } = require('../scripts/deleteLegacyChats');

const PROJECT_ID = 'bhromon-rules-test-project';

describe('deleting the chats made before tours tied them', () => {
  let db;

  beforeAll(() => {
    if (!getApps().length) initializeApp({ projectId: PROJECT_ID });
    db = getFirestore();
  });

  beforeEach(async () => {
    await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`, {
      method: 'DELETE',
    });
  });

  async function seedChat(id, data, messageCount) {
    await db.doc(`chats/${id}`).set(data);
    for (let i = 0; i < messageCount; i++) {
      await db.doc(`chats/${id}/messages/m${i}`).set({ senderId: 'a', type: 'text', text: 'hi' });
    }
  }

  async function seedLegacyAndNew() {
    await seedChat('legacy_ab', { participants: ['a', 'b'], lastMessage: 'old' }, 2);
    await seedChat('legacy_cd', { participants: ['c', 'd'] }, 1);
    await seedChat('legacy_ai', { participants: ['a', 'bhromon_ai_advisor'] }, 1);
    await seedChat(
      'new_xy',
      {
        participants: ['x', 'y'],
        sharedTourId: 'tour_a',
        memberEmails: { x: 'x@x.com', y: 'y@x.com' },
      },
      1,
    );
  }

  test('a dry run finds the old chats and deletes nothing', async () => {
    await seedLegacyAndNew();

    const result = await deleteLegacyChats(db, { apply: false });

    expect(result).toEqual({ found: 3, deleted: 0 });
    expect((await db.doc('chats/legacy_ab').get()).exists).toBe(true);
    expect((await db.collection('chats/legacy_ab/messages').get()).size).toBe(2);
  });

  test('apply deletes the old chats with their messages, and keeps the new chat', async () => {
    await seedLegacyAndNew();

    const result = await deleteLegacyChats(db, { apply: true });

    expect(result).toEqual({ found: 3, deleted: 3 });
    for (const id of ['legacy_ab', 'legacy_cd', 'legacy_ai']) {
      expect((await db.doc(`chats/${id}`).get()).exists).toBe(false);
      expect((await db.collection(`chats/${id}/messages`).get()).size).toBe(0);
    }
    expect((await db.doc('chats/new_xy').get()).exists).toBe(true);
    expect((await db.collection('chats/new_xy/messages').get()).size).toBe(1);
  });

  test('a list longer than one page is searched in full', async () => {
    const batch = db.batch();
    for (let i = 0; i < 305; i++) {
      batch.set(db.doc(`chats/old_${String(i).padStart(3, '0')}`), { participants: ['p', 'q'] });
    }
    batch.set(db.doc('chats/new_one'), { sharedTourId: 'tour_a', participants: ['p', 'r'] });
    await batch.commit();

    const legacy = await findLegacyChats(db);

    expect(legacy).toHaveLength(305);
    expect(legacy.map((ref) => ref.id)).not.toContain('new_one');
  });
});
