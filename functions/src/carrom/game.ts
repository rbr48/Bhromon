/**
 * A carrom board on the server: the ICF rules of the phone's game
 * (lib/features/game_zone/carrom/carrom_game.dart), run once for the table.
 * The board is public, so the state holds every piece. A shot is simulated and
 * scored inside one call, so the table never waits in a "moving" state.
 */

import {
  BASELINE_MAX,
  BASELINE_MIN,
  COIN_RADIUS,
  MAX_SHOT_SECONDS,
  Piece,
  PieceType,
  STEP_SECONDS,
  STRIKER_ID,
  STRIKER_RADIUS,
  baselineY,
  isSettled,
  makePiece,
  shotSpeed,
  step,
} from './physics';

export type Phase = 'aiming' | 'gameOver';

export interface Shot {
  x: number;
  angle: number;
  power: number;
}

export interface LastShot extends Shot {
  shooter: number;
}

export const COINS_PER_PLAYER = 9;

function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}

function clampRange(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function colorOf(player: number): PieceType {
  return player === 0 ? 'white' : 'black';
}

/** Queen in the middle, a ring of 6 and a ring of 12, colours alternating. */
function initialLayout(): Piece[] {
  const r = COIN_RADIUS * 1.02;
  const pieces: Piece[] = [makePiece(0, 'queen', 0.5, 0.5)];
  let id = 1;
  for (let i = 0; i < 6; i++) {
    const a = Math.PI / 2 + (i * Math.PI) / 3;
    pieces.push(
      makePiece(id++, i % 2 === 0 ? 'white' : 'black', 0.5 + Math.cos(a) * 2 * r, 0.5 + Math.sin(a) * 2 * r),
    );
  }
  for (let i = 0; i < 12; i++) {
    const a = Math.PI / 2 + (i * Math.PI) / 6;
    pieces.push(
      makePiece(id++, i % 2 === 0 ? 'black' : 'white', 0.5 + Math.cos(a) * 4 * r, 0.5 + Math.sin(a) * 4 * r),
    );
  }
  return pieces;
}

export class CarromTable {
  phase: Phase = 'aiming';
  currentPlayer = 0;
  /** Coin ids that each player has pocketed, in the order they went down. */
  pocketed: [number[], number[]] = [[], []];
  queenCoveredBy: number | null = null;
  /** The player who pocketed the queen and still has to cover her. */
  queenPendingFor: number | null = null;
  /** Penalty coins a player owes, each taken back from their next coin pocketed. */
  penaltyDue: [number, number] = [0, 0];
  winner: number | null = null;
  winnerPoints = 0;
  status = '';
  strikerX = 0.5;
  lastShot: LastShot | null = null;

  /** The 19 coins (queen first), on the board or in a pocket. */
  readonly coins: Piece[];
  readonly striker: Piece;

  constructor(readonly names: [string, string], coins: Piece[], striker: Piece) {
    this.coins = coins;
    this.striker = striker;
  }

  /** A new board: the break is player 0's. */
  static fresh(names: [string, string]): CarromTable {
    const table = new CarromTable(names, initialLayout(), makePiece(STRIKER_ID, 'striker', 0.5, baselineY(0)));
    table.setUpStriker();
    table.status = `${names[0]} breaks. Slide the striker along the baseline, then drag back and let go to shoot.`;
    return table;
  }

  /** Every piece on the board: the coins, then the striker. */
  get pieces(): Piece[] {
    return [...this.coins, this.striker];
  }

  queen(): Piece {
    const queen = this.coins.find((c) => c.type === 'queen');
    if (!queen) throw new Error('The board has no queen');
    return queen;
  }

  remaining(player: number): number {
    return this.coins.filter((c) => c.type === colorOf(player) && !c.pocketed).length;
  }

  nameOf(player: number): string {
    return this.names[player];
  }

  /** The striker may sit anywhere on the baseline where it doesn't touch a coin. */
  canPlaceStriker(x: number): boolean {
    const clamped = clampRange(x, BASELINE_MIN, BASELINE_MAX);
    return !this.overlapsCoin(clamped, baselineY(this.currentPlayer), STRIKER_RADIUS);
  }

  strikerPlacementValid(): boolean {
    return this.canPlaceStriker(this.strikerX);
  }

  placeStriker(x: number): void {
    if (this.phase !== 'aiming') return;
    this.strikerX = clampRange(x, BASELINE_MIN, BASELINE_MAX);
    this.striker.pocketed = false;
    this.striker.vx = 0;
    this.striker.vy = 0;
    this.striker.x = this.strikerX;
    this.striker.y = baselineY(this.currentPlayer);
  }

  /**
   * Plays the current player's shot: places the striker, fires it, runs the
   * physics until the board is still, and scores it. Returns false when the
   * shot cannot be played, and the caller then stores nothing.
   */
  resolveShot(shooter: number, x: number, angle: number, power: number): boolean {
    if (this.phase !== 'aiming' || shooter !== this.currentPlayer) return false;
    this.placeStriker(x);
    if (!this.shoot(angle, power)) return false;
    this.lastShot = { shooter, x: this.strikerX, angle, power: clamp01(power) };
    this.runToRest();
    return true;
  }

  private shoot(angle: number, power: number): boolean {
    if (this.phase !== 'aiming' || !this.strikerPlacementValid()) return false;
    this.placeStriker(this.strikerX);
    const speed = shotSpeed(power);
    this.striker.vx = Math.cos(angle) * speed;
    this.striker.vy = Math.sin(angle) * speed;
    return true;
  }

  /** Runs the shot one fixed step at a time until the board is still, or the time is up. */
  private runToRest(): void {
    const pieces = this.pieces;
    const pocketedThisShot: Piece[] = [];
    let shotSeconds = 0;
    for (;;) {
      pocketedThisShot.push(...step(pieces));
      shotSeconds += STEP_SECONDS;
      if (isSettled(pieces) || shotSeconds > MAX_SHOT_SECONDS) {
        for (const p of pieces) {
          p.vx = 0;
          p.vy = 0;
        }
        this.scoreShot(pocketedThisShot);
        return;
      }
    }
  }

  private overlapsCoin(x: number, y: number, radius: number, ignore?: Piece): boolean {
    for (const c of this.coins) {
      if (c.pocketed || c === ignore) continue;
      const dx = c.x - x;
      const dy = c.y - y;
      const minDist = c.radius + radius;
      if (dx * dx + dy * dy < minDist * minDist) return true;
    }
    return false;
  }

  private pieceById(id: number): Piece {
    const piece = this.coins.find((c) => c.id === id);
    if (!piece) throw new Error(`No coin with id ${id}`);
    return piece;
  }

  private popPocketed(player: number): Piece {
    const id = this.pocketed[player].pop();
    if (id === undefined) throw new Error('No coin to take back');
    return this.pieceById(id);
  }

  private removePocketed(player: number, id: number): void {
    const index = this.pocketed[player].indexOf(id);
    if (index >= 0) this.pocketed[player].splice(index, 1);
  }

  /**
   * Applies the ICF rules to the pieces that went down during the shot just
   * played. Fouls send the shot's own coins back, the queen too when she was in
   * play, and cost one penalty coin; a legal shot keeps the turn only when a
   * coin of the shooter's own colour went down.
   */
  private scoreShot(pocketedNow: Piece[]): void {
    const player = this.currentPlayer;
    const opp = 1 - player;
    const messages: string[] = [];
    const who = this.nameOf(player);
    const whose = `${who}${player === 0 ? 'r' : "'s"}`;

    const ownNow = pocketedNow.filter((p) => p.type === colorOf(player));
    const oppNow = pocketedNow.filter((p) => p.type === colorOf(opp));
    let queenNow = pocketedNow.some((p) => p.type === 'queen');
    const queenWasCovered = this.queenCoveredBy !== null;

    this.pocketed[player].push(...ownNow.map((p) => p.id));
    this.pocketed[opp].push(...oppNow.map((p) => p.id));

    // --- Fouls (ICF) ---
    const fouls: string[] = [];
    if (pocketedNow.some((p) => p.type === 'striker')) fouls.push('striker pocketed');
    if (ownNow.length > 0 && this.remaining(player) === 0 && !queenWasCovered) {
      fouls.push('last coin pocketed before the Queen was covered');
    }
    if (oppNow.length > 0 && this.remaining(opp) === 0) {
      fouls.push(`${this.nameOf(opp)}${opp === 0 ? 'r' : "'s"} last coin pocketed`);
    }

    if (fouls.length > 0) {
      // Everything of yours from this shot comes back, the Queen too, and
      // the opponent's last coin if that was the foul.
      for (const c of ownNow) {
        this.removePocketed(player, c.id);
        this.returnToCentre(c);
      }
      if (oppNow.length > 0 && this.remaining(opp) === 0) {
        this.returnToCentre(this.popPocketed(opp));
      }
      if (queenNow || this.queenPendingFor === player) {
        this.returnToCentre(this.queen());
        queenNow = false;
        this.queenPendingFor = null;
      }
      const penalty = this.takePenalty(player);
      messages.push(`Foul - ${fouls.join(', ')}! ${penalty}`);
      this.currentPlayer = opp;
      this.finishTurn(messages, false, player);
      return;
    }

    // --- Legal shot ---
    if (queenNow && this.pocketed[player].length === 0) {
      // You need a coin of your own pocketed (this shot counts) before taking the Queen.
      this.returnToCentre(this.queen());
      queenNow = false;
      messages.push('The Queen can only be taken after pocketing a coin of your own - she returns to the centre.');
    }

    if (queenNow) {
      if (ownNow.length > 0) {
        this.queenCoveredBy = player;
        this.queenPendingFor = null;
        messages.push(`${who} covered the Queen! (+3)`);
      } else {
        this.queenPendingFor = player;
        messages.push('Queen pocketed! Pocket one of your coins next shot to cover her.');
      }
    } else if (this.queenPendingFor === player) {
      if (ownNow.length > 0) {
        this.queenCoveredBy = player;
        messages.push(`${who} covered the Queen! (+3)`);
      } else {
        this.returnToCentre(this.queen());
        messages.push('Queen not covered - she returns to the centre.');
      }
      this.queenPendingFor = null;
    }

    if (ownNow.length > 0) {
      messages.push(`${who} pocketed ${ownNow.length} coin${ownNow.length === 1 ? '' : 's'}.`);
    }
    if (oppNow.length > 0) {
      messages.push(
        `${oppNow.length} ${opp === 0 ? 'white' : 'black'} coin${oppNow.length === 1 ? '' : 's'} went down for ${this.nameOf(opp)}.`,
      );
    }

    // A penalty owed from an earlier foul is paid from the coins just pocketed.
    let paid = 0;
    while (this.penaltyDue[player] > 0 && ownNow.length > 0 && this.pocketed[player].length > 0) {
      this.returnToCentre(this.popPocketed(player));
      this.penaltyDue[player]--;
      paid++;
    }
    if (paid > 0) {
      messages.push(`${paid} due penalty coin${paid === 1 ? '' : 's'} of ${whose} returned to the centre.`);
    }

    for (const p of [player, opp]) {
      if (this.remaining(p) === 0 && this.queenCoveredBy !== null) {
        this.winner = p;
        this.winnerPoints = this.remaining(1 - p) + (this.queenCoveredBy === p ? 3 : 0);
        this.phase = 'gameOver';
        this.status = `${messages.join(' ')} ${this.nameOf(p)} wins the board with ${this.winnerPoints} points!`.trim();
        return;
      }
    }

    const continueTurn = ownNow.length > 0 || (queenNow && this.queenPendingFor === player);
    if (!continueTurn) {
      if (this.queenPendingFor === player) {
        this.returnToCentre(this.queen());
        this.queenPendingFor = null;
        messages.push('Queen not covered - she returns to the centre.');
      }
      if (messages.length === 0) messages.push('Nothing pocketed.');
      this.currentPlayer = opp;
    }
    this.finishTurn(messages, continueTurn, player);
  }

  /** Returns one of [player]'s pocketed coins to the centre, or records it as due. */
  private takePenalty(player: number): string {
    const whose = `${this.nameOf(player)}${player === 0 ? 'r' : "'s"}`;
    if (this.pocketed[player].length > 0) {
      this.returnToCentre(this.popPocketed(player));
      return `One of ${whose} coins goes back to the centre as a penalty.`;
    }
    this.penaltyDue[player]++;
    return `A penalty coin is now due from ${whose} next pocketed coin.`;
  }

  private finishTurn(messages: string[], continueTurn: boolean, shooter: number): void {
    this.setUpStriker();
    const next = `${this.nameOf(this.currentPlayer)}'s turn.`;
    const again = `${this.nameOf(shooter)} shoots again!`;
    this.status = `${messages.join(' ')} ${continueTurn ? again : next}`;
  }

  /** Puts a coin back on the board as close to the centre as possible. */
  private returnToCentre(coin: Piece): void {
    coin.pocketed = false;
    coin.vx = 0;
    coin.vy = 0;
    for (let ring = 0; ring < 12; ring++) {
      const steps = ring === 0 ? 1 : 6 * ring;
      for (let k = 0; k < steps; k++) {
        const a = (2 * Math.PI * k) / steps;
        const x = 0.5 + Math.cos(a) * ring * COIN_RADIUS * 2.1;
        const y = 0.5 + Math.sin(a) * ring * COIN_RADIUS * 2.1;
        if (!this.overlapsCoin(x, y, coin.radius, coin)) {
          coin.x = x;
          coin.y = y;
          return;
        }
      }
    }
  }

  /** Puts the striker on the current player's baseline, at the first free spot near the middle. */
  private setUpStriker(): void {
    for (let i = 0; i <= 30; i++) {
      const offset = Math.floor((i + 1) / 2) * 0.02 * (i % 2 === 1 ? 1 : -1);
      const x = 0.5 + offset;
      if (x < BASELINE_MIN || x > BASELINE_MAX) continue;
      this.strikerX = x;
      if (this.canPlaceStriker(x)) break;
    }
    this.phase = 'aiming';
    this.placeStriker(this.strikerX);
  }
}

/** The board's public state: every piece, the scores, and whose shot it is. */
export function publicState(t: CarromTable, step: number, turnDeadline: number | null): Record<string, unknown> {
  return {
    step,
    phase: t.phase,
    currentPlayer: t.currentPlayer,
    winner: t.winner,
    winnerPoints: t.winnerPoints,
    queenCoveredBy: t.queenCoveredBy,
    queenPendingFor: t.queenPendingFor,
    penaltyDue: [...t.penaltyDue],
    // A map, not a list of lists: Firestore does not store arrays inside arrays.
    pocketed: { '0': [...t.pocketed[0]], '1': [...t.pocketed[1]] },
    strikerX: t.strikerX,
    pieces: t.pieces.map((p) => ({ id: p.id, type: p.type, x: p.x, y: p.y, pocketed: p.pocketed })),
    status: t.status,
    lastShot: t.lastShot ? { ...t.lastShot } : null,
    turnDeadline,
  };
}

/** Rebuilds a board from its stored public state. The pieces are at rest. */
export function restoreTable(state: Record<string, unknown>, names: [string, string]): CarromTable {
  const rawPieces = state.pieces;
  if (!Array.isArray(rawPieces)) throw new Error('Corrupt board');
  const pieces: Piece[] = rawPieces.map((raw) => {
    const r = raw as Record<string, unknown>;
    const type = r.type as PieceType;
    const piece = makePiece(Number(r.id), type, Number(r.x), Number(r.y));
    piece.pocketed = r.pocketed === true;
    return piece;
  });
  const striker = pieces.find((p) => p.type === 'striker');
  if (!striker) throw new Error('Corrupt board: no striker');
  const coins = pieces.filter((p) => p.type !== 'striker');

  const t = new CarromTable(names, coins, striker);
  t.phase = state.phase as Phase;
  t.currentPlayer = Number(state.currentPlayer);
  const pocketed = state.pocketed as Record<string, number[]>;
  t.pocketed = [[...pocketed['0']], [...pocketed['1']]];
  t.queenCoveredBy = state.queenCoveredBy === null || state.queenCoveredBy === undefined ? null : Number(state.queenCoveredBy);
  t.queenPendingFor = state.queenPendingFor === null || state.queenPendingFor === undefined ? null : Number(state.queenPendingFor);
  const penalty = state.penaltyDue as [number, number];
  t.penaltyDue = [Number(penalty[0]), Number(penalty[1])];
  t.winner = state.winner === null || state.winner === undefined ? null : Number(state.winner);
  t.winnerPoints = Number(state.winnerPoints);
  t.status = String(state.status ?? '');
  t.strikerX = Number(state.strikerX);
  const last = state.lastShot as Record<string, unknown> | null;
  t.lastShot = last
    ? { shooter: Number(last.shooter), x: Number(last.x), angle: Number(last.angle), power: Number(last.power) }
    : null;
  return t;
}
