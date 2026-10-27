import * as admin from 'firebase-admin';

// Initialize mock app for tests
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// ─── Shared Mock State ──────────────────────────────────────────────────────
type Membership = { tourId: string; email: string; status: string };

let memberships: Membership[] = [];
let accounts: Record<string, string> = {}; // email -> Firebase user ID
let tokens: Record<string, string> = {}; // user ID -> legacy single push token
let devices: Record<string, string[]> = {}; // user ID -> tokens of each signed-in device
let deadTokens: string[] = []; // tokens FCM reports as no longer registered
let deleted: string[] = []; // document paths the function removed
let multicasts: any[] = [];

/** A chainable query over the memberships list. */
function membershipQuery(filters: Record<string, string> = {}): any {
  return {
    where: (field: string, _op: string, value: string) =>
      membershipQuery({ ...filters, [field]: value }),
    get: async () => {
      const rows = memberships.filter((m) =>
        Object.entries(filters).every(([field, value]) => (m as any)[field] === value),
      );
      return { docs: rows.map((m) => ({ data: () => m })) };
    },
  };
}

/** A document reference that records its own deletion. */
function ref(path: string): any {
  return { path, delete: async () => void deleted.push(path) };
}

/** fcm_tokens/{uid}: the legacy token, plus one document per device. */
function fcmUser(uid: string): any {
  return {
    ...ref(`fcm_tokens/${uid}`),
    get: async () => ({
      exists: uid in tokens,
      data: () => (uid in tokens ? { token: tokens[uid] } : undefined),
    }),
    collection: (name: string) => ({
      get: async () => ({
        docs: (devices[uid] ?? []).map((token, i) => ({
          data: () => ({ token }),
          ref: ref(`fcm_tokens/${uid}/${name}/${i}`),
        })),
      }),
    }),
  };
}

const mockDb = {
  collection: (name: string) => {
    if (name === 'memberships') return membershipQuery();
    return { doc: (id: string) => (name === 'fcm_tokens' ? fcmUser(id) : ref(`${name}/${id}`)) };
  },
};

const mockAuth = {
  getUsers: jest.fn(async (identifiers: Array<{ email: string }>) => ({
    users: identifiers.filter((i) => i.email in accounts).map((i) => ({ uid: accounts[i.email] })),
    notFound: identifiers.filter((i) => !(i.email in accounts)),
  })),
};

const mockMessaging = {
  sendEachForMulticast: jest.fn(async (msg: any) => {
    multicasts.push(msg);
    const responses = msg.tokens.map((t: string) =>
      deadTokens.includes(t)
        ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
        : { success: true },
    );
    return {
      responses,
      successCount: responses.filter((r: any) => r.success).length,
      failureCount: responses.filter((r: any) => !r.success).length,
    };
  }),
};

// Install the mocks before the module reads admin.firestore() at load time.
jest.spyOn(admin, 'firestore' as any).mockReturnValue(mockDb as any);
jest.spyOn(admin, 'auth' as any).mockReturnValue(mockAuth as any);
jest.spyOn(admin, 'messaging' as any).mockReturnValue(mockMessaging as any);

const { sendSosAlert } = require('../sendSosAlert');

const alert = (data: Record<string, unknown>) => ({ data: () => data } as any);
const context = (tourId = 'tour_1', alertId = 'alert_1') =>
  ({ params: { tourId, alertId } } as any);

describe('sendSosAlert', () => {
  beforeEach(() => {
    memberships = [
      { tourId: 'tour_1', email: 'sender@x.com', status: 'active' },
      { tourId: 'tour_1', email: 'asha@x.com', status: 'active' },
      { tourId: 'tour_1', email: 'babu@x.com', status: 'active' },
      { tourId: 'tour_1', email: 'left@x.com', status: 'invited' },
      { tourId: 'tour_2', email: 'other@x.com', status: 'active' },
    ];
    accounts = {
      'sender@x.com': 'u_sender',
      'asha@x.com': 'u_asha',
      'babu@x.com': 'u_babu',
      'other@x.com': 'u_other',
    };
    tokens = { u_sender: 't_sender', u_asha: 't_asha', u_babu: 't_babu', u_other: 't_other' };
    devices = {};
    deadTokens = [];
    deleted = [];
    multicasts = [];
    mockAuth.getUsers.mockClear();
    mockMessaging.sendEachForMulticast.mockClear();
  });

  it('pushes to every other active member of the tour, and no one else', async () => {
    await sendSosAlert.run(
      alert({ senderEmail: 'sender@x.com', senderName: 'Rina' }),
      context(),
    );

    expect(multicasts).toHaveLength(1);
    expect([...multicasts[0].tokens].sort()).toEqual(['t_asha', 't_babu']);
    expect(multicasts[0].notification.title).toBe('SOS from Rina');
    expect(multicasts[0].data).toEqual({
      action: 'sos',
      type: 'sos',
      tourId: 'tour_1',
      alertId: 'alert_1',
    });
  });

  it('reaches every device a member has signed in on, sending each token once', async () => {
    devices = { u_asha: ['t_asha', 't_asha_tablet'] };

    await sendSosAlert.run(alert({ senderEmail: 'sender@x.com', senderName: 'Rina' }), context());

    expect([...multicasts[0].tokens].sort()).toEqual(['t_asha', 't_asha_tablet', 't_babu']);
  });

  it('removes a token FCM reports as dead, and keeps the others', async () => {
    devices = { u_asha: ['t_asha_old'] };
    deadTokens = ['t_asha_old'];

    await sendSosAlert.run(alert({ senderEmail: 'sender@x.com', senderName: 'Rina' }), context());

    expect(deleted).toEqual(['fcm_tokens/u_asha/devices/0']);
  });

  it('skips members with no account or no device token', async () => {
    delete accounts['babu@x.com'];

    await sendSosAlert.run(alert({ senderEmail: 'sender@x.com', senderName: 'Rina' }), context());

    expect(multicasts).toHaveLength(1);
    expect(multicasts[0].tokens).toEqual(['t_asha']);
  });

  it('sends nothing when no other member can receive it', async () => {
    // Asha has an account but no token; Babu has no account at all.
    delete accounts['babu@x.com'];
    delete tokens.u_asha;

    await sendSosAlert.run(alert({ senderEmail: 'sender@x.com', senderName: 'Rina' }), context());

    expect(mockMessaging.sendEachForMulticast).not.toHaveBeenCalled();
  });

  it('sends nothing when the sender is the only active member', async () => {
    memberships = [{ tourId: 'tour_1', email: 'sender@x.com', status: 'active' }];

    await sendSosAlert.run(alert({ senderEmail: 'sender@x.com', senderName: 'Rina' }), context());

    expect(mockAuth.getUsers).not.toHaveBeenCalled();
    expect(mockMessaging.sendEachForMulticast).not.toHaveBeenCalled();
  });

  it('does nothing for an alert with no sender email', async () => {
    await sendSosAlert.run(alert({ senderName: 'Rina' }), context());

    expect(mockMessaging.sendEachForMulticast).not.toHaveBeenCalled();
  });

  it('uses a generic name when the alert has none', async () => {
    await sendSosAlert.run(alert({ senderEmail: 'sender@x.com' }), context());

    expect(multicasts[0].notification.title).toBe('SOS from A member');
  });

  it('looks up accounts in batches of 100', async () => {
    memberships = [
      { tourId: 'tour_1', email: 'sender@x.com', status: 'active' },
      ...Array.from({ length: 120 }, (_, i) => ({
        tourId: 'tour_1',
        email: `m${i}@x.com`,
        status: 'active',
      })),
    ];
    for (let i = 0; i < 120; i++) {
      accounts[`m${i}@x.com`] = `u_m${i}`;
      tokens[`u_m${i}`] = `t_m${i}`;
    }

    await sendSosAlert.run(alert({ senderEmail: 'sender@x.com', senderName: 'Rina' }), context());

    expect(mockAuth.getUsers).toHaveBeenCalledTimes(2);
    expect(multicasts[0].tokens).toHaveLength(120);
  });
});
