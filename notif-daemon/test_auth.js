const admin = require('firebase-admin');
const path = require('path');
const serviceAccount = require('./service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function run() {
  try {
    console.log("Trying to get collection group 'notifications'...");
    const snap = await db.collectionGroup('notifications').limit(1).get();
    console.log("CollectionGroup success! Found docs:", snap.size);
  } catch (e) {
    console.error("CollectionGroup failed:", e.message);
  }

  try {
    console.log("Trying to get collection 'notifications'...");
    const snap2 = await db.collection('notifications').limit(1).get();
    console.log("Collection success! Found docs:", snap2.size);
  } catch (e) {
    console.error("Collection failed:", e.message);
  }
}

run();
