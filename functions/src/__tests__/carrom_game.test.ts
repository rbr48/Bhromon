import { BOT_AIM_NOISE, chooseShot } from '../carrom/bot';
import { CarromTable, Shot } from '../carrom/game';
import {
  BASELINE_MAX,
  BASELINE_MIN,
  Piece,
  STRIKER_ID,
  makePiece,
  shotSpeed,
  simulateToRest,
} from '../carrom/physics';

function prng(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** The scoring step, reached directly so a rule can be tested without a physics run. */
function score(table: CarromTable, pocketedNow: Piece[]): void {
  (table as unknown as { scoreShot(p: Piece[]): void }).scoreShot(pocketedNow);
}

function queenOf(table: CarromTable): Piece {
  return table.queen();
}

describe('carrom physics', () => {
  it('a coin struck by the striker moves on, and the striker slows down', () => {
    const striker = makePiece(STRIKER_ID, 'striker', 0.5, 0.7);
    const coin = makePiece(1, 'white', 0.5, 0.5);
    striker.vy = -shotSpeed(0.8);
    const pieces = [coin, striker];
    simulateToRest(pieces, 20);
    expect(coin.y).not.toBe(0.5);
    expect(pieces.every((p) => p.pocketed || (p.vx === 0 && p.vy === 0))).toBe(true);
  });

  it('a coin sent at a corner pocket drops in, and is reported as pocketed', () => {
    const coin = makePiece(1, 'white', 0.2, 0.2);
    coin.vx = -0.8;
    coin.vy = -0.8;
    const dropped = simulateToRest([coin], 20);
    expect(dropped).toContain(coin);
    expect(coin.pocketed).toBe(true);
  });

  it('the same shot gives the same result every time', () => {
    const run = () => {
      const coin = makePiece(1, 'black', 0.3, 0.4);
      const striker = makePiece(STRIKER_ID, 'striker', 0.4, 0.8);
      striker.vx = 0.4;
      striker.vy = -shotSpeed(0.9);
      simulateToRest([coin, striker], 20);
      return [coin.x, coin.y, striker.x, striker.y];
    };
    expect(run()).toEqual(run());
  });
});

describe('carrom board layout', () => {
  it('starts with the queen in the middle, nine coins of each colour, and a free striker', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    expect(table.coins).toHaveLength(19);
    expect(table.coins.filter((c) => c.type === 'white')).toHaveLength(9);
    expect(table.coins.filter((c) => c.type === 'black')).toHaveLength(9);
    expect(queenOf(table).x).toBe(0.5);
    expect(queenOf(table).y).toBe(0.5);
    expect(table.phase).toBe('aiming');
    expect(table.currentPlayer).toBe(0);
    expect(table.strikerPlacementValid()).toBe(true);
    expect(table.striker.y).toBeGreaterThan(0.8);
  });
});

describe('carrom rules, scored from the pocketed pieces', () => {
  it('a coin of the shooter’s own colour keeps the turn', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    const white = table.coins.find((c) => c.type === 'white')!;
    white.pocketed = true;
    score(table, [white]);
    expect(table.pocketed[0]).toEqual([white.id]);
    expect(table.currentPlayer).toBe(0);
  });

  it('pocketing the striker is a foul: the turn passes, and a penalty is due', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    table.striker.pocketed = true;
    score(table, [table.striker]);
    expect(table.currentPlayer).toBe(1);
    expect(table.penaltyDue[0]).toBe(1);
  });

  it('a queen pocketed without a coin of your own goes back to the centre', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    const queen = queenOf(table);
    queen.pocketed = true;
    score(table, [queen]);
    expect(queen.pocketed).toBe(false);
    expect(table.queenPendingFor).toBeNull();
    expect(table.currentPlayer).toBe(1);
  });

  it('a queen pocketed with a coin of your own is covered at once', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    const queen = queenOf(table);
    queen.pocketed = true;
    const white = table.coins.find((c) => c.type === 'white')!;
    white.pocketed = true;
    score(table, [queen, white]);
    expect(table.queenCoveredBy).toBe(0);
    expect(table.currentPlayer).toBe(0);
  });

  it('pocketing your own last coin before the queen is covered is a foul, and the coin comes back', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    const whites = table.coins.filter((c) => c.type === 'white');
    for (const w of whites.slice(0, 8)) w.pocketed = true;
    const last = whites[8];
    last.pocketed = true;
    score(table, [last]);
    expect(last.pocketed).toBe(false);
    expect(table.currentPlayer).toBe(1);
    expect(table.penaltyDue[0]).toBe(1);
  });
});

describe('carrom bot', () => {
  it('chooses a shot the rules accept from the starting board', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    const shot: Shot = chooseShot(table, 0, BOT_AIM_NOISE, () => 0.5);
    expect(shot.x).toBeGreaterThanOrEqual(BASELINE_MIN);
    expect(shot.x).toBeLessThanOrEqual(BASELINE_MAX);
    expect(shot.power).toBeGreaterThanOrEqual(0);
    expect(shot.power).toBeLessThanOrEqual(1);
    expect(Number.isFinite(shot.angle)).toBe(true);
    expect(table.resolveShot(0, shot.x, shot.angle, shot.power)).toBe(true);
  });

  it('two bots keep every coin accounted for shot by shot', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    const rnd = prng(7);
    for (let shots = 0; shots < 8 && table.phase === 'aiming'; shots++) {
      const shooter = table.currentPlayer;
      const shot = chooseShot(table, shooter, BOT_AIM_NOISE, rnd);
      expect(table.resolveShot(shooter, shot.x, shot.angle, shot.power)).toBe(true);

      const flagged = table.coins.filter((c) => c.pocketed).length;
      const listed = table.pocketed[0].length + table.pocketed[1].length;
      const queenDown = queenOf(table).pocketed ? 1 : 0;
      expect(flagged).toBe(listed + queenDown);
    }
  });
});
