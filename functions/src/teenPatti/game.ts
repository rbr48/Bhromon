/**
 * A Teen Patti table on the server: the rules of the phone's offline game
 * (lib/features/game_zone/teen_patti/teen_patti_game.dart), run once for the
 * whole table. Each seat's cards stay in its private document. Everyone else
 * reads the public state, which never holds a hand, except the hands shown at
 * a showdown.
 */

import { Evaluation, HandType, compareEvaluations, compareHands, evaluate, isCard } from './cards';
import { botAcceptsSideshow, playBotTurn } from './bot';
import {
  BOOT,
  HUMAN_TURN_MS,
  MAX_BASE,
  MAX_BLIND_TURNS,
  MIN_BUY_IN,
  POT_LIMIT,
  REBUY_AMOUNT,
  START_BASE,
} from './rules';
import { secureRandom } from '../gameTable/random';

const SEAT_COUNT = 4;

export type Phase = 'betting' | 'awaitingSideshowReply' | 'roundOver';

export type LastActionKind = 'blind' | 'chaal' | 'raise' | 'show' | 'sideshow' | 'pack' | 'seen' | 'left' | 'sideshowLost';

export interface LastAction {
  kind: LastActionKind;
  amount: number | null;
}

export interface Seat {
  chips: number;
  /** Dealt into the current hand. A seat short of the buy-in sits the hand out. */
  playing: boolean;
  isSeen: boolean;
  isFolded: boolean;
  blindTurns: number;
  lastAction: LastAction | null;
  /** The seat's three cards. Private: only the seat's document holds them. */
  hand: string[];
}

export interface SideshowRequest {
  from: number;
  to: number;
}

export interface HandResult {
  winners: number[];
  potWon: number;
  wasShowdown: boolean;
  handType: HandType | null;
  potLimitReached: boolean;
  requestedBy: number | null;
}

/** What just happened at the table, for the screen to show. */
export interface LastEvent {
  type: string;
  seat: number;
  value: number | null;
}

export type TeenPattiAction =
  | { type: 'see' }
  | { type: 'bet' }
  | { type: 'raise' }
  | { type: 'pack' }
  | { type: 'show' }
  | { type: 'sideshow' }
  | { type: 'sideshowReply'; accept: boolean }
  | { type: 'rebuy' }
  | { type: 'nextHand' };

/** A rule was broken by the caller: not their turn, not enough chips, and so on. */
export class TeenPattiRuleError extends Error {}

function emptySeat(): Seat {
  return { chips: 0, playing: false, isSeen: false, isFolded: false, blindTurns: 0, lastAction: null, hand: [] };
}

export class TeenPattiGame {
  readonly seats: Seat[] = Array.from({ length: SEAT_COUNT }, () => emptySeat());
  /** Starts at the last seat, so the first hand is dealt from seat 0, as on the phone. */
  dealer = SEAT_COUNT - 1;
  currentTurn = 0;
  pot = 0;
  baseBet = START_BASE;
  phase: Phase = 'roundOver';
  pendingSideshow: SideshowRequest | null = null;
  result: HandResult | null = null;
  /** Hands shown at the last showdown, by seat. Packed hands are never shown. */
  revealed: Record<string, string[]> | null = null;
  lastEvent: LastEvent | null = null;
  handNumber = 0;
  /** Chips that rebuys have added. With the chips and the pot, this checks the books. */
  totalInjected = 0;

  constructor(
    readonly isBot: readonly boolean[],
    private readonly random: () => number = secureRandom,
  ) {}

  // --- Who may act ---

  isActive(seat: number): boolean {
    return this.seats[seat].playing && !this.seats[seat].isFolded;
  }

  activeSeats(): number[] {
    const seats: number[] = [];
    for (let seat = 0; seat < this.seats.length; seat++) {
      if (this.isActive(seat)) seats.push(seat);
    }
    return seats;
  }

  activeCount(): number {
    return this.activeSeats().length;
  }

  isTurnOf(seat: number): boolean {
    return this.phase === 'betting' && this.currentTurn === seat && this.isActive(seat);
  }

  /** The stake this seat pays to stay in: the base bet blind, double it once seen (chaal). */
  costFor(seat: number, base: number = this.baseBet): number {
    return this.seats[seat].isSeen ? base * 2 : base;
  }

  /** Looking at your cards is free, and it does not use your turn. */
  canSee(seat: number): boolean {
    return this.phase !== 'roundOver' && this.isActive(seat) && !this.seats[seat].isSeen;
  }

  canBet(seat: number): boolean {
    return this.isTurnOf(seat) && this.seats[seat].chips >= this.costFor(seat);
  }

  canRaise(seat: number): boolean {
    return (
      this.isTurnOf(seat) &&
      this.baseBet < MAX_BASE &&
      this.seats[seat].chips >= this.costFor(seat, this.baseBet * 2)
    );
  }

  canShow(seat: number): boolean {
    return this.isTurnOf(seat) && this.activeCount() === 2 && this.seats[seat].chips >= this.costFor(seat);
  }

  /** The previous active seat, the one who just acted before [seat]. */
  sideshowTarget(seat: number): number | null {
    let idx = (seat + this.seats.length - 1) % this.seats.length;
    while (idx !== seat) {
      if (this.isActive(idx)) return idx;
      idx = (idx + this.seats.length - 1) % this.seats.length;
    }
    return null;
  }

  canSideshow(seat: number): boolean {
    if (!this.isTurnOf(seat)) return false;
    const target = this.sideshowTarget(seat);
    return (
      this.seats[seat].isSeen &&
      this.activeCount() > 2 &&
      target !== null &&
      this.seats[target].isSeen &&
      this.seats[seat].chips >= this.costFor(seat)
    );
  }

  /** Chips can be topped up between hands, or while sitting a hand out. */
  canRebuy(seat: number): boolean {
    return this.seats[seat].chips < MIN_BUY_IN && (this.phase === 'roundOver' || !this.seats[seat].playing);
  }

  // --- Actions. Each returns false, and changes nothing, when the rules refuse it. ---

  see(seat: number): boolean {
    if (!this.canSee(seat)) return false;
    this.seats[seat].isSeen = true;
    this.seats[seat].lastAction = { kind: 'seen', amount: null };
    this.lastEvent = { type: 'seen', seat, value: null };
    return true;
  }

  bet(seat: number): boolean {
    if (!this.canBet(seat)) return false;
    this.stake(seat, false);
    return true;
  }

  raise(seat: number): boolean {
    if (!this.canRaise(seat)) return false;
    this.baseBet *= 2;
    this.stake(seat, true);
    return true;
  }

  pack(seat: number): boolean {
    if (!this.isTurnOf(seat)) return false;
    this.seats[seat].isFolded = true;
    this.seats[seat].lastAction = { kind: 'pack', amount: null };
    this.lastEvent = { type: 'pack', seat, value: null };
    this.settleTurn();
    return true;
  }

  show(seat: number): boolean {
    if (!this.canShow(seat)) return false;
    const cost = this.costFor(seat);
    this.pay(seat, cost);
    this.seats[seat].lastAction = { kind: 'show', amount: cost };
    this.showdown(this.activeSeats(), seat, false);
    return true;
  }

  /** Asks the previous seen player to compare hands in private. A person may decline. */
  requestSideshow(seat: number): boolean {
    const target = this.sideshowTarget(seat);
    if (target === null || !this.canSideshow(seat)) return false;
    const cost = this.costFor(seat);
    this.pay(seat, cost);
    this.seats[seat].lastAction = { kind: 'sideshow', amount: cost };

    if (!this.isBot[target]) {
      this.pendingSideshow = { from: seat, to: target };
      this.phase = 'awaitingSideshowReply';
      this.lastEvent = { type: 'sideshowAsked', seat, value: target };
      return true;
    }
    if (botAcceptsSideshow(this, target)) {
      this.resolveSideshow(seat, target);
    } else {
      this.lastEvent = { type: 'sideshowDeclined', seat: target, value: null };
      this.settleTurn();
    }
    return true;
  }

  /** The target's answer to a sideshow. Only the seat that was asked may answer. */
  replySideshow(seat: number, accept: boolean): boolean {
    const request = this.pendingSideshow;
    if (this.phase !== 'awaitingSideshowReply' || request === null || request.to !== seat) return false;
    this.pendingSideshow = null;
    this.phase = 'betting';
    if (accept) {
      this.resolveSideshow(request.from, request.to);
    } else {
      this.lastEvent = { type: 'sideshowDeclined', seat, value: null };
      this.settleTurn();
    }
    return true;
  }

  rebuy(seat: number): boolean {
    if (!this.canRebuy(seat)) return false;
    this.seats[seat].chips += REBUY_AMOUNT;
    this.totalInjected += REBUY_AMOUNT;
    this.lastEvent = { type: 'rebuy', seat, value: REBUY_AMOUNT };
    return true;
  }

  /**
   * A player left the table in the middle of a hand. The seat packs, and the hand
   * carries on without it. The seat itself becomes a bot, so it keeps its chips.
   */
  seatLeft(seat: number): void {
    if (this.phase === 'roundOver' || !this.isActive(seat)) return;
    const request = this.pendingSideshow;
    this.seats[seat].isFolded = true;
    this.seats[seat].lastAction = { kind: 'left', amount: null };
    this.lastEvent = { type: 'left', seat, value: null };

    if (this.phase === 'awaitingSideshowReply' && request !== null && (request.from === seat || request.to === seat)) {
      // Whichever side left, the question is over and the asker's turn is used up.
      this.pendingSideshow = null;
      this.phase = 'betting';
      this.settleTurn();
      return;
    }
    if (this.phase === 'betting' && this.currentTurn === seat) {
      this.settleTurn();
      return;
    }
    if (this.activeCount() <= 1) this.settleTurn();
  }

  /**
   * Deals a hand from a shuffled deck. Bots buy back in first. Returns false when
   * fewer than two seats have the buy-in.
   */
  startHand(deck: readonly string[]): boolean {
    if (deck.length !== 52) throw new Error('A Teen Patti deck has 52 cards');
    this.seats.forEach((s, seat) => {
      if (this.isBot[seat] && s.chips < MIN_BUY_IN) {
        s.chips += REBUY_AMOUNT;
        this.totalInjected += REBUY_AMOUNT;
      }
    });
    const playing = this.seats.map((_, seat) => seat).filter((seat) => this.seats[seat].chips >= MIN_BUY_IN);
    if (playing.length < 2) return false;

    this.dealer = (this.dealer + 1) % this.seats.length;
    let dealt = 0;
    this.seats.forEach((s, seat) => {
      const isPlaying = playing.includes(seat);
      s.playing = isPlaying;
      s.isFolded = !isPlaying;
      s.isSeen = false;
      s.blindTurns = 0;
      s.lastAction = null;
      if (isPlaying) {
        s.hand = deck.slice(dealt * 3, dealt * 3 + 3);
        dealt++;
        s.chips -= BOOT;
      } else {
        s.hand = [];
      }
    });
    this.pot = BOOT * playing.length;
    this.baseBet = START_BASE;
    this.phase = 'betting';
    this.result = null;
    this.revealed = null;
    this.pendingSideshow = null;
    this.handNumber++;
    this.currentTurn = this.nextSeatFrom(this.dealer, (seat) => this.seats[seat].playing);
    this.lastEvent = { type: 'dealt', seat: this.dealer, value: null };
    return true;
  }

  /**
   * Applies a person's action, from the seat that sent it. The seat may only act
   * for itself, and only when the rules allow it.
   */
  applyHuman(seat: number, action: TeenPattiAction, deck: () => string[]): void {
    const refuse = (message: string): never => {
      throw new TeenPattiRuleError(message);
    };
    switch (action.type) {
      case 'see':
        if (!this.see(seat)) refuse('You cannot look at your cards now.');
        return;
      case 'bet':
        if (!this.bet(seat)) refuse('You cannot play now.');
        return;
      case 'raise':
        if (!this.raise(seat)) refuse('You cannot raise now.');
        return;
      case 'pack':
        if (!this.pack(seat)) refuse('You cannot pack now.');
        return;
      case 'show':
        if (!this.show(seat)) refuse('You cannot ask for a show now.');
        return;
      case 'sideshow':
        if (!this.requestSideshow(seat)) refuse('You cannot ask for a sideshow now.');
        return;
      case 'sideshowReply':
        if (!this.replySideshow(seat, action.accept)) refuse('There is no sideshow for you to answer.');
        return;
      case 'rebuy':
        if (!this.rebuy(seat)) refuse('You cannot rebuy now.');
        return;
      case 'nextHand':
        if (this.phase !== 'roundOver') refuse('The hand is not over yet.');
        if (!this.startHand(deck())) refuse('Fewer than two players have chips to play.');
        return;
      default:
        return refuse('Unknown action.');
    }
  }

  /**
   * One step of the table: a bot acts, or a person's time has run out and the
   * table plays for them. Returns what happened, or null when the table is
   * waiting for a person who still has time.
   */
  advance(humanTurnExpired: boolean): 'bot' | 'auto' | null {
    if (this.phase === 'betting') {
      const seat = this.currentTurn;
      if (this.isBot[seat]) {
        playBotTurn(this, seat, this.random);
        return 'bot';
      }
      if (!humanTurnExpired) return null;
      this.pack(seat);
      return 'auto';
    }
    if (this.phase === 'awaitingSideshowReply' && this.pendingSideshow !== null) {
      if (!humanTurnExpired) return null;
      this.replySideshow(this.pendingSideshow.to, false);
      return 'auto';
    }
    return null;
  }

  /** When the table next waits on a person, the moment their time runs out. */
  turnDeadline(nowMs: number): number | null {
    if (this.phase === 'betting') return this.isBot[this.currentTurn] ? null : nowMs + HUMAN_TURN_MS;
    if (this.phase === 'awaitingSideshowReply' && this.pendingSideshow !== null) {
      return this.isBot[this.pendingSideshow.to] ? null : nowMs + HUMAN_TURN_MS;
    }
    return null;
  }

  // --- Internals. Each mirrors a private method of TeenPattiGame. ---

  private stake(seat: number, raised: boolean): void {
    const s = this.seats[seat];
    const wasBlind = !s.isSeen;
    const cost = this.costFor(seat);
    this.pay(seat, cost);
    const kind: LastActionKind = raised ? 'raise' : wasBlind ? 'blind' : 'chaal';
    s.lastAction = { kind, amount: cost };
    if (wasBlind) {
      s.blindTurns++;
      if (s.blindTurns >= MAX_BLIND_TURNS) s.isSeen = true;
    }
    this.lastEvent = { type: raised ? 'raise' : 'bet', seat, value: cost };
    this.settleTurn();
  }

  private pay(seat: number, amount: number): void {
    this.seats[seat].chips -= amount;
    this.pot += amount;
  }

  private resolveSideshow(from: number, to: number): void {
    const cmp = compareHands(this.seats[from].hand, this.seats[to].hand);
    const loser = cmp > 0 ? to : from; // a tie goes against the player who asked
    const winner = loser === from ? to : from;
    this.seats[loser].isFolded = true;
    this.seats[loser].lastAction = { kind: 'sideshowLost', amount: null };
    this.lastEvent = { type: 'sideshowResult', seat: loser, value: winner };
    this.settleTurn();
  }

  /** Ends the hand when one seat is left or the pot is full, or passes the turn on. */
  private settleTurn(): void {
    const active = this.activeSeats();
    if (active.length === 0) throw new Error('A hand has no active seat');
    if (active.length === 1) {
      this.awardLastStanding(active[0]);
      return;
    }
    if (this.pot >= POT_LIMIT) {
      this.showdown(active, null, true);
      return;
    }
    do {
      this.currentTurn = (this.currentTurn + 1) % this.seats.length;
    } while (!this.isActive(this.currentTurn));
  }

  private awardLastStanding(winner: number): void {
    const won = this.pot;
    this.seats[winner].chips += won;
    this.pot = 0;
    this.phase = 'roundOver';
    this.pendingSideshow = null;
    this.result = {
      winners: [winner],
      potWon: won,
      wasShowdown: false,
      handType: null,
      potLimitReached: false,
      requestedBy: null,
    };
    this.lastEvent = { type: 'lastStanding', seat: winner, value: won };
  }

  /** Compares the contenders' hands. A tie splits the pot; the first winner takes the odd chips. */
  private showdown(contenders: number[], requestedBy: number | null, potLimitReached: boolean): void {
    let best: Evaluation | null = null;
    let winners: number[] = [];
    for (const seat of contenders) {
      const evaluation = evaluate(this.seats[seat].hand);
      const cmp = best === null ? 1 : compareEvaluations(evaluation, best);
      if (cmp > 0) {
        best = evaluation;
        winners = [seat];
      } else if (cmp === 0) {
        winners.push(seat);
      }
    }
    if (best === null) throw new Error('A showdown needs a contender');

    const won = this.pot;
    const share = Math.floor(won / winners.length);
    winners.forEach((seat, i) => {
      this.seats[seat].chips += share + (i === 0 ? won - share * winners.length : 0);
    });
    this.pot = 0;
    this.phase = 'roundOver';
    this.pendingSideshow = null;
    const revealed: Record<string, string[]> = {};
    for (const seat of contenders) {
      this.seats[seat].isSeen = true;
      revealed[String(seat)] = [...this.seats[seat].hand];
    }
    this.revealed = revealed;
    this.result = {
      winners: [...winners],
      potWon: won,
      wasShowdown: true,
      handType: best.handType,
      potLimitReached,
      requestedBy,
    };
    this.lastEvent = { type: winners.length > 1 ? 'tie' : 'showdown', seat: winners[0], value: won };
  }

  private nextSeatFrom(seat: number, ok: (candidate: number) => boolean): number {
    for (let step = 1; step <= this.seats.length; step++) {
      const candidate = (seat + step) % this.seats.length;
      if (ok(candidate)) return candidate;
    }
    throw new Error('No seat is available');
  }
}

// --- Storage: the public state, the seat documents, and the rebuild from both ---

/** What every member may read. Hands are not in it, except the hands shown at a showdown. */
export function publicState(g: TeenPattiGame, step: number, nowMs: number): Record<string, unknown> {
  return {
    step,
    handNumber: g.handNumber,
    phase: g.phase,
    dealer: g.dealer,
    currentTurn: g.currentTurn,
    pot: g.pot,
    baseBet: g.baseBet,
    totalInjected: g.totalInjected,
    seats: g.seats.map((s) => ({
      chips: s.chips,
      playing: s.playing,
      isSeen: s.isSeen,
      isFolded: s.isFolded,
      blindTurns: s.blindTurns,
      lastAction: s.lastAction ? { kind: s.lastAction.kind, amount: s.lastAction.amount } : null,
    })),
    pendingSideshow: g.pendingSideshow ? { from: g.pendingSideshow.from, to: g.pendingSideshow.to } : null,
    result: g.result ? { ...g.result, winners: [...g.result.winners] } : null,
    revealed: g.revealed,
    lastEvent: g.lastEvent,
    turnDeadline: g.turnDeadline(nowMs),
  };
}

/** One seat's private document: its owner and its three cards. */
export interface SeatDoc {
  owner: string;
  seat: number;
  hand: string[];
}

export function seatDoc(g: TeenPattiGame, seat: number, owner: string): SeatDoc {
  return { owner, seat, hand: [...g.seats[seat].hand] };
}

/**
 * Rebuilds a table from its stored public state and its seat documents. The
 * cards are copied, so the game can play on them without changing what was read.
 */
export function restoreGame(
  state: Record<string, unknown>,
  seats: readonly SeatDoc[],
  isBot: readonly boolean[],
  random: () => number = secureRandom,
): TeenPattiGame {
  const g = new TeenPattiGame(isBot, random);
  const published = state.seats;
  if (!Array.isArray(published) || published.length !== g.seats.length || seats.length !== g.seats.length) {
    throw new Error('Corrupt seats');
  }
  g.phase = readPhase(state.phase);
  g.dealer = readInt(state.dealer, 'dealer');
  g.currentTurn = readInt(state.currentTurn, 'current turn');
  g.pot = readInt(state.pot, 'pot');
  g.baseBet = readInt(state.baseBet, 'base bet');
  g.totalInjected = readInt(state.totalInjected, 'chips added');
  g.handNumber = readInt(state.handNumber, 'hand number');
  g.pendingSideshow = readSideshow(state.pendingSideshow);
  g.result = readResult(state.result);
  g.revealed = readRevealed(state.revealed);
  g.lastEvent = (state.lastEvent as LastEvent | null) ?? null;
  for (let seat = 0; seat < g.seats.length; seat++) {
    const pub = published[seat] as Record<string, unknown>;
    const playing = pub.playing === true;
    g.seats[seat] = {
      chips: readInt(pub.chips, 'chips'),
      playing,
      isSeen: pub.isSeen === true,
      isFolded: pub.isFolded === true,
      blindTurns: readInt(pub.blindTurns, 'blind turns'),
      lastAction: readLastAction(pub.lastAction),
      hand: readHand(seats[seat].hand, playing),
    };
  }
  return g;
}

function readPhase(value: unknown): Phase {
  if (value === 'betting' || value === 'awaitingSideshowReply' || value === 'roundOver') return value;
  throw new Error('Corrupt phase');
}

function readInt(value: unknown, label: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value)) throw new Error(`Corrupt ${label}`);
  return value;
}

function readSideshow(value: unknown): SideshowRequest | null {
  if (value === null || value === undefined) return null;
  const v = value as Record<string, unknown>;
  return { from: readInt(v.from, 'sideshow'), to: readInt(v.to, 'sideshow') };
}

function readResult(value: unknown): HandResult | null {
  if (value === null || value === undefined) return null;
  const v = value as Record<string, unknown>;
  if (!Array.isArray(v.winners)) throw new Error('Corrupt result');
  return {
    winners: v.winners.map((w) => readInt(w, 'winner')),
    potWon: readInt(v.potWon, 'pot won'),
    wasShowdown: v.wasShowdown === true,
    handType: (v.handType as HandType | null) ?? null,
    potLimitReached: v.potLimitReached === true,
    requestedBy: v.requestedBy === null || v.requestedBy === undefined ? null : readInt(v.requestedBy, 'requested by'),
  };
}

function readRevealed(value: unknown): Record<string, string[]> | null {
  if (value === null || value === undefined) return null;
  const out: Record<string, string[]> = {};
  for (const [seat, cards] of Object.entries(value as Record<string, unknown>)) {
    if (!Array.isArray(cards) || !cards.every(isCard)) throw new Error('Corrupt revealed hands');
    out[seat] = [...(cards as string[])];
  }
  return out;
}

function readLastAction(value: unknown): LastAction | null {
  if (value === null || value === undefined) return null;
  const v = value as Record<string, unknown>;
  return { kind: v.kind as LastActionKind, amount: typeof v.amount === 'number' ? v.amount : null };
}

function readHand(value: unknown, playing: boolean): string[] {
  if (!Array.isArray(value) || !value.every(isCard) || value.length !== (playing ? 3 : 0)) {
    throw new Error('Corrupt hand');
  }
  return [...(value as string[])];
}
