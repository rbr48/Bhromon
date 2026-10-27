/**
 * Card and trick rules for the 29 card game, as plain functions over card codes
 * such as "JH" (jack of hearts) or "10S" (ten of spades).
 *
 * This mirrors lib/features/game_zone/card29/card29_engine.dart. The server
 * runs the game, so these rules must stay identical to the app's rules.
 */

export const SUITS = ['spades', 'hearts', 'diamonds', 'clubs'] as const;
export type Suit = (typeof SUITS)[number];

const SUIT_CODE: Record<Suit, string> = { spades: 'S', hearts: 'H', diamonds: 'D', clubs: 'C' };

export interface RankInfo {
  readonly code: string;
  readonly points: number;
  /** Higher beats lower within a suit. */
  readonly power: number;
}

const RANKS: readonly RankInfo[] = [
  { code: 'J', points: 3, power: 8 },
  { code: '9', points: 2, power: 7 },
  { code: 'A', points: 1, power: 6 },
  { code: '10', points: 1, power: 5 },
  { code: 'K', points: 0, power: 4 },
  { code: 'Q', points: 0, power: 3 },
  { code: '8', points: 0, power: 2 },
  { code: '7', points: 0, power: 1 },
];

const RANK_BY_CODE = new Map(RANKS.map((r) => [r.code, r]));
const SUIT_BY_CODE = new Map(SUITS.map((s) => [SUIT_CODE[s], s]));

export const BID_MIN = 16;
export const BID_MAX = 28;
export const PIPS_TO_WIN = 6;

/** A card as it was played, and whether it can count as trump. */
export interface PlayedCard {
  seat: number;
  card: string;
  trumpEligible: boolean;
}

export function cardOf(suit: Suit, rankCode: string): string {
  return `${rankCode}${SUIT_CODE[suit]}`;
}

export function rankOf(card: string): RankInfo {
  const rank = RANK_BY_CODE.get(card.slice(0, -1));
  if (!rank) throw new Error(`Not a card: ${card}`);
  return rank;
}

export function suitOf(card: string): Suit {
  const suit = SUIT_BY_CODE.get(card.slice(-1));
  if (!suit) throw new Error(`Not a card: ${card}`);
  return suit;
}

export function pointsOf(card: string): number {
  return rankOf(card).points;
}

export function powerOf(card: string): number {
  return rankOf(card).power;
}

export function isCard(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  try {
    rankOf(value);
    suitOf(value);
    return true;
  } catch {
    return false;
  }
}

export function isSuit(value: unknown): value is Suit {
  return typeof value === 'string' && (SUITS as readonly string[]).includes(value);
}

/** The team a seat plays for: seats 0 and 2 are one team, 1 and 3 the other. */
export function teamOf(seat: number): number {
  return seat % 2;
}

/** All 32 cards, in suit order then rank order (the same order the app builds them). */
export function fullDeck(): string[] {
  const deck: string[] = [];
  for (const suit of SUITS) {
    for (const rank of RANKS) deck.push(cardOf(suit, rank.code));
  }
  return deck;
}

/** Hands are kept by suit, then by power, highest first. */
export function sortHand(hand: readonly string[]): string[] {
  return [...hand].sort((a, b) => {
    const bySuit = SUITS.indexOf(suitOf(a)) - SUITS.indexOf(suitOf(b));
    if (bySuit !== 0) return bySuit;
    return powerOf(b) - powerOf(a);
  });
}

export function hasRoyalty(hand: readonly string[], trump: Suit | null): boolean {
  if (trump === null) return false;
  return hand.includes(cardOf(trump, 'K')) && hand.includes(cardOf(trump, 'Q'));
}

/** Who takes a trick. Trump counts only when revealed and played after the reveal. */
export function trickWinner(trick: readonly PlayedCard[], trump: Suit | null, revealed: boolean): PlayedCard {
  if (trick.length === 0) throw new Error('A trick needs at least one card');
  const leadSuit = suitOf(trick[0].card);
  const countsAsTrump = (play: PlayedCard): boolean =>
    revealed &&
    trump !== null &&
    suitOf(play.card) === trump &&
    (play.trumpEligible || suitOf(play.card) === leadSuit);

  let best = trick[0];
  let highestTrumpPower = countsAsTrump(trick[0]) ? powerOf(trick[0].card) : -1;
  for (let i = 1; i < trick.length; i++) {
    const play = trick[i];
    if (countsAsTrump(play)) {
      if (powerOf(play.card) > highestTrumpPower) {
        highestTrumpPower = powerOf(play.card);
        best = play;
      }
    } else if (highestTrumpPower === -1 && suitOf(play.card) === leadSuit) {
      if (powerOf(play.card) > powerOf(best.card)) best = play;
    }
  }
  return best;
}

export interface LegalPlayInput {
  hand: readonly string[];
  seat: number;
  leadSuit: Suit | null;
  trick: readonly PlayedCard[];
  trump: Suit | null;
  revealed: boolean;
  highestBidder: number;
}

/**
 * Cards the seat may play now. Follow the led suit when you can. Once trump is
 * revealed, a void player must trump when an opponent is winning, unless their
 * partner is winning or they cannot beat the opponent's trump.
 */
export function legalPlays(input: LegalPlayInput): string[] {
  const { hand, seat, leadSuit, trick, trump, revealed, highestBidder } = input;

  if (leadSuit === null) {
    if (!revealed && seat === highestBidder) {
      const nonTrump = hand.filter((c) => suitOf(c) !== trump);
      if (nonTrump.length > 0) return nonTrump;
    }
    return [...hand];
  }

  let mustTrump = true;
  let minTrumpPowerToBeat: number | null = null;
  if (revealed && trick.length > 0) {
    const winner = trickWinner(trick, trump, revealed);
    if (teamOf(winner.seat) === teamOf(seat)) {
      mustTrump = false;
    } else {
      const winningIsTrump =
        trump !== null && suitOf(winner.card) === trump && (winner.trumpEligible || suitOf(winner.card) === leadSuit);
      if (winningIsTrump) minTrumpPowerToBeat = powerOf(winner.card);
    }
  }

  return hand.filter((card) => isLegal(card, hand, leadSuit, revealed, trump, mustTrump, minTrumpPowerToBeat));
}

function isLegal(
  card: string,
  hand: readonly string[],
  leadSuit: Suit,
  revealed: boolean,
  trump: Suit | null,
  mustTrump: boolean,
  minTrumpPowerToBeat: number | null,
): boolean {
  if (hand.some((c) => suitOf(c) === leadSuit)) return suitOf(card) === leadSuit;

  if (revealed && trump !== null && mustTrump) {
    if (minTrumpPowerToBeat !== null) {
      const canOverTrump = hand.some((c) => suitOf(c) === trump && powerOf(c) > minTrumpPowerToBeat);
      if (canOverTrump) return suitOf(card) === trump && powerOf(card) > minTrumpPowerToBeat;
    } else if (hand.some((c) => suitOf(c) === trump)) {
      return suitOf(card) === trump;
    }
  }
  return true;
}
