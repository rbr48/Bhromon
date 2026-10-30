import { normalizeEmail } from './tourContentPlan';

/**
 * The Storage files a tour's members upload to its folder, and their removal.
 * Kept apart from the purge itself, so the rule that picks a person's files can
 * be tested on its own.
 */

/** The part of a Storage bucket the purge uses. */
export interface StorageBucketLike {
  getFiles(query: { prefix: string }): Promise<
    [
      Array<{
        getMetadata(): Promise<[{ metadata?: Record<string, unknown> }, ...unknown[]]>;
        delete(options?: { ignoreNotFound?: boolean }): Promise<unknown>;
      }>,
      ...unknown[],
    ]
  >;
}

/**
 * Removes the files in the tour's Storage folder that [uploaderEmail] uploaded
 * (every file when it is null). Only uploads that name their uploader can be
 * matched to a person, as with the media server.
 */
export async function purgeTourStorage(
  bucket: StorageBucketLike,
  tourId: string,
  uploaderEmail: string | null,
): Promise<void> {
  const [files] = await bucket.getFiles({ prefix: `tours/${tourId}/` });
  for (const file of files) {
    if (uploaderEmail !== null) {
      const [info] = await file.getMetadata();
      if (normalizeEmail(info.metadata?.uploadedByEmail) !== uploaderEmail) continue;
    }
    await file.delete({ ignoreNotFound: true });
  }
}
