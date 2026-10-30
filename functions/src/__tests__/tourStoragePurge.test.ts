import { purgeTourStorage, StorageBucketLike } from '../lib/tourStorage';

interface FakeFile {
  name: string;
  uploadedByEmail?: string;
}

/** A bucket that lists the given files, and records what is asked of it. */
function fakeBucket(files: FakeFile[]) {
  const queries: string[] = [];
  const deleted: string[] = [];
  const bucket: StorageBucketLike = {
    getFiles: async ({ prefix }) => {
      queries.push(prefix);
      const listed = files.map((file) => ({
        getMetadata: async () =>
          [
            {
              metadata:
                file.uploadedByEmail === undefined
                  ? undefined
                  : { uploadedByEmail: file.uploadedByEmail },
            },
          ] as [{ metadata?: Record<string, unknown> }],
        delete: async () => {
          deleted.push(file.name);
          return [];
        },
      }));
      return [listed] as [typeof listed];
    },
  };
  return { bucket, queries, deleted };
}

const FILES: FakeFile[] = [
  { name: 'tours/t1/posts/a.jpg', uploadedByEmail: 'Leaver@X.com' },
  { name: 'tours/t1/posts/b.jpg', uploadedByEmail: 'friend@x.com' },
  { name: 'tours/t1/channels/legacy.jpg' },
];

describe('purgeTourStorage', () => {
  it('removes only the files the person uploaded, matched without regard to case', async () => {
    const { bucket, queries, deleted } = fakeBucket(FILES);

    await purgeTourStorage(bucket, 't1', 'leaver@x.com');

    expect(queries).toEqual(['tours/t1/']);
    expect(deleted).toEqual(['tours/t1/posts/a.jpg']);
  });

  it('removes every file of the tour when there is no uploader to match', async () => {
    const { bucket, deleted } = fakeBucket(FILES);

    await purgeTourStorage(bucket, 't1', null);

    expect(deleted).toEqual(FILES.map((file) => file.name));
  });
});
