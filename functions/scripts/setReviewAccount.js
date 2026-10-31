// Sets the sign-in account that Play review uses. Only a digest of its code is
// stored, in config/auth, so the code is not kept anywhere in the source or the
// database. The code comes from the environment, not the command line, so it stays
// out of shell history.
//
//   REVIEW_CODE='<a long random code>' node functions/scripts/setReviewAccount.js \
//     --project bhromon-ff801 --email tester@bhromon.fun
//
//   node functions/scripts/setReviewAccount.js --project bhromon-ff801 --clear
//
// Give the same email and code to Play Console as the reviewer's sign-in.
const crypto = require('crypto');
const admin = require('firebase-admin');

/** The digest verifyOtp compares against. Same formula as functions/src/lib/otp.ts. */
function reviewDigest(email, code) {
  return crypto.createHash('sha256').update(`${email}\u0000${code}`).digest('hex');
}

/** Stores the review account's email and code digest. With no email, removes the account. */
async function setReviewAccount(db, { email, code }) {
  const ref = db.collection('config').doc('auth');
  if (!email) {
    await ref.set({ reviewEmail: admin.firestore.FieldValue.delete(), reviewDigest: admin.firestore.FieldValue.delete() }, { merge: true });
    return { cleared: true };
  }
  const normalized = email.trim().toLowerCase();
  if (!normalized.includes('@')) throw new Error('The review email must be an email address.');
  if (!code || code.length < 16) throw new Error('Set REVIEW_CODE to a code of at least 16 characters.');
  await ref.set({ reviewEmail: normalized, reviewDigest: reviewDigest(normalized, code.trim()) }, { merge: true });
  return { cleared: false, email: normalized };
}

module.exports = { reviewDigest, setReviewAccount };

if (require.main === module) {
  const args = process.argv.slice(2);
  const projectFlag = args.indexOf('--project');
  const emailFlag = args.indexOf('--email');
  const projectId = projectFlag >= 0 ? args[projectFlag + 1] : process.env.GCLOUD_PROJECT;
  if (!projectId) {
    console.error('Pass the Firebase project id with --project.');
    process.exit(1);
  }
  const clear = args.includes('--clear');
  const email = emailFlag >= 0 ? args[emailFlag + 1] : undefined;
  if (!clear && !email) {
    console.error('Pass --email for the review account, or --clear to remove it.');
    process.exit(1);
  }
  admin.initializeApp({ projectId });
  setReviewAccount(admin.firestore(), { email: clear ? undefined : email, code: process.env.REVIEW_CODE })
    .then((result) => {
      console.log(result.cleared ? 'Review account removed.' : `Review account set for ${result.email}.`);
    })
    .catch((error) => {
      console.error(error.message);
      process.exit(1);
    });
}
