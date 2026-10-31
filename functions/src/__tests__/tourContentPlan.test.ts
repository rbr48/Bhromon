import { FieldPath, FieldValue } from 'firebase-admin/firestore';
import {
  isInTour,
  normalizeEmail,
  scrubsFor,
  updateArgs,
} from '../lib/tourContentPlan';

const LEAVER = 'leaver@x.com';

describe('normalizeEmail', () => {
  it('trims and lower-cases what the app stores as an email', () => {
    expect(normalizeEmail('  Leaver@X.com ')).toBe('leaver@x.com');
  });

  it('gives an empty string for anything that is not text', () => {
    expect(normalizeEmail(undefined)).toBe('');
    expect(normalizeEmail(42)).toBe('');
  });
});

describe('isInTour', () => {
  it('matches only documents under that tour', () => {
    expect(isInTour('tours/t1/posts/p', 't1')).toBe(true);
    expect(isInTour('tours/t10/posts/p', 't1')).toBe(false);
    expect(isInTour('trip_logs/x/comments/y', 't1')).toBe(false);
  });
});

describe('scrubsFor', () => {
  it('finds the person in likes and viewers, under any spelling', () => {
    const scrubs = scrubsFor(
      { likes: ['Leaver@X.com', 'friend@x.com'], viewers: [LEAVER] },
      LEAVER,
    );
    expect(scrubs).toEqual([
      { kind: 'arrayRemove', field: 'likes', value: 'Leaver@X.com' },
      { kind: 'arrayRemove', field: 'viewers', value: LEAVER },
    ]);
  });

  it('finds the person as a reaction, a vote and a poll vote', () => {
    const scrubs = scrubsFor(
      {
        reactions: { [LEAVER]: '😀', 'friend@x.com': '👍' },
        votes: { [LEAVER]: 1 },
        poll: { votes: { [LEAVER]: 0 } },
      },
      LEAVER,
    );
    expect(scrubs).toEqual([
      { kind: 'deleteKey', path: ['reactions', LEAVER] },
      { kind: 'deleteKey', path: ['votes', LEAVER] },
      { kind: 'deleteKey', path: ['poll', 'votes', LEAVER] },
    ]);
  });

  it('does not match an address that only starts the same way', () => {
    const scrubs = scrubsFor(
      { likes: ['leaver@x.com.au'], reactions: { 'leaver@x.com.au': '👍' } },
      LEAVER,
    );
    expect(scrubs).toEqual([]);
  });

  it('returns nothing when the person is not named', () => {
    expect(
      scrubsFor({ likes: ['friend@x.com'], viewers: [] }, LEAVER),
    ).toEqual([]);
    expect(scrubsFor({}, LEAVER)).toEqual([]);
  });
});

describe('updateArgs', () => {
  it('pairs each change with its value, keys as field paths', () => {
    const args = updateArgs([
      { kind: 'arrayRemove', field: 'likes', value: LEAVER },
      { kind: 'deleteKey', path: ['reactions', LEAVER] },
    ]);
    expect(args).toHaveLength(4);
    expect(args[0]).toBe('likes');
    expect(args[1]).toEqual(FieldValue.arrayRemove(LEAVER));
    expect(args[2]).toBeInstanceOf(FieldPath);
    expect(args[3]).toEqual(FieldValue.delete());
  });
});
