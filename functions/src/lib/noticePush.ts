/** A push shows at most this many characters of a notice's text. */
export const NOTICE_PUSH_TEXT_LIMIT = 120;

/**
 * The text a notice push shows. Notices keep their text in `content`. `body`
 * is still read, in case an older notice was saved with it.
 */
export function noticePushBody(notice: Record<string, unknown>): string {
  const text = [notice.content, notice.body].find(
    (value): value is string => typeof value === 'string' && value.trim() !== '',
  );
  if (text === undefined) return 'A new notice was posted.';
  const trimmed = text.trim();
  return trimmed.length > NOTICE_PUSH_TEXT_LIMIT
    ? `${trimmed.slice(0, NOTICE_PUSH_TEXT_LIMIT - 1)}…`
    : trimmed;
}

/** The title a notice push shows. */
export function noticePushTitle(notice: Record<string, unknown>): string {
  const title = typeof notice.title === 'string' ? notice.title.trim() : '';
  return title === '' ? '📢 New notice' : `📢 ${title}`;
}
