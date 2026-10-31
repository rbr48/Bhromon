import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { getAuth } from 'firebase-admin/auth';
jest.mock('firebase-admin/firestore', () => ({ ...jest.requireActual<object>('firebase-admin/firestore'), getFirestore: jest.fn() }));
jest.mock('firebase-admin/messaging', () => ({ ...jest.requireActual<object>('firebase-admin/messaging'), getMessaging: jest.fn() }));
jest.mock('firebase-admin/auth', () => ({ ...jest.requireActual<object>('firebase-admin/auth'), getAuth: jest.fn() }));
import { getApps, initializeApp } from 'firebase-admin/app';

if (getApps().length === 0) {
  initializeApp();
}

// ─── Shared Mock State ──────────────────────────────────────────────────────
type Membership = { tourId: string; email: string; status: string };

let memberships: Membership[] = [];
let accounts: Record<string, string> = {}; // email -> Firebase user ID
let tokens: Record<string, string> = {}; // user ID -> push token
let channels: Record<string, { name: string }> = {}; // "tourId/channelId" -> channel
let multicasts: any[] = [];

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

const fcmUser = (uid: string) => ({
  get: async () => ({
    exists: uid in tokens,
    data: () => (uid in tokens ? { token: tokens[uid] } : undefined),
  }),
  delete: async () => undefined,
  collection: () => ({ get: async () => ({ docs: [] }) }),
});

const mockDb = {
  collection: (name: string) => {
    if (name === 'memberships') return membershipQuery();
    if (name === 'fcm_tokens') return { doc: (uid: string) => fcmUser(uid) };
    if (name === 'tours') {
      return {
        doc: (tourId: string) => ({
          collection: () => ({
            doc: (channelId: string) => ({
              get: async () => ({ data: () => channels[`${tourId}/${channelId}`] }),
            }),
          }),
        }),
      };
    }
    throw new Error(`unexpected collection ${name}`);
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
    return {
      responses: msg.tokens.map(() => ({ success: true })),
      successCount: msg.tokens.length,
      failureCount: 0,
    };
  }),
};

jest.mocked(getFirestore).mockReturnValue(mockDb as any);
jest.mocked(getAuth).mockReturnValue(mockAuth as any);
jest.mocked(getMessaging).mockReturnValue(mockMessaging as any);

const { sendChannelNotification } = require('../sendChannelNotification');

const message = (data: Record<string, unknown>) => ({ data: () => data } as any);
const context = (channelId = 'general') =>
  ({ params: { tourId: 'tour_1', channelId, messageId: 'msg_1' } } as any);

describe('sendChannelNotification', () => {
  beforeEach(() => {
    memberships = [
      { tourId: 'tour_1', email: 'sender@x.com', status: 'active' },
      { tourId: 'tour_1', email: 'asha@x.com', status: 'active' },
      { tourId: 'tour_1', email: 'babu@x.com', status: 'active' },
      { tourId: 'tour_1', email: 'left@x.com', status: 'removed' },
      { tourId: 'tour_2', email: 'other@x.com', status: 'active' },
    ];
    accounts = {
      'sender@x.com': 'u_sender',
      'asha@x.com': 'u_asha',
      'babu@x.com': 'u_babu',
      'other@x.com': 'u_other',
    };
    tokens = { u_sender: 't_sender', u_asha: 't_asha', u_babu: 't_babu', u_other: 't_other' };
    channels = {
      'tour_1/general': { name: 'General' },
      'tour_1/emergency': { name: 'Emergency' },
    };
    multicasts = [];
    mockMessaging.sendEachForMulticast.mockClear();
  });

  it('pings only the members a normal channel message mentions', async () => {
    await sendChannelNotification.run(
      message({
        senderEmail: 'sender@x.com',
        senderName: 'Rina',
        text: 'Lunch at 1?',
        mentions: ['asha@x.com'],
      }),
      context('general'),
    );

    expect(multicasts).toHaveLength(1);
    expect(multicasts[0].tokens).toEqual(['t_asha']);
    expect(multicasts[0].notification).toEqual({
      title: 'Rina in General',
      body: 'Lunch at 1?',
    });
    expect(multicasts[0].data).toEqual({
      action: 'channel',
      tourId: 'tour_1',
      channelId: 'general',
      messageId: 'msg_1',
    });
  });

  it('sends nothing to a normal channel when nobody is mentioned', async () => {
    await sendChannelNotification.run(
      message({ senderEmail: 'sender@x.com', text: 'hello all', mentions: [] }),
      context('general'),
    );

    expect(mockMessaging.sendEachForMulticast).not.toHaveBeenCalled();
  });

  it('ignores mentions of people who are not active members of the tour', async () => {
    await sendChannelNotification.run(
      message({
        senderEmail: 'sender@x.com',
        text: 'hi',
        mentions: ['other@x.com', 'left@x.com'],
      }),
      context('general'),
    );

    expect(mockMessaging.sendEachForMulticast).not.toHaveBeenCalled();
  });

  it('pings every other active member of the emergency channel', async () => {
    await sendChannelNotification.run(
      message({ senderEmail: 'sender@x.com', senderName: 'Rina', text: 'Bus broke down' }),
      context('emergency'),
    );

    expect([...multicasts[0].tokens].sort()).toEqual(['t_asha', 't_babu']);
    expect(multicasts[0].notification.title).toBe('Rina in Emergency');
    expect(multicasts[0].android).toEqual({ priority: 'high' });
  });

  it('never pings the sender, even when they mention themselves', async () => {
    await sendChannelNotification.run(
      message({ senderEmail: 'sender@x.com', text: 'me', mentions: ['sender@x.com', 'asha@x.com'] }),
      context('general'),
    );

    expect(multicasts[0].tokens).toEqual(['t_asha']);
  });

  it('describes a photo or video without text', async () => {
    await sendChannelNotification.run(
      message({
        senderEmail: 'sender@x.com',
        text: '',
        mentions: ['asha@x.com'],
        attachments: [{ url: 'https://x/a.jpg', isVideo: false }],
      }),
      context('general'),
    );
    expect(multicasts[0].notification.body).toBe('📷 Photo');

    await sendChannelNotification.run(
      message({
        senderEmail: 'sender@x.com',
        text: '',
        mentions: ['asha@x.com'],
        attachments: [{ url: 'https://x/a.mp4', isVideo: true }],
      }),
      context('general'),
    );
    expect(multicasts[1].notification.body).toBe('🎬 Video');
  });

  it('describes a voice note and a video stored by their kind', async () => {
    await sendChannelNotification.run(
      message({
        senderEmail: 'sender@x.com',
        text: '',
        mentions: ['asha@x.com'],
        attachments: [{ url: 'https://x/n.m4a', kind: 'audio', durationSeconds: 12 }],
      }),
      context('general'),
    );
    expect(multicasts[0].notification.body).toBe('🎤 Voice message');

    await sendChannelNotification.run(
      message({
        senderEmail: 'sender@x.com',
        text: '',
        mentions: ['asha@x.com'],
        attachments: [{ url: 'https://x/a.mp4', kind: 'video' }],
      }),
      context('general'),
    );
    expect(multicasts[1].notification.body).toBe('🎬 Video');
  });

  it('shortens a long preview to 120 characters', async () => {
    await sendChannelNotification.run(
      message({ senderEmail: 'sender@x.com', text: 'a'.repeat(300), mentions: ['asha@x.com'] }),
      context('general'),
    );

    const body: string = multicasts[0].notification.body;
    expect(body).toHaveLength(120);
    expect(body.endsWith('…')).toBe(true);
  });
});
