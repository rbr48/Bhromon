import {
  aboutPerson,
  anonymize,
  FORMER_MEMBER_NAME,
  formerMemberId,
  gameInvolves,
  leaveHotelRoom,
  luggageOf,
  pairWith,
  profileOf,
  seatHeldBy,
  sosOf,
} from '../lib/tourContentPlan';

const LEAVER = 'leaver@x.com';
const STAND_IN = formerMemberId('tour_1', LEAVER);

describe('formerMemberId', () => {
  it('is the same for the same person in the same tour, whatever the case', () => {
    expect(formerMemberId('tour_1', 'Leaver@X.com')).toBe(formerMemberId('tour_1', LEAVER));
  });

  it('differs between tours and between people, and does not show the address', () => {
    expect(formerMemberId('tour_2', LEAVER)).not.toBe(STAND_IN);
    expect(formerMemberId('tour_1', 'other@x.com')).not.toBe(STAND_IN);
    expect(STAND_IN.startsWith('former-')).toBe(true);
    expect(STAND_IN).not.toContain('leaver');
  });
});

describe('anonymize', () => {
  const ledger = anonymize(
    {
      emails: ['addedByEmail', 'paidById'],
      names: { paidById: 'paidByName' },
      lists: ['participantIds'],
      maps: ['splitShares'],
    },
    LEAVER,
    STAND_IN,
  );

  it('replaces the person in an expense and keeps every amount', () => {
    const decision = ledger({
      addedByEmail: 'Leaver@X.com',
      paidById: 'leaver@x.com',
      paidByName: 'Rajib',
      participantIds: ['leaver@x.com', 'friend@x.com'],
      splitShares: { 'Leaver@x.com': 300, 'friend@x.com': 200 },
      amountPaisa: 500,
      title: 'Lunch',
    }, 'e1');

    expect(decision).toEqual({
      kind: 'update',
      fields: {
        addedByEmail: STAND_IN,
        paidById: STAND_IN,
        paidByName: FORMER_MEMBER_NAME,
        participantIds: [STAND_IN, 'friend@x.com'],
        splitShares: { [STAND_IN]: 300, 'friend@x.com': 200 },
      },
    });
  });

  it('leaves a record alone when the person is not named in it', () => {
    expect(
      ledger({ addedByEmail: 'friend@x.com', paidById: null, amountPaisa: 5 }, 'e2'),
    ).toBeNull();
  });

  it('takes the person out of the lists it is removed from, and keeps the rest', () => {
    const checklist = anonymize({ removeFromLists: ['checkedBy'] }, LEAVER, STAND_IN);
    expect(checklist({ checkedBy: [LEAVER, 'friend@x.com'] }, 'c1')).toEqual({
      kind: 'update',
      fields: { checkedBy: ['friend@x.com'] },
    });
  });

  it('names a notice author by the label and takes the person out of the acknowledgements', () => {
    const notice = anonymize(
      {
        emails: ['authorEmail'],
        names: { authorEmail: 'author' },
        removeFromLists: ['ackBy'],
      },
      LEAVER,
      STAND_IN,
    );
    expect(
      notice({ authorEmail: LEAVER, author: 'Rajib', ackBy: [LEAVER, 'friend@x.com'] }, 'n1'),
    ).toEqual({
      kind: 'update',
      fields: {
        authorEmail: STAND_IN,
        author: FORMER_MEMBER_NAME,
        ackBy: ['friend@x.com'],
      },
    });
  });

  it('keeps a deposit or transfer amount, with the names of both sides replaced', () => {
    const deposit = anonymize(
      { emails: ['addedByEmail', 'memberId'], names: { memberId: 'memberName' } },
      LEAVER,
      STAND_IN,
    );
    expect(
      deposit({ addedByEmail: 'friend@x.com', memberId: LEAVER, memberName: 'Rajib', amountPaisa: 100 }, 'd1'),
    ).toEqual({
      kind: 'update',
      fields: { memberId: STAND_IN, memberName: FORMER_MEMBER_NAME },
    });

    const transfer = anonymize(
      {
        emails: ['addedByEmail', 'fromId', 'toId'],
        names: { fromId: 'fromName', toId: 'toName' },
      },
      LEAVER,
      STAND_IN,
    );
    expect(
      transfer({ addedByEmail: LEAVER, fromId: LEAVER, fromName: 'Rajib', toId: 'friend@x.com', toName: 'Friend' }, 't1'),
    ).toEqual({
      kind: 'update',
      fields: {
        addedByEmail: STAND_IN,
        fromId: STAND_IN,
        fromName: FORMER_MEMBER_NAME,
      },
    });
  });
});

describe('leaveHotelRoom', () => {
  it('takes the person out of both guest lists at the same position', () => {
    expect(
      leaveHotelRoom(LEAVER)({
        assignedMemberEmails: ['a@x.com', LEAVER, 'c@x.com'],
        assignedMemberNames: ['A', 'Leaver', 'C'],
      }),
    ).toEqual({
      kind: 'update',
      fields: {
        assignedMemberEmails: ['a@x.com', 'c@x.com'],
        assignedMemberNames: ['A', 'C'],
      },
    });
  });

  it('keeps the lists short when a name is missing, and leaves a room without them alone', () => {
    expect(
      leaveHotelRoom(LEAVER)({
        assignedMemberEmails: [LEAVER, 'b@x.com'],
        assignedMemberNames: ['Leaver'],
      }),
    ).toEqual({
      kind: 'update',
      fields: { assignedMemberEmails: ['b@x.com'], assignedMemberNames: [] },
    });
    expect(leaveHotelRoom(LEAVER)({ assignedMemberEmails: ['a@x.com'] })).toBeNull();
  });
});

describe('seats, luggage and game tables', () => {
  it('frees a seat the person holds, whatever the case of the address', () => {
    expect(seatHeldBy(LEAVER)({ assignedMemberEmail: 'Leaver@X.com' }, 's1')).toEqual({
      kind: 'delete',
      recursive: false,
    });
    expect(seatHeldBy(LEAVER)({ assignedMemberEmail: 'friend@x.com' }, 's2')).toBeNull();
  });

  it('removes luggage the person owns, and clears the custody they held', () => {
    const luggage = luggageOf(LEAVER);
    expect(luggage({ ownerEmail: LEAVER }, 'l1')).toEqual({ kind: 'delete' });
    expect(
      luggage({ ownerEmail: 'friend@x.com', custodianEmail: 'Leaver@X.com', custodianName: 'Rajib' }, 'l2'),
    ).toEqual({
      kind: 'update',
      fields: { custodianEmail: null, custodianName: null },
    });
    expect(luggage({ ownerEmail: 'friend@x.com' }, 'l3')).toBeNull();
  });

  it('ends a game table the person hosts or sits at, with its seats', () => {
    const game = gameInvolves(LEAVER);
    expect(game({ hostEmail: LEAVER, players: [] }, 'g1')).toEqual({
      kind: 'delete',
      recursive: true,
    });
    expect(game({ hostEmail: 'friend@x.com', players: [{ email: LEAVER }] }, 'g2')).toEqual({
      kind: 'delete',
      recursive: true,
    });
    expect(game({ hostEmail: 'friend@x.com', players: [{ email: 'other@x.com' }] }, 'g3')).toBeNull();
  });
});

describe('safety alerts, voice pairs and profiles', () => {
  it('removes an alert the person raised and keeps the stand-in on one they resolved', () => {
    const sos = sosOf(LEAVER, STAND_IN);
    expect(sos({ senderEmail: LEAVER }, 'a1')).toEqual({ kind: 'delete' });
    expect(sos({ senderEmail: 'friend@x.com', resolvedByEmail: LEAVER }, 'a2')).toEqual({
      kind: 'update',
      fields: { resolvedByEmail: STAND_IN },
    });
    expect(sos({ senderEmail: 'friend@x.com' }, 'a3')).toBeNull();
  });

  it('removes a voice pair that names the person, with its candidates', () => {
    const pair = pairWith(LEAVER);
    expect(pair({}, 'friend@x.com__leaver@x.com')).toEqual({ kind: 'delete', recursive: true });
    expect(pair({}, 'friend@x.com__other@x.com')).toBeNull();
  });

  it('removes the person\'s location, telemetry or legacy row by its key or email', () => {
    const about = aboutPerson(LEAVER);
    expect(about({ lat: 1 }, LEAVER)?.kind).toBe('delete');
    expect(about({ email: 'Leaver@X.com' }, 'row1')?.kind).toBe('delete');
    expect(about({ email: 'friend@x.com' }, 'friend@x.com')).toBeNull();
  });

  it('removes a profile by the account id or the email, and keeps the others', () => {
    expect(profileOf(LEAVER, 'uid_1')({ uid: 'uid_1' }, 'p1')?.kind).toBe('delete');
    expect(profileOf(LEAVER, null)({ email: LEAVER }, 'p2')?.kind).toBe('delete');
    expect(profileOf(LEAVER, null)({ uid: 'other' }, 'other')).toBeNull();
  });
});
