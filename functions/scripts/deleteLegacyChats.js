// Deletes the direct chats made before chats were tied to a tour: every chat
// document without a sharedTourId, with its messages. Chats made since then
// are kept.
//
// Dry run by default. It counts the chats it would delete and deletes nothing.
// Pass --apply to delete them.
//
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node functions/scripts/deleteLegacyChats.js --project bhromon-ff801
//   ...then add --apply to delete.
const { initializeApp } = require('firebase-admin/app');
const { FieldPath, getFirestore } = require('firebase-admin/firestore');

const PAGE_SIZE = 300;

/** The references of every chat that has no sharedTourId. */
async function findLegacyChats(db) {
  const legacy = [];
  let last = null;
  for (;;) {
    let query = db
      .collection('chats')
      .orderBy(FieldPath.documentId())
      .limit(PAGE_SIZE);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    for (const doc of page.docs) {
      if (doc.get('sharedTourId') === undefined) legacy.push(doc.ref);
    }
    if (page.size < PAGE_SIZE) break;
    last = page.docs[page.docs.length - 1];
  }
  return legacy;
}

/**
 * Deletes the legacy chats with their messages when apply is true. Either way,
 * returns how many were found and how many were deleted.
 */
async function deleteLegacyChats(db, { apply }) {
  const legacy = await findLegacyChats(db);
  if (!apply) return { found: legacy.length, deleted: 0 };
  for (const ref of legacy) {
    await db.recursiveDelete(ref);
  }
  return { found: legacy.length, deleted: legacy.length };
}

module.exports = { findLegacyChats, deleteLegacyChats };

if (require.main === module) {
  const args = process.argv.slice(2);
  const apply = args.includes('--apply');
  const projectFlag = args.indexOf('--project');
  const projectId =
    projectFlag >= 0 ? args[projectFlag + 1] : process.env.GCLOUD_PROJECT;
  if (!projectId) {
    console.error('Pass the Firebase project id with --project.');
    process.exit(1);
  }
  initializeApp({ projectId });
  deleteLegacyChats(getFirestore(), { apply })
    .then(({ found, deleted }) => {
      console.log(
        apply
          ? `Deleted ${deleted} chats, with their messages.`
          : `Dry run: ${found} chats would be deleted. Add --apply to delete them.`,
      );
    })
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
