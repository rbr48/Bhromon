/**
 * Family dates: birthdays, bills, school and medicine times that a family
 * circle keeps, and when each one reminds people. Pure functions, so the
 * reminder rules are tested without Firestore or FCM.
 *
 * Every day is a `YYYY-MM-DD` string. The app computes the same rules in Dart
 * (`family_date_rules.dart`), and both sides test the same examples.
 */

export type FamilyRecurrence = 'once' | 'monthly' | 'yearly';

/** Dhaka is UTC+6 all year, with no daylight saving, so a fixed offset is exact. */
const DHAKA_OFFSET_MS = 6 * 60 * 60 * 1000;

/** A reminder sends at most this many occurrences in one run. Bounds the loop. */
const MAX_STEPS = 10;

const DAY_KEY = /^\d{4}-\d{2}-\d{2}$/;

/** The Dhaka calendar day of [nowMs], as `YYYY-MM-DD`. */
export function dhakaDayKey(nowMs: number): string {
  return new Date(nowMs + DHAKA_OFFSET_MS).toISOString().slice(0, 10);
}

/** Days from [fromKey] to [toKey]: positive when [toKey] is later. */
export function daysBetween(fromKey: string, toKey: string): number {
  const ms = dayMs(toKey) - dayMs(fromKey);
  return Math.round(ms / 86400000);
}

/** The day [days] after [key], as `YYYY-MM-DD`. */
export function addDays(key: string, days: number): string {
  return new Date(dayMs(key) + days * 86400000).toISOString().slice(0, 10);
}

function dayMs(key: string): number {
  const [y, m, d] = key.split('-').map(Number);
  return Date.UTC(y, m - 1, d);
}

function daysInMonth(year: number, month: number): number {
  // Month is 1-based here. Day 0 of the next month is the last day of this one.
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/**
 * The first occurrence on or after [fromKey]. A monthly date keeps its day of the
 * month, and a yearly date its month and day. A day the month does not have (the
 * 31st in April, 29 February in a common year) falls on the month's last day.
 * A one-time date is always [startOn], whether or not it has passed.
 */
export function occurrenceOnOrAfter(
  startOn: string,
  recurrence: FamilyRecurrence,
  fromKey: string,
): string {
  if (recurrence === 'once') return startOn;
  const [, sm, sd] = startOn.split('-').map(Number);
  const [fy, fm] = fromKey.split('-').map(Number);

  if (recurrence === 'monthly') {
    for (let step = 0; step < 2; step++) {
      const total = fy * 12 + (fm - 1) + step;
      const year = Math.floor(total / 12);
      const month = (total % 12) + 1;
      const day = Math.min(sd, daysInMonth(year, month));
      const candidate = format(year, month, day);
      if (candidate >= fromKey) return candidate;
    }
  }

  // Yearly: this year first, then the next one.
  for (let step = 0; step < 2; step++) {
    const year = fy + step;
    const day = Math.min(sd, daysInMonth(year, sm));
    const candidate = format(year, sm, day);
    if (candidate >= fromKey) return candidate;
  }
  // Unreachable for valid keys, kept so the function always returns.
  return startOn;
}

function format(year: number, month: number, day: number): string {
  return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

/** The fields the reminder job reads from a family date. */
export interface FamilyDateRecord {
  title?: unknown;
  kind?: unknown;
  recurrence?: unknown;
  startOn?: unknown;
  nextOn?: unknown;
  remindDays?: unknown;
  remindOn?: unknown;
}

/** One reminder to send, and how many days before the date it falls. */
export interface PlannedReminder {
  daysLeft: number;
}

/** What the job does with one family date: reminders to send, and the new schedule. */
export interface ReminderPlan {
  reminders: PlannedReminder[];
  update: { nextOn: string; remindOn: string | null };
}

/**
 * Works out the reminders a family date is due at [today], and its next schedule.
 * Returns null when nothing is due.
 *
 * A reminder is due once `remindOn` is today or earlier. Each occurrence gets at
 * most one reminder, and an occurrence that has already passed gets none. A
 * recurring date then moves on to its next occurrence, which is the one after
 * the date just handled, or the first one from today when this one has passed.
 * A one-time date stops after its reminder.
 */
export function planFamilyDateReminders(
  record: FamilyDateRecord,
  today: string,
): ReminderPlan | null {
  const startOn = validDay(record.startOn);
  const nextOn = validDay(record.nextOn);
  const remindOn = validDay(record.remindOn);
  const remindDays = typeof record.remindDays === 'number' ? record.remindDays : NaN;
  const recurrence = record.recurrence;
  if (
    !startOn ||
    !nextOn ||
    !remindOn ||
    remindOn > today ||
    !Number.isInteger(remindDays) ||
    (recurrence !== 'once' && recurrence !== 'monthly' && recurrence !== 'yearly')
  ) {
    return null;
  }

  const reminders: PlannedReminder[] = [];
  let current = nextOn;

  if (recurrence === 'once') {
    if (current >= today) reminders.push({ daysLeft: daysBetween(today, current) });
    return { reminders, update: { nextOn: current, remindOn: null } };
  }

  // Each pass handles one occurrence whose reminder is due, then moves to the next.
  // The next pass only happens when that occurrence's reminder is also due, which
  // needs a long reminder lead close to a short gap; MAX_STEPS bounds it anyway.
  for (let step = 0; ; step++) {
    if (current >= today) reminders.push({ daysLeft: daysBetween(today, current) });
    const from = current >= today ? addDays(current, 1) : today;
    current = occurrenceOnOrAfter(startOn, recurrence, from);
    const next = addDays(current, -remindDays);
    if (next > today || step + 1 >= MAX_STEPS) {
      return { reminders, update: { nextOn: current, remindOn: next } };
    }
  }
}

function validDay(raw: unknown): string | null {
  if (typeof raw !== 'string' || !DAY_KEY.test(raw)) return null;
  const [y, m, d] = raw.split('-').map(Number);
  if (m < 1 || m > 12 || d < 1 || d > daysInMonth(y, m)) return null;
  return raw;
}

/** The push a member sees for a family date that is [daysLeft] days away. */
export function familyDateReminderText(
  record: FamilyDateRecord,
  daysLeft: number,
): { title: string; body: string } {
  const title = typeof record.title === 'string' ? record.title.trim() : '';
  const kind = typeof record.kind === 'string' ? record.kind : 'custom';
  const emoji = KIND_EMOJI[kind] ?? KIND_EMOJI.custom;
  const when =
    daysLeft <= 0 ? 'Today' : daysLeft === 1 ? 'Tomorrow' : `In ${daysLeft} days`;
  return {
    title: title === '' ? `${emoji} Family date` : `${emoji} ${title}`,
    body: when,
  };
}

const KIND_EMOJI: Record<string, string> = {
  birthday: '🎂',
  anniversary: '💍',
  bill: '🧾',
  school: '🎒',
  medicine: '💊',
  custom: '📅',
};
