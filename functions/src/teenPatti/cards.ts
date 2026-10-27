/**
 * Cards and hand ranking for Teen Patti, ported from
 * lib/features/game_zone/teen_patti/teen_patti_engine.dart. A card is a code:
 * the rank, then the suit (S, H, D, C), as in "10S" or "AH". The two rule sets
 * must rank every hand the same way.
 */

import { randomInt } from 'crypto';

export const SUITS = ['S', 'H', 'D', 'C'] as const;
export type Suit = (typeof SUITS)[number];

const RANK_VALUES: Record<string, number> = {
  '2': 2,
  '3': 3,
  '4': 4,
  '5': 5,
  '6': 6,
  '7': 7,
  '8': 8,
  '9': 9,
  '10': 10,
  J: 11,
  Q: 12,
  K: 13,
  A: 14,
};

export type HandType = 'highCard' | 'pair' | 'color' | 'sequence' | 'pureSequence' | 'trail';

const HAND_SCORE: Record<HandType, number> = {
  highCard: 1,
  pair: 2,
  color: 3,
  sequence: 4,
  pureSequence: 5,
  trail: 6,
};

export interface Evaluation {
  handType: HandType;
  primary: number;
  secondary: number;
  kicker: number;
}

export function isCard(value: unknown): value is string {
  if (typeof value !== 'string' || value.length < 2) return false;
  const rank = rankOf(value);
  const suit = suitOf(value);
  return Object.prototype.hasOwnProperty.call(RANK_VALUES, rank) && (SUITS as readonly string[]).includes(suit);
}

export function rankOf(code: string): string {
  return code.slice(0, -1);
}

export function suitOf(code: string): Suit {
  return code.slice(-1) as Suit;
}

export function cardValue(code: string): number {
  return RANK_VALUES[rankOf(code)];
}

/** All 52 cards, in a fixed order. */
export function fullDeck(): string[] {
  const deck: string[] = [];
  for (const suit of SUITS) {
    for (const rank of Object.keys(RANK_VALUES)) deck.push(`${rank}${suit}`);
  }
  return deck;
}

/** A shuffled 52-card deck, drawn from a cryptographically random source. */
export function shuffledDeck(): string[] {
  const deck = fullDeck();
  for (let i = deck.length - 1; i > 0; i--) {
    const j = randomInt(0, i + 1);
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

/**
 * Ranks three cards. A run is A-K-Q at the top, down to 4-3-2; A-2-3 plays the
 * ace low and is the lowest run of all.
 */
export function evaluate(cards: readonly string[]): Evaluation {
  if (cards.length !== 3) throw new Error('A Teen Patti hand must contain exactly 3 cards');

  const sorted = [...cards].sort((a, b) => cardValue(b) - cardValue(a));
  const [v1, v2, v3] = sorted.map((c) => cardValue(c));
  const isFlush = suitOf(sorted[0]) === suitOf(sorted[1]) && suitOf(sorted[1]) === suitOf(sorted[2]);

  if (v1 === v2 && v2 === v3) return { handType: 'trail', primary: v1, secondary: 0, kicker: 0 };

  const isStandardSeq = v1 - v2 === 1 && v2 - v3 === 1;
  const isA23Seq = v1 === 14 && v2 === 3 && v3 === 2;
  if (isStandardSeq || isA23Seq) {
    const seqRank = isA23Seq ? 3 : v1;
    return { handType: isFlush ? 'pureSequence' : 'sequence', primary: seqRank, secondary: 0, kicker: 0 };
  }

  if (isFlush) return { handType: 'color', primary: v1, secondary: v2, kicker: v3 };

  if (v1 === v2) return { handType: 'pair', primary: v1, secondary: 0, kicker: v3 };
  if (v2 === v3) return { handType: 'pair', primary: v2, secondary: 0, kicker: v1 };
  if (v1 === v3) return { handType: 'pair', primary: v1, secondary: 0, kicker: v2 };

  return { handType: 'highCard', primary: v1, secondary: v2, kicker: v3 };
}

/** Positive when [a] beats [b], negative when [b] wins, zero for a tie. */
export function compareEvaluations(a: Evaluation, b: Evaluation): number {
  if (HAND_SCORE[a.handType] !== HAND_SCORE[b.handType]) return HAND_SCORE[a.handType] - HAND_SCORE[b.handType];
  if (a.primary !== b.primary) return a.primary - b.primary;
  if (a.secondary !== b.secondary) return a.secondary - b.secondary;
  return a.kicker - b.kicker;
}

export function compareHands(a: readonly string[], b: readonly string[]): number {
  return compareEvaluations(evaluate(a), evaluate(b));
}

/** Rough 0..1 strength of a hand, used by the bots. Ported from TeenPattiGame.handStrength. */
export function handStrength(hand: readonly string[]): number {
  const e = evaluate(hand);
  const rank = e.primary / 14;
  switch (e.handType) {
    case 'trail':
      return 0.97 + rank * 0.03;
    case 'pureSequence':
      return 0.92 + rank * 0.04;
    case 'sequence':
      return 0.84 + rank * 0.06;
    case 'color':
      return 0.72 + rank * 0.1;
    case 'pair':
      return 0.45 + rank * 0.25;
    case 'highCard':
      return Math.min(1, Math.max(0, (e.primary - 4) / 10)) * 0.4;
  }
}
