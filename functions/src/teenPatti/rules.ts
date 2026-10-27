/**
 * The Teen Patti numbers, as in lib/features/game_zone/teen_patti/teen_patti_game.dart.
 * The phone's offline game and the server's table must agree on every one.
 */

export const BOOT = 10;
export const START_BASE = 10;
export const MAX_BASE = 40;
export const MAX_BLIND_TURNS = 4;
export const STARTING_CHIPS = 500;
export const REBUY_AMOUNT = 500;
export const POT_LIMIT = 1280;

/** Chips needed to sit in a hand: the boot plus one blind stake. */
export const MIN_BUY_IN = BOOT + START_BASE;

/** How long a person has to act before the table plays for them. */
export const HUMAN_TURN_MS = 60_000;
