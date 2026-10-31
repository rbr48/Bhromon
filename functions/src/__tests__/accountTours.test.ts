import { MemberRow, nextOwnerFor } from '../lib/accountTours';

const row = (email: string, extra: Partial<MemberRow> = {}): MemberRow => ({
  email,
  status: 'active',
  role: 'member',
  joinedAtMs: 1,
  uid: null,
  ...extra,
});

describe('nextOwnerFor', () => {
  const owner = row('owner@x.com', { role: 'owner', joinedAtMs: 0 });

  it('passes the tour to the earliest-joined admin before any member', () => {
    const members = [
      owner,
      row('member@x.com', { joinedAtMs: 1 }),
      row('admin-late@x.com', { role: 'admin', joinedAtMs: 9 }),
      row('admin-early@x.com', { role: 'admin', joinedAtMs: 5 }),
    ];
    expect(nextOwnerFor(members, 'owner@x.com')).toEqual({ email: 'admin-early@x.com', uid: null });
  });

  it('falls back to the earliest-joined member when there is no admin', () => {
    const members = [
      owner,
      row('late@x.com', { joinedAtMs: 7 }),
      row('early@x.com', { joinedAtMs: 2, uid: 'uid-early' }),
    ];
    expect(nextOwnerFor(members, 'owner@x.com')).toEqual({ email: 'early@x.com', uid: 'uid-early' });
  });

  it('skips people who are only invited or no longer in the tour', () => {
    const members = [
      owner,
      row('invited@x.com', { status: 'invited', role: 'admin', joinedAtMs: 1 }),
      row('active@x.com', { joinedAtMs: 3 }),
    ];
    expect(nextOwnerFor(members, 'owner@x.com')?.email).toBe('active@x.com');
  });

  it('is null when nobody else is in the tour', () => {
    expect(nextOwnerFor([owner], 'owner@x.com')).toBeNull();
  });

  it('breaks a tie in join time by email, so the choice is the same every run', () => {
    const members = [owner, row('b@x.com', { joinedAtMs: 4 }), row('a@x.com', { joinedAtMs: 4 })];
    expect(nextOwnerFor(members, 'owner@x.com')?.email).toBe('a@x.com');
  });
});
