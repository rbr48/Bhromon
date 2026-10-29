const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.cert(require('/run/secrets/firebase-admin.json')),
});

const db = admin.firestore();

async function main() {
  const snap = await db.collectionGroup('games').get();
  console.log(`Found ${snap.size} total game table(s).`);

  for (const doc of snap.docs) {
    const data = doc.data();
    console.log(`Deleting game table: ${doc.ref.path} (${data.tableName || 'unnamed'}, status: ${data.status}, game: ${data.gameType})`);

    // Delete subcollections like 'private'
    const privateSnap = await doc.ref.collection('private').get();
    for (const pDoc of privateSnap.docs) {
      console.log(`  Deleting subdoc: ${pDoc.ref.path}`);
      await pDoc.ref.delete();
    }

    await doc.ref.delete();
    console.log(`  Successfully deleted ${doc.ref.path}`);
  }

  console.log('All open game tables have been deleted successfully.');
}

main().catch((err) => {
  console.error('Error deleting game tables:', err);
  process.exit(1);
});
