import {
  REMINDER_LEAD_MS,
  minutesUntil,
  reminderText,
  reminderWindow,
} from '../lib/noticeReminders';

const NOW = Date.UTC(2026, 9, 30, 10, 0, 0);
const MINUTE = 60 * 1000;

describe('reminderWindow', () => {
  it('covers the next half hour', () => {
    expect(REMINDER_LEAD_MS).toBe(30 * MINUTE);
    expect(reminderWindow(NOW)).toEqual({ fromMs: NOW, toMs: NOW + 30 * MINUTE });
  });
});

describe('minutesUntil', () => {
  it('gives exact minutes', () => {
    expect(minutesUntil(NOW + 20 * MINUTE, NOW)).toBe(20);
  });

  it('rounds a partial minute up', () => {
    expect(minutesUntil(NOW + 90000, NOW)).toBe(2);
  });

  it('is never below one minute while the event is still ahead', () => {
    expect(minutesUntil(NOW + 5000, NOW)).toBe(1);
  });
});

describe('reminderText', () => {
  it('names the notice, the time left and the place', () => {
    expect(reminderText({ title: 'Bus', place: 'Gate 2' }, 20)).toEqual({
      title: '⏰ Bus',
      body: 'Starts in 20 min · Gate 2',
    });
  });

  it('leaves the place out when there is none', () => {
    expect(reminderText({ title: '  ', place: '' }, 5)).toEqual({
      title: '⏰ Upcoming notice',
      body: 'Starts in 5 min',
    });
  });
});
