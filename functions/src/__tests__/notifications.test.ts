import * as admin from 'firebase-admin';

// Initialize mock app for tests
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// ─── Shared Mock State ──────────────────────────────────────────────────────
let sentMessages: any[] = [];
let dbWrites: Record<string, any[]> = {};
let fcmTokens: Record<string, string> = {
  'recipient_123': 'token_recipient_123',
  'user_456': 'token_user_456',
  'pioneer_1': 'token_pioneer_1',
};
let explorerProfiles: Record<string, any> = {
  'sender_789': { displayName: 'John Doe', tier: 'verified' },
  'pioneer_1': { displayName: 'Pioneer Explorer', tier: 'pioneer' },
};

const mockDb = {
  collection: (collectionName: string) => {
    return {
      doc: (docId: string) => ({
        get: async () => {
          if (collectionName === 'fcm_tokens') {
            const token = fcmTokens[docId];
            return {
              exists: !!token,
              data: () => (token ? { token } : null),
            };
          }
          if (collectionName === 'explorer_profiles') {
            const profile = explorerProfiles[docId];
            return {
              exists: !!profile,
              data: () => (profile ? { displayName: profile.displayName, tier: profile.tier } : null),
            };
          }
          if (collectionName === 'chats') {
            if (docId === 'chat_123') {
              return {
                exists: true,
                data: () => ({ participants: ['sender_789', 'recipient_123'] }),
              };
            }
          }
          return { exists: false };
        },
        collection: (subName: string) => ({
          add: async (data: any) => {
            const path = `${collectionName}/${docId}/${subName}`;
            if (!dbWrites[path]) {
              dbWrites[path] = [];
            }
            dbWrites[path].push(data);
            return { id: 'mock_sub_id' };
          },
        }),
      }),
      get: async () => {
        if (collectionName === 'fcm_tokens') {
          return {
            forEach: (cb: (doc: any) => void) => {
              Object.keys(fcmTokens).forEach(uid => {
                cb({ data: () => ({ token: fcmTokens[uid] }) });
              });
            },
          };
        }
        return { forEach: () => {} };
      },
      where: (field: string, op: string, value: any) => {
        return {
          get: async () => {
            if (collectionName === 'explorer_profiles' && field === 'tier') {
              const matches = Object.keys(explorerProfiles)
                .filter(uid => explorerProfiles[uid].tier === value)
                .map(uid => ({ id: uid, data: () => explorerProfiles[uid] }));
              return {
                forEach: (cb: (doc: any) => void) => matches.forEach(cb),
                docs: matches,
              };
            }
            if (collectionName === 'fcm_tokens') {
              const matchedTokens = value
                .filter((uid: string) => fcmTokens[uid])
                .map((uid: string) => ({ id: uid, data: () => ({ token: fcmTokens[uid] }) }));
              return {
                forEach: (cb: (doc: any) => void) => matchedTokens.forEach(cb),
                docs: matchedTokens,
              };
            }
            return { forEach: () => {}, docs: [] };
          },
        };
      },
    };
  },
};

// Global mock of firestore and messaging BEFORE importing modules
jest.spyOn(admin, 'firestore' as any).mockReturnValue(mockDb as any);
(admin.firestore as any).FieldValue = {
  serverTimestamp: () => 'mock-server-timestamp',
};
(admin.firestore as any).FieldPath = {
  documentId: () => ({
    toString: () => '__name__'
  })
};
jest.spyOn(admin, 'messaging' as any).mockReturnValue({
  send: jest.fn().mockImplementation(async (msg) => {
    sentMessages.push(msg);
    return 'mock_message_id';
  }),
  sendEachForMulticast: jest.fn().mockImplementation(async (msg) => {
    sentMessages.push(msg);
    return { successCount: msg.tokens.length, failureCount: 0 };
  }),
} as any);

const { sendGeneralNotification } = require('../sendGeneralNotification');
const { sendChatNotification } = require('../sendChatNotification');
const { sendBroadcastNotification } = require('../sendBroadcastNotification');

describe('Push Notifications Cloud Functions', () => {
  beforeEach(() => {
    sentMessages = [];
    dbWrites = {};
  });

  describe('sendGeneralNotification', () => {
    it('sends FCM push notification to the user token when general notification is created', async () => {
      const snap = {
        data: () => ({
          title: 'Tier Upgraded',
          body: 'Congratulations! You are now a Verified Explorer.',
          action: 'tier_upgrade',
          uid: 'user_456',
        }),
        exists: true,
      };

      await sendGeneralNotification.run(snap as any, { params: { userId: 'user_456', notificationId: 'notif_1' } } as any);

      expect(sentMessages.length).toBe(1);
      expect(sentMessages[0]).toEqual(expect.objectContaining({
        token: 'token_user_456',
        notification: {
          title: 'Tier Upgraded',
          body: 'Congratulations! You are now a Verified Explorer.',
        },
        data: {
          action: 'tier_upgrade',
          uid: 'user_456',
          itemId: '',
        },
      }));
    });

    it('ignores notifications with action "chat" (they are handled by sendChatNotification)', async () => {
      const snap = {
        data: () => ({
          title: 'New Chat',
          body: 'Hello',
          action: 'chat',
        }),
        exists: true,
      };

      await sendGeneralNotification.run(snap as any, { params: { userId: 'user_456', notificationId: 'notif_2' } } as any);
      expect(sentMessages.length).toBe(0);
    });
  });

  describe('sendChatNotification', () => {
    it('writes in-app notification to db and sends FCM push notification for new messages', async () => {
      const snap = {
        data: () => ({
          senderId: 'sender_789',
          text: 'Are we still going to Sajek tomorrow?',
        }),
        exists: true,
      };

      await sendChatNotification.run(snap as any, { params: { chatId: 'chat_123', messageId: 'msg_999' } } as any);

      // Verify db in-app notification write
      expect(dbWrites['users/recipient_123/notifications']).toBeDefined();
      expect(dbWrites['users/recipient_123/notifications'][0]).toEqual(expect.objectContaining({
        title: 'New message from John Doe',
        body: 'Are we still going to Sajek tomorrow?',
        action: 'chat',
        uid: 'sender_789',
      }));

      // Verify FCM push message sent
      expect(sentMessages.length).toBe(1);
      expect(sentMessages[0].tokens).toContain('token_recipient_123');
      expect(sentMessages[0]).toEqual(expect.objectContaining({
        notification: {
          title: 'New message from John Doe',
          body: 'Are we still going to Sajek tomorrow?',
        },
        // data gained chatId/messageType when chat deep-links were added
        data: expect.objectContaining({
          action: 'chat',
          uid: 'sender_789',
          itemId: 'chat_123',
          chatId: 'chat_123',
        }),
      }));
    });
    it('does not notify anyone about a call log', async () => {
      const snap = {
        data: () => ({
          senderId: 'sender_789',
          type: 'call',
          callStatus: 'ended',
          durationSeconds: 192,
        }),
        exists: true,
      };

      await sendChatNotification.run(snap as any, { params: { chatId: 'chat_123', messageId: 'msg_1000' } } as any);

      expect(sentMessages).toHaveLength(0);
      expect(dbWrites['users/recipient_123/notifications']).toBeUndefined();
    });
  });

  describe('sendBroadcastNotification', () => {
    it('sends multicast broadcast to all users when target is "all"', async () => {
      const snap = {
        data: () => ({
          title: 'System Maintenance',
          body: 'We will be offline for 2 hours tonight.',
          target: 'all',
        }),
        exists: true,
      };

      await sendBroadcastNotification.run(snap as any, { params: { notifId: 'broadcast_1' } } as any);

      expect(sentMessages.length).toBe(1);
      expect(sentMessages[0].tokens).toContain('token_recipient_123');
      expect(sentMessages[0].tokens).toContain('token_user_456');
      expect(sentMessages[0].notification.title).toBe('System Maintenance');
    });

    it('filters broadcast receivers by target tier', async () => {
      const snap = {
        data: () => ({
          title: 'Pioneer Meeting',
          body: 'Exclusive event details for Pioneers.',
          target: 'pioneer',
        }),
        exists: true,
      };

      await sendBroadcastNotification.run(snap as any, { params: { notifId: 'broadcast_2' } } as any);

      expect(sentMessages.length).toBe(1);
      expect(sentMessages[0].notification.title).toBe('Pioneer Meeting');
    });
  });
});
