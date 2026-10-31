import { FieldValue } from 'firebase-admin/firestore';
import {
  aboutPerson,
  anonymize,
  Decision,
  FORMER_MEMBER_NAME,
  formerMemberId,
  leaveClientTable,
  leaveHotelRoom,
  luggageOf,
  pairWith,
  profileOf,
  seatHeldBy,
  sosOf,
  tableNames,
} from '../lib/tourContentPlan';

const LEAVER = 'leaver@x.com';
const STAND_IN = formerMemberId('tour_1', LEAVER);

/** The fields an update changes, or none when the decision is not an update. */
function fieldsOf(decision: Decision | null): Record<string, unknown> {
  return decision?.kind === 'update' ? decision.fields : {};
}

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

describe('seats and luggage', () => {
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

});

describe('game tables', () => {
  it('names a person who hosts a table or sits at it, whatever the case of the address', () => {
    expect(tableNames({ hostEmail: LEAVER, players: [] }, LEAVER)).toBe(true);
    expect(tableNames({ hostEmail: 'friend@x.com', players: [{ email: 'Leaver@X.com' }] }, LEAVER)).toBe(true);
    expect(tableNames({ hostEmail: 'friend@x.com', players: [{ email: 'other@x.com' }] }, LEAVER)).toBe(false);
  });

  it('takes the leaver’s seat out of a table and keeps the others', () => {
    expect(
      leaveClientTable(LEAVER)({
        hostEmail: 'friend@x.com',
        players: [{ email: 'friend@x.com', isHost: true }, { email: LEAVER, isHost: false }],
      }),
    ).toEqual({
      kind: 'update',
      fields: { players: [{ email: 'friend@x.com', isHost: true }] },
    });
  });

  it('passes the host to someone still at the table, and never to a bot', () => {
    expect(
      leaveClientTable(LEAVER)({
        hostEmail: LEAVER,
        players: [
          { email: LEAVER, isHost: true },
          { email: 'bot@x.com', isBot: true, isHost: false },
          { email: 'friend@x.com', isBot: false, isHost: false },
        ],
      }),
    ).toEqual({
      kind: 'update',
      fields: {
        hostEmail: 'friend@x.com',
        players: [
          { email: 'bot@x.com', isBot: true, isHost: false },
          { email: 'friend@x.com', isBot: false, isHost: true },
        ],
      },
    });
  });

  it('ends a table with no people left, and leaves a table without the person alone', () => {
    expect(leaveClientTable(LEAVER)({ hostEmail: LEAVER, players: [{ email: LEAVER }] })).toEqual({
      kind: 'delete',
      recursive: true,
    });
    expect(
      leaveClientTable(LEAVER)({
        hostEmail: LEAVER,
        players: [{ email: LEAVER }, { email: 'bot@x.com', isBot: true }],
      }),
    ).toEqual({ kind: 'delete', recursive: true });
    expect(
      leaveClientTable(LEAVER)({ hostEmail: 'friend@x.com', players: [{ email: 'other@x.com' }] }),
    ).toBeNull();
  });
});

describe('safety alerts, voice pairs and profiles', () => {
  it('keeps an alert the person raised under the stand-in, resolved, without the location they sent', () => {
    const sos = sosOf(LEAVER, STAND_IN);
    const raised = sos(
      { senderEmail: 'Leaver@X.com', senderName: 'Rajib', latitude: 23.8, longitude: 90.4, resolved: false },
      'a1',
    );
    expect(fieldsOf(raised)).toMatchObject({
      senderEmail: STAND_IN,
      senderName: FORMER_MEMBER_NAME,
      resolved: true,
      resolvedByEmail: STAND_IN,
    });
    expect(fieldsOf(raised).latitude).toEqual(FieldValue.delete());
    expect(fieldsOf(raised).longitude).toEqual(FieldValue.delete());
    expect(fieldsOf(raised)).toHaveProperty('resolvedAt');
  });

  it('keeps the resolution of an alert the person raised, with the stand-in in place of the person', () => {
    const sos = sosOf(LEAVER, STAND_IN);
    expect(
      fieldsOf(sos({ senderEmail: LEAVER, resolved: true, resolvedByEmail: LEAVER }, 'a2')),
    ).toMatchObject({ resolvedByEmail: STAND_IN });

    const resolvedByAdmin = fieldsOf(
      sos({ senderEmail: LEAVER, resolved: true, resolvedByEmail: 'admin@x.com' }, 'a3'),
    );
    expect(resolvedByAdmin).not.toHaveProperty('resolvedByEmail');
    expect(resolvedByAdmin).not.toHaveProperty('resolved');
  });

  it('keeps an alert of another member, and takes the person out of who resolved it', () => {
    const sos = sosOf(LEAVER, STAND_IN);
    expect(sos({ senderEmail: 'friend@x.com', resolvedByEmail: LEAVER }, 'a4')).toEqual({
      kind: 'update',
      fields: { resolvedByEmail: STAND_IN },
    });
    expect(sos({ senderEmail: 'friend@x.com' }, 'a5')).toBeNull();
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
