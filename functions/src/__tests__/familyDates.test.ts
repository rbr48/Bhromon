import {
  addDays,
  daysBetween,
  dhakaDayKey,
  familyDateReminderText,
  occurrenceOnOrAfter,
  planFamilyDateReminders,
} from '../lib/familyDates';

describe('dhakaDayKey', () => {
  it('reads the Dhaka day, which is six hours ahead of UTC', () => {
    // 17:59 UTC is 23:59 in Dhaka, still the same day.
    expect(dhakaDayKey(Date.UTC(2026, 9, 31, 17, 59))).toBe('2026-10-31');
    // 18:00 UTC is midnight in Dhaka, so the next day.
    expect(dhakaDayKey(Date.UTC(2026, 9, 31, 18, 0))).toBe('2026-11-01');
  });
});

describe('day arithmetic', () => {
  it('counts whole days, forwards and backwards', () => {
    expect(daysBetween('2026-10-31', '2026-11-03')).toBe(3);
    expect(daysBetween('2026-11-03', '2026-10-31')).toBe(-3);
    expect(daysBetween('2026-10-31', '2026-10-31')).toBe(0);
  });

  it('adds days across month, year and leap-day boundaries', () => {
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2028-02-28', 1)).toBe('2028-02-29');
    expect(addDays('2026-02-28', 1)).toBe('2026-03-01');
    expect(addDays('2026-11-03', -7)).toBe('2026-10-27');
  });
});

describe('occurrenceOnOrAfter', () => {
  it('keeps a yearly date on its month and day', () => {
    expect(occurrenceOnOrAfter('2000-03-15', 'yearly', '2026-10-31')).toBe(
      '2027-03-15',
    );
    expect(occurrenceOnOrAfter('2000-03-15', 'yearly', '2026-03-15')).toBe(
      '2026-03-15',
    );
    expect(occurrenceOnOrAfter('2000-03-15', 'yearly', '2026-03-16')).toBe(
      '2027-03-15',
    );
  });

  it('moves a 29 February birthday to 28 February in a common year', () => {
    expect(occurrenceOnOrAfter('2024-02-29', 'yearly', '2026-01-01')).toBe(
      '2026-02-28',
    );
    expect(occurrenceOnOrAfter('2024-02-29', 'yearly', '2028-01-01')).toBe(
      '2028-02-29',
    );
  });

  it('keeps a monthly date on its day, or the last day of a short month', () => {
    expect(occurrenceOnOrAfter('2026-01-31', 'monthly', '2026-02-01')).toBe(
      '2026-02-28',
    );
    expect(occurrenceOnOrAfter('2026-01-31', 'monthly', '2026-02-28')).toBe(
      '2026-02-28',
    );
    expect(occurrenceOnOrAfter('2026-01-31', 'monthly', '2026-03-01')).toBe(
      '2026-03-31',
    );
  });

  it('rolls a monthly date over the year end', () => {
    expect(occurrenceOnOrAfter('2026-11-15', 'monthly', '2026-12-20')).toBe(
      '2027-01-15',
    );
  });

  it('never moves a one-time date', () => {
    expect(occurrenceOnOrAfter('2026-05-01', 'once', '2026-10-31')).toBe(
      '2026-05-01',
    );
  });
});

describe('planFamilyDateReminders', () => {
  it('does nothing before the reminder day', () => {
    expect(
      planFamilyDateReminders(
        {
          recurrence: 'yearly',
          startOn: '2000-11-03',
          nextOn: '2026-11-03',
          remindDays: 7,
          remindOn: '2026-10-27',
        },
        '2026-10-26',
      ),
    ).toBeNull();
  });

  it('sends the reminder and moves a yearly birthday to next year', () => {
    expect(
      planFamilyDateReminders(
        {
          recurrence: 'yearly',
          startOn: '2000-11-03',
          nextOn: '2026-11-03',
          remindDays: 7,
          remindOn: '2026-10-27',
        },
        '2026-10-27',
      ),
    ).toEqual({
      reminders: [{ daysLeft: 7 }],
      update: { nextOn: '2027-11-03', remindOn: '2027-10-27' },
    });
  });

  it('sends a same-day reminder when the date is today', () => {
    expect(
      planFamilyDateReminders(
        {
          recurrence: 'yearly',
          startOn: '2000-11-03',
          nextOn: '2026-11-03',
          remindDays: 0,
          remindOn: '2026-11-03',
        },
        '2026-11-03',
      ),
    ).toEqual({
      reminders: [{ daysLeft: 0 }],
      update: { nextOn: '2027-11-03', remindOn: '2027-11-03' },
    });
  });

  it('does not send for a date that passed while the job was down', () => {
    expect(
      planFamilyDateReminders(
        {
          recurrence: 'yearly',
          startOn: '2000-11-03',
          nextOn: '2026-11-03',
          remindDays: 7,
          remindOn: '2026-10-27',
        },
        '2026-11-06',
      ),
    ).toEqual({
      reminders: [],
      update: { nextOn: '2027-11-03', remindOn: '2027-10-27' },
    });
  });

  it('keeps a monthly bill on the first of each month', () => {
    expect(
      planFamilyDateReminders(
        {
          recurrence: 'monthly',
          startOn: '2026-06-01',
          nextOn: '2026-11-01',
          remindDays: 3,
          remindOn: '2026-10-29',
        },
        '2026-10-29',
      ),
    ).toEqual({
      reminders: [{ daysLeft: 3 }],
      update: { nextOn: '2026-12-01', remindOn: '2026-11-28' },
    });
  });

  it('reminds a one-time date once, then clears its reminder', () => {
    expect(
      planFamilyDateReminders(
        {
          recurrence: 'once',
          startOn: '2026-11-10',
          nextOn: '2026-11-10',
          remindDays: 1,
          remindOn: '2026-11-09',
        },
        '2026-11-09',
      ),
    ).toEqual({
      reminders: [{ daysLeft: 1 }],
      update: { nextOn: '2026-11-10', remindOn: null },
    });
  });

  it('clears a one-time date that already passed, without a reminder', () => {
    expect(
      planFamilyDateReminders(
        {
          recurrence: 'once',
          startOn: '2026-10-01',
          nextOn: '2026-10-01',
          remindDays: 1,
          remindOn: '2026-09-30',
        },
        '2026-10-31',
      ),
    ).toEqual({
      reminders: [],
      update: { nextOn: '2026-10-01', remindOn: null },
    });
  });

  it('reminds about a 29 February date on the 28th in a common year', () => {
    expect(
      planFamilyDateReminders(
        {
          recurrence: 'yearly',
          startOn: '2024-02-29',
          nextOn: '2026-02-28',
          remindDays: 1,
          remindOn: '2026-02-27',
        },
        '2026-02-27',
      ),
    ).toEqual({
      reminders: [{ daysLeft: 1 }],
      update: { nextOn: '2027-02-28', remindOn: '2027-02-27' },
    });
  });

  it('refuses a record it cannot read', () => {
    const good = {
      recurrence: 'yearly',
      startOn: '2000-11-03',
      nextOn: '2026-11-03',
      remindDays: 7,
      remindOn: '2026-10-27',
    };
    const today = '2026-10-27';
    expect(planFamilyDateReminders({ ...good, nextOn: '2026-02-30' }, today)).toBeNull();
    expect(planFamilyDateReminders({ ...good, remindDays: 1.5 }, today)).toBeNull();
    expect(planFamilyDateReminders({ ...good, recurrence: 'weekly' }, today)).toBeNull();
    expect(planFamilyDateReminders({ ...good, remindOn: null }, today)).toBeNull();
    expect(planFamilyDateReminders({ ...good, startOn: 'soon' }, today)).toBeNull();
  });
});

describe('familyDateReminderText', () => {
  const record = { title: "Asha's birthday", kind: 'birthday' };

  it('says when the date is', () => {
    expect(familyDateReminderText(record, 0).body).toBe('Today');
    expect(familyDateReminderText(record, 1).body).toBe('Tomorrow');
    expect(familyDateReminderText(record, 5).body).toBe('In 5 days');
  });

  it('leads with a kind emoji and the title', () => {
    expect(familyDateReminderText(record, 0)).toEqual({
      title: "🎂 Asha's birthday",
      body: 'Today',
    });
  });

  it('falls back when the title is empty or the kind is unknown', () => {
    expect(familyDateReminderText({ title: '  ', kind: 'bill' }, 2).title).toBe(
      '🧾 Family date',
    );
    expect(familyDateReminderText({ title: 'Trip', kind: 'other' }, 2).title).toBe(
      '📅 Trip',
    );
  });
});
