// Gives every tour that still has a six-character invite code a new eight-character
// one. The rules no longer look up six-character codes, so run this before the new
// rules are deployed, or those tours' invite links stop working.
//
// Dry run by default. It counts what it would change and changes nothing. Pass --apply
// to change it.
//
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node functions/scripts/upgradeLegacyInviteCodes.js --project bhromon-ff801
//   ...then add --apply to change it.
const crypto = require('crypto');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

// The same alphabet and length as lib/features/tour_group/domain/services/invite_code.dart.
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 8;

/** A new code from a secure source. */
function newInviteCode() {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += ALPHABET[crypto.randomInt(ALPHABET.length)];
  }
  return code;
}

/** The invite documents whose id is not an eight-character code. */
async function findLegacyInvites(db) {
  const invites = await db.collection('invites').get();
  return invites.docs.filter((doc) => doc.id.length !== CODE_LENGTH);
}

/**
 * Moves each legacy invite to a new code: writes the new invite, points the tour at it,
 * and deletes the old invite. Returns how many were found and how many were moved.
 */
async function upgradeLegacyInviteCodes(db, { apply }) {
  const legacy = await findLegacyInvites(db);
  if (!apply) return { found: legacy.length, moved: 0 };

  let moved = 0;
  for (const invite of legacy) {
    const tourId = invite.get('tourId');
    if (typeof tourId !== 'string' || tourId === '') continue;

    let code = newInviteCode();
    while ((await db.collection('invites').doc(code).get()).exists) code = newInviteCode();

    const batch = db.batch();
    batch.set(db.collection('invites').doc(code), { tourId, code });
    batch.update(db.collection('tours').doc(tourId), { inviteCode: code });
    batch.delete(invite.ref);
    await batch.commit();
    moved += 1;
  }
  return { found: legacy.length, moved };
}

module.exports = { findLegacyInvites, upgradeLegacyInviteCodes, newInviteCode };

if (require.main === module) {
  const args = process.argv.slice(2);
  const apply = args.includes('--apply');
  const projectFlag = args.indexOf('--project');
  const projectId = projectFlag >= 0 ? args[projectFlag + 1] : process.env.GCLOUD_PROJECT;
  if (!projectId) {
    console.error('Pass the Firebase project id with --project.');
    process.exit(1);
  }
  initializeApp({ projectId });
  upgradeLegacyInviteCodes(getFirestore(), { apply })
    .then(({ found, moved }) => {
      console.log(
        apply
          ? `Moved ${moved} of ${found} legacy invite codes to eight-character codes.`
          : `Dry run: ${found} legacy invite codes would be moved. Add --apply to move them.`,
      );
    })
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
