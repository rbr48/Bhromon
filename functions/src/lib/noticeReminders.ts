/** A reminder goes out this long before a timed notice starts. */
export const REMINDER_LEAD_MS = 30 * 60 * 1000;

/** The event times due a reminder at [nowMs]: from now until the lead time ahead. */
export function reminderWindow(nowMs: number): { fromMs: number; toMs: number } {
  return { fromMs: nowMs, toMs: nowMs + REMINDER_LEAD_MS };
}

/** Whole minutes from [nowMs] to [eventAtMs], rounded up, and never below one. */
export function minutesUntil(eventAtMs: number, nowMs: number): number {
  return Math.max(1, Math.ceil((eventAtMs - nowMs) / 60000));
}

/** The reminder a member sees for a timed notice. */
export function reminderText(
  notice: Record<string, unknown>,
  minutesLeft: number,
): { title: string; body: string } {
  const title = typeof notice.title === 'string' ? notice.title.trim() : '';
  const place = typeof notice.place === 'string' ? notice.place.trim() : '';
  return {
    title: title === '' ? '⏰ Upcoming notice' : `⏰ ${title}`,
    body: `Starts in ${minutesLeft} min${place === '' ? '' : ` · ${place}`}`,
  };
}
