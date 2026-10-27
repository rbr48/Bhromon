/**
 * The 29 table state machine for the online game. It mirrors Card29Game in
 * lib/features/game_zone/card29/card29_game.dart, with two additions for the
 * online table: seats can be bots, and the state is split into what everyone
 * may see (public) and what each seat holds privately.
 */

import { randomInt } from 'crypto';
import { GameView, bidLimit, chooseCard, chooseTrump, shouldAskTrump } from './bot';
import {
  BID_MAX,
  BID_MIN,
  PIPS_TO_WIN,
  PlayedCard,
  Suit,
  fullDeck,
  hasRoyalty,
  isCard,
  isSuit,
  legalPlays,
  pointsOf,
  sortHand,
  suitOf,
  teamOf,
  trickWinner,
} from './cards';

export type Phase = 'bidding' | 'trumpSelection' | 'playing' | 'trickComplete' | 'roundOver' | 'matchOver';

/** How long a human has to act before the table plays for them. */
export const HUMAN_TURN_MS = 60_000;

/** A rule was broken by the caller: not their turn, an illegal card, and so on. */
export class Card29RuleError extends Error {}

export interface LastTrick {
  cards: PlayedCard[];
  winner: number;
  points: number;
}

export interface LastEvent {
  type: string;
  seat: number;
  value?: number;
}

export type HumanAction =
  | { type: 'bid'; bid: number }
  | { type: 'pass' }
  | { type: 'selectTrump'; suit: Suit }
  | { type: 'ask' }
  | { type: 'reveal' }
  | { type: 'claimRoyalty' }
  | { type: 'play'; card: string }
  | { type: 'nextDeal' }
  | { type: 'newMatch' };

/** Cryptographically random, uniform in [0, 1). */
export function secureRandom(): number {
  return randomInt(0, 1_000_000) / 1_000_000;
}

/** A fresh 32-card deck, shuffled with a cryptographically random source. */
export function shuffledDeck(): string[] {
  const deck = fullDeck();
  for (let i = deck.length - 1; i > 0; i--) {
    const j = randomInt(0, i + 1);
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

export class Card29Game implements GameView {
  readonly hands: string[][] = [[], [], [], []];
  /** Second half of each hand, held back until bidding ends. */
  readonly pending: string[][] = [[], [], [], []];

  phase: Phase = 'roundOver';
  dealer = 3;
  currentTurn = 0;
  highestBid = 15;
  highestBidder = -1;
  readonly passed = new Set<number>();

  trump: Suit | null = null;
  revealed = false;
  revealedBy = -1;
  royaltyClaimed = false;
  royaltyClaimedBy = -1;
  bidTarget = 0;

  currentTrick: PlayedCard[] = [];
  leadSuit: Suit | null = null;
  trickWinnerSeat: number | null = null;
  playedCards: string[] = [];

  teamPoints: number[] = [0, 0];
  matchPips: number[] = [0, 0];
  trickCount = 0;
  lastTrick: LastTrick | null = null;
  lastEvent: LastEvent | null = null;

  constructor(
    readonly isBot: readonly boolean[],
    private readonly random: () => number = secureRandom,
  ) {}

  get bidderTeam(): number {
    return teamOf(this.highestBidder);
  }

  minimumNextBid(): number {
    return Math.max(BID_MIN, this.highestBid + 1);
  }

  canBid(seat: number, bid: number): boolean {
    return (
      this.phase === 'bidding' &&
      this.currentTurn === seat &&
      !this.passed.has(seat) &&
      bid >= this.minimumNextBid() &&
      bid <= BID_MAX
    );
  }

  placeBid(seat: number, bid: number): boolean {
    if (!this.canBid(seat, bid)) return false;
    this.highestBid = bid;
    this.highestBidder = seat;
    this.lastEvent = { type: 'bid', seat, value: bid };
    this.advanceBidding();
    return true;
  }

  pass(seat: number): boolean {
    if (this.phase !== 'bidding' || this.currentTurn !== seat || this.passed.has(seat)) return false;
    this.passed.add(seat);
    this.lastEvent = { type: 'pass', seat };
    this.advanceBidding();
    return true;
  }

  private advanceBidding(): void {
    if (this.highestBidder === -1 && this.passed.size === 4) {
      this.highestBidder = this.dealer;
      this.highestBid = BID_MIN;
      this.lastEvent = { type: 'allPassed', seat: this.dealer, value: BID_MIN };
      this.finishBidding();
      return;
    }
    if (this.highestBidder !== -1 && (this.passed.size >= 3 || this.highestBid >= BID_MAX)) {
      this.finishBidding();
      return;
    }
    do {
      this.currentTurn = (this.currentTurn + 1) % 4;
    } while (this.passed.has(this.currentTurn));
  }

  private finishBidding(): void {
    this.bidTarget = this.highestBid;
    this.currentTurn = this.highestBidder;
    if (this.isBot[this.highestBidder]) {
      // A bot keeps its trump secret and deals the second half at once.
      this.trump = chooseTrump(this.hands[this.highestBidder]);
      this.dealSecondHalf();
    } else {
      this.phase = 'trumpSelection';
    }
  }

  selectTrump(seat: number, suit: Suit): boolean {
    if (this.phase !== 'trumpSelection' || seat !== this.highestBidder) return false;
    this.trump = suit;
    this.lastEvent = { type: 'trumpChosen', seat };
    this.dealSecondHalf();
    return true;
  }

  private dealSecondHalf(): void {
    for (let i = 0; i < 4; i++) {
      this.hands[i] = sortHand([...this.hands[i], ...this.pending[i]]);
      this.pending[i] = [];
    }
    this.phase = 'playing';
    this.currentTurn = this.highestBidder;
  }

  private isVoidInLead(seat: number): boolean {
    return this.leadSuit !== null && !this.hands[seat].some((c) => suitOf(c) === this.leadSuit);
  }

  legalCards(seat: number): string[] {
    if (this.phase !== 'playing' || this.currentTurn !== seat) return [];
    return legalPlays({
      hand: this.hands[seat],
      seat,
      leadSuit: this.leadSuit,
      trick: this.currentTrick,
      trump: this.trump,
      revealed: this.revealed,
      highestBidder: this.highestBidder,
    });
  }

  canAskTrump(seat: number): boolean {
    return (
      this.phase === 'playing' &&
      this.currentTurn === seat &&
      !this.revealed &&
      seat !== this.highestBidder &&
      this.isVoidInLead(seat)
    );
  }

  askTrump(seat: number): boolean {
    if (!this.canAskTrump(seat)) return false;
    this.reveal(seat, 'ask');
    return true;
  }

  canRevealTrump(seat: number): boolean {
    return (
      this.phase === 'playing' &&
      this.currentTurn === seat &&
      !this.revealed &&
      seat === this.highestBidder &&
      this.isVoidInLead(seat)
    );
  }

  revealTrump(seat: number): boolean {
    if (!this.canRevealTrump(seat)) return false;
    this.reveal(seat, 'reveal');
    return true;
  }

  private reveal(seat: number, type: 'ask' | 'reveal'): void {
    this.revealed = true;
    this.revealedBy = seat;
    this.lastEvent = { type, seat };
  }

  canClaimRoyalty(seat: number): boolean {
    return (
      (this.phase === 'playing' || this.phase === 'trickComplete') &&
      this.revealed &&
      !this.royaltyClaimed &&
      hasRoyalty(this.hands[seat], this.trump)
    );
  }

  claimRoyalty(seat: number): boolean {
    if (!this.canClaimRoyalty(seat)) return false;
    this.royaltyClaimed = true;
    this.royaltyClaimedBy = seat;
    if (teamOf(seat) === this.bidderTeam) {
      this.bidTarget = Math.max(BID_MIN, this.bidTarget - 4);
    } else {
      this.bidTarget = Math.min(BID_MAX, this.bidTarget + 4);
    }
    this.lastEvent = { type: 'pair', seat, value: this.bidTarget };
    return true;
  }

  playCard(seat: number, card: string): boolean {
    if (!this.legalCards(seat).includes(card)) return false;

    if (!this.revealed && seat === this.highestBidder && suitOf(card) === this.trump && this.isVoidInLead(seat)) {
      this.reveal(seat, 'reveal');
    }

    const index = this.hands[seat].indexOf(card);
    this.hands[seat].splice(index, 1);
    this.playedCards.push(card);
    this.currentTrick.push({ seat, card, trumpEligible: this.revealed });
    this.leadSuit ??= suitOf(card);
    this.lastEvent = { type: 'play', seat };

    if (this.currentTrick.length === 4) {
      this.trickWinnerSeat = trickWinner(this.currentTrick, this.trump, this.revealed).seat;
      this.phase = 'trickComplete';
    } else {
      this.currentTurn = (seat + 1) % 4;
    }
    return true;
  }

  /** Collects a finished trick. The server calls this after the trick has been shown. */
  resolveTrick(): boolean {
    if (this.phase !== 'trickComplete' || this.trickWinnerSeat === null) return false;
    const winner = this.trickWinnerSeat;
    let points = this.currentTrick.reduce((sum, p) => sum + pointsOf(p.card), 0);
    this.trickCount++;
    if (this.trickCount === 8) points += 1; // the last trick is worth one more point
    this.teamPoints[teamOf(winner)] += points;
    this.lastTrick = { cards: [...this.currentTrick], winner, points };

    this.currentTrick = [];
    this.leadSuit = null;
    this.trickWinnerSeat = null;
    this.currentTurn = winner;

    if (this.trickCount === 8) {
      this.finishRound();
    } else {
      this.phase = 'playing';
    }
    return true;
  }

  private finishRound(): void {
    const team = this.bidderTeam;
    const score = this.teamPoints[team];
    const made = score >= this.bidTarget;
    const winningTeam = made ? team : 1 - team;
    this.matchPips[winningTeam]++;
    this.lastEvent = { type: made ? 'bidMade' : 'bidFailed', seat: this.highestBidder, value: score };
    this.phase = this.matchPips.some((p) => p >= PIPS_TO_WIN) ? 'matchOver' : 'roundOver';
  }

  /** Deals a new round. [deck] must be 32 distinct cards. */
  startRound(deck: readonly string[]): void {
    if (deck.length !== 32) throw new Error('A deck has 32 cards');
    if (this.phase === 'matchOver') {
      this.matchPips = [0, 0];
    }
    this.dealer = (this.dealer + 1) % 4;
    for (let i = 0; i < 4; i++) {
      this.hands[i] = sortHand(deck.slice(i * 4, i * 4 + 4));
      this.pending[i] = deck.slice(16 + i * 4, 16 + i * 4 + 4);
    }
    this.currentTurn = (this.dealer + 1) % 4;
    this.phase = 'bidding';
    this.highestBid = 15;
    this.highestBidder = -1;
    this.passed.clear();
    this.trump = null;
    this.revealed = false;
    this.revealedBy = -1;
    this.royaltyClaimed = false;
    this.royaltyClaimedBy = -1;
    this.bidTarget = 0;
    this.currentTrick = [];
    this.leadSuit = null;
    this.trickWinnerSeat = null;
    this.playedCards = [];
    this.teamPoints = [0, 0];
    this.trickCount = 0;
    this.lastTrick = null;
    this.lastEvent = { type: 'dealt', seat: this.dealer };
  }

  newMatch(deck: readonly string[]): void {
    this.matchPips = [0, 0];
    this.dealer = 3;
    this.phase = 'roundOver';
    this.startRound(deck);
  }

  /**
   * Applies an action from the seat that sent it. A seat may only act for
   * itself, and only when the rules allow it.
   */
  applyHuman(seat: number, action: HumanAction, deck: () => string[]): void {
    const refuse = (message: string): never => {
      throw new Card29RuleError(message);
    };
    switch (action.type) {
      case 'bid':
        if (!this.placeBid(seat, action.bid)) refuse('That bid is not allowed now.');
        return;
      case 'pass':
        if (!this.pass(seat)) refuse('You cannot pass now.');
        return;
      case 'selectTrump':
        if (!isSuit(action.suit)) refuse('Unknown suit.');
        if (!this.selectTrump(seat, action.suit)) refuse('Only the bidder picks the trump now.');
        return;
      case 'ask':
        if (!this.askTrump(seat)) refuse('You cannot ask for trump now.');
        return;
      case 'reveal':
        if (!this.revealTrump(seat)) refuse('You cannot reveal trump now.');
        return;
      case 'claimRoyalty':
        if (!this.claimRoyalty(seat)) refuse('You cannot show the pair now.');
        return;
      case 'play':
        if (!isCard(action.card)) refuse('Unknown card.');
        if (!this.playCard(seat, action.card)) refuse('That card cannot be played now.');
        return;
      case 'nextDeal':
        if (this.phase !== 'roundOver') refuse('The round is not over.');
        this.startRound(deck());
        return;
      case 'newMatch':
        if (this.phase !== 'matchOver') refuse('The match is not over.');
        this.newMatch(deck());
        return;
      default:
        return refuse('Unknown action.');
    }
  }

  /**
   * One step of the table, for when a bot must act, a finished trick must be
   * collected, or a human has run out of time. Returns what happened, or null
   * when the table is waiting for a human who still has time.
   */
  advance(humanTurnExpired: boolean): 'resolve' | 'bot' | 'auto' | null {
    if (this.phase === 'trickComplete') {
      this.resolveTrick();
      return 'resolve';
    }
    if (this.phase === 'roundOver' || this.phase === 'matchOver') return null;

    const seatToAct = this.phase === 'trumpSelection' ? this.highestBidder : this.currentTurn;
    if (this.isBot[seatToAct]) {
      if (this.phase === 'bidding') this.botBid(seatToAct);
      else if (this.phase === 'playing') this.botPlay(seatToAct);
      else return null;
      return 'bot';
    }

    if (!humanTurnExpired) return null;
    if (this.phase === 'bidding') {
      this.pass(seatToAct);
    } else if (this.phase === 'trumpSelection') {
      this.selectTrump(seatToAct, chooseTrump(this.hands[seatToAct]));
    } else {
      this.playCard(seatToAct, chooseCard(this, seatToAct));
    }
    return 'auto';
  }

  private botBid(seat: number): void {
    const limit = bidLimit(this.hands[seat]);
    const next = this.minimumNextBid();
    const partnerHolds = this.highestBidder !== -1 && teamOf(this.highestBidder) === teamOf(seat);
    if (next <= limit && (!partnerHolds || limit >= next + 2)) {
      this.placeBid(seat, next);
    } else {
      this.pass(seat);
    }
  }

  private botPlay(seat: number): void {
    if (this.canClaimRoyalty(seat)) this.claimRoyalty(seat);
    if (this.canAskTrump(seat) && shouldAskTrump(this, seat, this.random)) this.askTrump(seat);
    this.playCard(seat, chooseCard(this, seat));
    if (this.canClaimRoyalty(seat)) this.claimRoyalty(seat);
  }

  /** When the table next waits on a human, or null when no human is awaited. */
  turnDeadline(nowMs: number): number | null {
    if (this.phase !== 'bidding' && this.phase !== 'trumpSelection' && this.phase !== 'playing') return null;
    const seat = this.phase === 'trumpSelection' ? this.highestBidder : this.currentTurn;
    return this.isBot[seat] ? null : nowMs + HUMAN_TURN_MS;
  }
}

/** What each seat holds privately, stored in games/{id}/private/seat{n}. */
export interface SeatDoc {
  owner: string;
  seat: number;
  hand: string[];
  pending: string[];
  /** Set only for the bidder, who knows the trump before it is revealed. */
  trumpSuit: Suit | null;
}

/** The table state every member may read. Hands and the hidden trump are not in it. */
export function publicState(g: Card29Game, step: number, nowMs: number): Record<string, unknown> {
  return {
    step,
    phase: g.phase,
    dealer: g.dealer,
    currentTurn: g.currentTurn,
    highestBid: g.highestBid,
    highestBidder: g.highestBidder,
    passed: [...g.passed].sort((a, b) => a - b),
    trumpRevealed: g.revealed,
    trumpRevealedBy: g.revealedBy,
    trumpSuit: g.revealed ? g.trump : null,
    royaltyClaimed: g.royaltyClaimed,
    royaltyClaimedBy: g.royaltyClaimedBy,
    bidTarget: g.bidTarget,
    currentTrick: g.currentTrick,
    leadSuit: g.leadSuit,
    trickWinner: g.trickWinnerSeat,
    playedCards: g.playedCards,
    trickCount: g.trickCount,
    teamPoints: g.teamPoints,
    matchPips: g.matchPips,
    handCounts: g.hands.map((h) => h.length),
    lastTrick: g.lastTrick,
    lastEvent: g.lastEvent,
    turnDeadline: g.turnDeadline(nowMs),
  };
}

export function seatDoc(g: Card29Game, seat: number, owner: string): SeatDoc {
  return {
    owner,
    seat,
    hand: [...g.hands[seat]],
    pending: [...g.pending[seat]],
    trumpSuit: seat === g.highestBidder ? g.trump : null,
  };
}

/**
 * Cards from storage, copied. The copy matters: the game removes cards from its
 * hands as they are played, and the stored snapshot must not change with them,
 * or a later write can miss the change.
 */
function readCards(value: unknown, label: string): string[] {
  if (!Array.isArray(value) || !value.every(isCard)) throw new Error(`Corrupt ${label}`);
  return [...(value as string[])];
}

function readNumbers(value: unknown): number[] {
  return [...(value as number[])];
}

/** Rebuilds the table from its stored public state and the four seat documents. */
export function restoreGame(
  state: Record<string, unknown>,
  seats: readonly SeatDoc[],
  isBot: readonly boolean[],
  random: () => number = secureRandom,
): Card29Game {
  const g = new Card29Game(isBot, random);
  g.phase = state.phase as Phase;
  g.dealer = state.dealer as number;
  g.currentTurn = state.currentTurn as number;
  g.highestBid = state.highestBid as number;
  g.highestBidder = state.highestBidder as number;
  for (const seat of state.passed as number[]) g.passed.add(seat);
  g.revealed = state.trumpRevealed === true;
  g.revealedBy = state.trumpRevealedBy as number;
  g.royaltyClaimed = state.royaltyClaimed === true;
  g.royaltyClaimedBy = state.royaltyClaimedBy as number;
  g.bidTarget = state.bidTarget as number;
  g.currentTrick = (state.currentTrick as PlayedCard[]).map((p) => ({ ...p }));
  g.leadSuit = (state.leadSuit as Suit | null) ?? null;
  g.trickWinnerSeat = (state.trickWinner as number | null) ?? null;
  g.playedCards = readCards(state.playedCards, 'played cards');
  g.teamPoints = readNumbers(state.teamPoints);
  g.matchPips = readNumbers(state.matchPips);
  g.trickCount = state.trickCount as number;
  g.lastTrick = (state.lastTrick as LastTrick | null) ?? null;
  g.lastEvent = (state.lastEvent as LastEvent | null) ?? null;
  for (let i = 0; i < 4; i++) {
    g.hands[i] = readCards(seats[i].hand, 'hand');
    g.pending[i] = readCards(seats[i].pending, 'pending cards');
  }
  const publicTrump = (state.trumpSuit as Suit | null) ?? null;
  g.trump = publicTrump ?? (g.highestBidder >= 0 ? seats[g.highestBidder].trumpSuit : null);
  return g;
}
