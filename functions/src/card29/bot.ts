/**
 * The bot players for the online 29 table. This mirrors Card29Bot in
 * lib/features/game_zone/card29/card29_game.dart: the same heuristics, the
 * same tie-breaks, and the same gating, so a bot never uses the hidden trump
 * before it is revealed.
 */

import {
  BID_MAX,
  PlayedCard,
  SUITS,
  Suit,
  cardOf,
  pointsOf,
  powerOf,
  rankOf,
  suitOf,
  teamOf,
  trickWinner,
} from './cards';

/** What a bot may look at. The game object implements this. */
export interface GameView {
  readonly hands: readonly (readonly string[])[];
  readonly playedCards: readonly string[];
  readonly currentTrick: readonly PlayedCard[];
  readonly trump: Suit | null;
  readonly revealed: boolean;
  readonly highestBidder: number;
  readonly leadSuit: Suit | null;
  legalCards(seat: number): string[];
}

const BID_WEIGHTS: Record<string, number> = { J: 3, '9': 2, A: 1.2, '10': 1, K: 0.4, Q: 0.3 };

/** The highest bid a bot will make with its first four cards. */
export function bidLimit(hand: readonly string[]): number {
  let strength = 0;
  const counts = new Map<Suit, number>();
  for (const card of hand) {
    strength += BID_WEIGHTS[rankOf(card).code] ?? 0;
    const suit = suitOf(card);
    counts.set(suit, (counts.get(suit) ?? 0) + 1);
  }
  strength += Math.max(0, ...counts.values());
  return Math.min(BID_MAX, Math.max(15, Math.round(13 + strength * 1.2)));
}

/** The suit the bot would keep as trump from its first four cards. */
export function chooseTrump(hand: readonly string[]): Suit {
  let best: Suit = suitOf(hand[0]);
  let bestScore = Number.NEGATIVE_INFINITY;
  for (const suit of SUITS) {
    const cards = hand.filter((c) => suitOf(c) === suit);
    if (cards.length === 0) continue;
    const score = cards.length * 2 + cards.reduce((sum, c) => sum + pointsOf(c) + powerOf(c) / 10, 0);
    if (score > bestScore) {
      bestScore = score;
      best = suit;
    }
  }
  return best;
}

/** True when no unplayed card of the same suit outranks [card] outside [ownHand]. */
export function isMaster(card: string, ownHand: readonly string[], played: readonly string[]): boolean {
  const suit = suitOf(card);
  for (const rank of ['J', '9', 'A', '10', 'K', 'Q', '8', '7']) {
    const higher = cardOf(suit, rank);
    if (powerOf(higher) <= powerOf(card)) continue;
    if (!played.includes(higher) && !ownHand.includes(higher)) return false;
  }
  return true;
}

function trickPoints(g: GameView): number {
  return g.currentTrick.reduce((sum, p) => sum + pointsOf(p.card), 0);
}

/** Would [card], played now by [seat], take the lead? Counts the bidder's reveal. */
function wouldWin(g: GameView, seat: number, card: string): boolean {
  const reveals =
    !g.revealed &&
    seat === g.highestBidder &&
    suitOf(card) === g.trump &&
    g.leadSuit !== null &&
    !g.hands[seat].some((c) => suitOf(c) === g.leadSuit);
  const revealed = g.revealed || reveals;
  const trick: PlayedCard[] = [...g.currentTrick, { seat, card, trumpEligible: revealed }];
  return trickWinner(trick, g.trump, revealed).seat === seat;
}

/** Whether a bot who may ask for trump should do so now. */
export function shouldAskTrump(g: GameView, seat: number, random: () => number): boolean {
  const winner = trickWinner(g.currentTrick, g.trump, g.revealed);
  if (teamOf(winner.seat) === teamOf(seat)) return false;
  return trickPoints(g) >= 1 || g.currentTrick.length === 3 || random() < 0.3;
}

/** The card a bot plays from its legal cards. */
export function chooseCard(g: GameView, seat: number): string {
  const legal = g.legalCards(seat);
  if (legal.length === 1) return legal[0];

  const hidingTrump = !g.revealed && seat === g.highestBidder;

  // The lowest-value card, keeping the hidden trump suit back when we know it.
  const cheapest = (cards: readonly string[]): string => {
    const pool = hidingTrump && cards.some((c) => suitOf(c) !== g.trump)
      ? cards.filter((c) => suitOf(c) !== g.trump)
      : cards;
    return pool.reduce((a, b) => {
      if (pointsOf(a) !== pointsOf(b)) return pointsOf(a) < pointsOf(b) ? a : b;
      return powerOf(a) <= powerOf(b) ? a : b;
    });
  };

  if (g.currentTrick.length === 0) {
    const ownTeamBid = teamOf(seat) === teamOf(g.highestBidder);
    const trumps = legal.filter((c) => suitOf(c) === g.trump);
    if (g.revealed && ownTeamBid && trumps.length >= 3) {
      // Draw out the opponents' trumps.
      return trumps.reduce((a, b) => (powerOf(a) >= powerOf(b) ? a : b));
    }
    const masters = legal.filter((c) => isMaster(c, g.hands[seat], g.playedCards));
    if (masters.length > 0) {
      return masters.reduce((a, b) => (pointsOf(a) >= pointsOf(b) ? a : b));
    }
    // Lead low from the longest side suit.
    const counts = new Map<Suit, number>();
    for (const c of legal) counts.set(suitOf(c), (counts.get(suitOf(c)) ?? 0) + 1);
    const sideCards = legal.filter((c) => suitOf(c) !== g.trump || !g.revealed);
    const pool = sideCards.length === 0 ? legal : sideCards;
    const longest = Math.max(...pool.map((c) => counts.get(suitOf(c)) ?? 0));
    return cheapest(pool.filter((c) => counts.get(suitOf(c)) === longest));
  }

  const winner = trickWinner(g.currentTrick, g.trump, g.revealed);
  const partnerWinning = teamOf(winner.seat) === teamOf(seat);
  const isLast = g.currentTrick.length === 3;

  if (partnerWinning) {
    const partnerSafe = isLast || isMaster(winner.card, g.hands[seat], g.playedCards);
    if (partnerSafe) {
      // Feed points to the partner's trick.
      const feedable = hidingTrump ? legal.filter((c) => suitOf(c) !== g.trump) : legal;
      const pool = feedable.length === 0 ? legal : feedable;
      return pool.reduce((a, b) => {
        if (pointsOf(a) !== pointsOf(b)) return pointsOf(a) > pointsOf(b) ? a : b;
        return powerOf(a) <= powerOf(b) ? a : b;
      });
    }
    return cheapest(legal);
  }

  const winners = legal.filter((c) => wouldWin(g, seat, c));
  if (winners.length > 0) {
    const cheapestWinner = winners.reduce((a, b) => (powerOf(a) <= powerOf(b) ? a : b));
    if (isLast || trickPoints(g) > 0 || isMaster(cheapestWinner, g.hands[seat], g.playedCards) || pointsOf(cheapestWinner) > 0) {
      return cheapestWinner;
    }
  }
  return cheapest(legal);
}
