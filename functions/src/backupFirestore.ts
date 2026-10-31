import * as functions from 'firebase-functions/v1';
import { google } from 'googleapis';

/**
 * Firestore backup scheduler — runs daily at 03:00 Asia/Dhaka.
 *
 * Exports all Firestore documents to a GCS bucket named
 * `<projectId>-firestore-backups` under a dated folder
 * `daily-backup-YYYY-MM-DD`.
 *
 * Pre-requisite: the Cloud Functions service account must have the
 * `roles/datastore.importExportAdmin` IAM role, and the GCS bucket must
 * already exist (create once via `gsutil mb gs://<projectId>-firestore-backups`).
 */
export const backupFirestore = functions
  .region('asia-south1')
  .pubsub.schedule('0 3 * * *')
  .timeZone('Asia/Dhaka')
  .onRun(async () => {
    const projectId =
      process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || '';
    const bucket = `gs://${projectId}-firestore-backups`;
    const timestamp = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    const outputUriPrefix = `${bucket}/daily-backup-${timestamp}`;

    const auth = new google.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/datastore'],
    });
    const authClient = await auth.getClient();

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const firestoreAdmin = google.firestore({
      version: 'v1',
      auth: authClient as any,
    });

    await firestoreAdmin.projects.databases.exportDocuments({
      name: `projects/${projectId}/databases/(default)`,
      requestBody: { outputUriPrefix },
    });

    console.log(`[backupFirestore] Export initiated → ${outputUriPrefix}`);
  });
