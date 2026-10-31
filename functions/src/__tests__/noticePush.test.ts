import {
  NOTICE_PUSH_TEXT_LIMIT,
  noticePushBody,
  noticePushTitle,
} from '../lib/noticePush';

describe('noticePushBody', () => {
  it('shows the notice text, which the app stores in content', () => {
    expect(noticePushBody({ content: 'Bus leaves at 6:00' })).toBe('Bus leaves at 6:00');
  });

  it('still reads a notice saved with body', () => {
    expect(noticePushBody({ body: 'Older text' })).toBe('Older text');
  });

  it('falls back to a generic line when the notice has no text', () => {
    expect(noticePushBody({ content: '   ' })).toBe('A new notice was posted.');
  });

  it('cuts long text to the push limit, ending with an ellipsis', () => {
    const body = noticePushBody({ content: 'a'.repeat(500) });
    expect(body.length).toBe(NOTICE_PUSH_TEXT_LIMIT);
    expect(body.endsWith('…')).toBe(true);
  });
});

describe('noticePushTitle', () => {
  it('puts the megaphone in front of the title', () => {
    expect(noticePushTitle({ title: 'Dinner' })).toBe('📢 Dinner');
  });

  it('falls back when the title is blank', () => {
    expect(noticePushTitle({ title: ' ' })).toBe('📢 New notice');
  });
});
