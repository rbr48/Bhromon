import { BOT_AIM_NOISE, chooseShot } from '../carrom/bot';
import { CarromTable, Shot, colorOf, publicState, restoreTable } from '../carrom/game';
import {
  BASELINE_MAX,
  BASELINE_MIN,
  Piece,
  PieceType,
  STRIKER_ID,
  baselineY,
  makePiece,
  shotSpeed,
  simulateToRest,
  step,
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

// A break shot whose result test/features/game_zone/carrom_parity_test.dart
// checks on the phone's engine too. Both must agree bit for bit.
const GOLDEN_VX = 0.041423333219775885;
const GOLDEN_VY = -3.1862307445420464;
const GOLDEN_START: Array<[number, PieceType, number, number]> = [
  [0, 'queen', 0.5, 0.5],
  [1, 'white', 0.5, 0.54386],
  [2, 'black', 0.46201612579001455, 0.52193],
  [3, 'white', 0.4620161257900145, 0.47807],
  [4, 'black', 0.5, 0.45614],
  [5, 'white', 0.5379838742099855, 0.47807],
  [6, 'black', 0.5379838742099855, 0.52193],
  [7, 'black', 0.5, 0.58772],
  [8, 'white', 0.45614000000000005, 0.575967748419971],
  [9, 'black', 0.42403225158002905, 0.54386],
  [10, 'white', 0.41228, 0.5],
  [11, 'black', 0.42403225158002905, 0.45614000000000005],
  [12, 'white', 0.45614000000000005, 0.42403225158002905],
  [13, 'black', 0.5, 0.41228],
  [14, 'white', 0.5438599999999999, 0.424032251580029],
  [15, 'black', 0.5759677484199709, 0.45614],
  [16, 'white', 0.58772, 0.5],
  [17, 'black', 0.575967748419971, 0.54386],
  [18, 'white', 0.54386, 0.5759677484199709],
  [99, 'striker', 0.5, 0.845],
];
/** Where each coin comes to rest. */
const GOLDEN_END: Array<[number, number, number, boolean]> = [
  [0, 0.39909468590158453, 0.17328294054717144, false],
  [1, 0.5167747634618395, 0.5370611084713123, false],
  [2, 0.45885043551658583, 0.5189562165851487, false],
  [3, 0.44670603161652933, 0.47032891900113505, false],
  [4, 0.6473804822495929, 0.3452438132414054, false],
  [5, 0.5830937766731544, 0.450331434676579, false],
  [6, 0.5674600973129902, 0.49308408386878677, false],
  [7, 0.4247674984033129, 0.568871863184978, false],
  [8, 0.15503938167604112, 0.7893282107373064, false],
  [9, 0.38737019457281474, 0.5465748123214239, false],
  [10, 0.4030048669795413, 0.48426615530294176, false],
  [11, 0.18741871994278278, 0.08416732742074995, false],
  [12, 0.3841581677362726, 0.4107264548819789, false],
  [13, 0.4907153523868395, 0.4886402011565425, false],
  [14, 0.6073500191252046, 0.3802232166340815, false],
  [15, 0.9072188133325689, 0.1615356671629447, false],
  [16, 0.6340456713861573, 0.46171026608610755, false],
  [17, 0.773478877766681, 0.5290815552436978, false],
  [18, 0.5948915798383954, 0.6682263769038964, false],
];

describe('carrom fixes', () => {
  it('a break shot ends where the phone\'s engine puts it', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    expect(table.pieces.map((p) => [p.id, p.type, p.x, p.y])).toEqual(GOLDEN_START);
    expect(table.resolveShot(0, 0.5, -Math.PI / 2 + 0.013, 0.93)).toBe(true);
    expect(table.lastShot!.vx).toBe(GOLDEN_VX);
    expect(table.lastShot!.vy).toBe(GOLDEN_VY);

    const pieces = GOLDEN_START.map(([id, type, x, y]) => makePiece(id, type, x, y));
    pieces[pieces.length - 1].vx = GOLDEN_VX;
    pieces[pieces.length - 1].vy = GOLDEN_VY;
    simulateToRest(pieces);
    // The coins only: after scoring, the server puts the striker back on a baseline.
    expect(pieces.slice(0, -1).map((p) => [p.id, p.x, p.y, p.pocketed])).toEqual(GOLDEN_END);
  });

  it('covering the queen with your last coin wins the board, and the match carries on', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    const whites = table.coins.filter((c) => c.type === 'white');
    for (const w of whites.slice(0, 8)) w.pocketed = true;
    score(table, whites.slice(0, 8));
    const queen = queenOf(table);
    queen.pocketed = true;
    whites[8].pocketed = true;
    score(table, [queen, whites[8]]);
    expect(table.boardWinner).toBe(0);
    expect(table.boardPoints).toBe(12);
    expect(table.matchScore).toEqual([12, 0]);
    expect(table.phase).toBe('aiming');
    expect(table.board).toBe(2);
    expect(table.currentPlayer).toBe(1);
    expect(table.remaining(0)).toBe(9);
  });

  it('a queen awaiting cover may be covered by the last coin on the next shot', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    const whites = table.coins.filter((c) => c.type === 'white');
    for (const w of whites.slice(0, 8)) w.pocketed = true;
    score(table, whites.slice(0, 8));
    const queen = queenOf(table);
    queen.pocketed = true;
    score(table, [queen]);
    expect(table.queenPendingFor).toBe(0);
    whites[8].pocketed = true;
    score(table, [whites[8]]);
    expect(table.boardWinner).toBe(0);
  });

  it('the match ends at 25, and the queen stops counting at 22', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    table.matchScore = [22, 0];
    const whites = table.coins.filter((c) => c.type === 'white');
    for (const w of whites.slice(0, 8)) w.pocketed = true;
    score(table, whites.slice(0, 8));
    const queen = queenOf(table);
    queen.pocketed = true;
    whites[8].pocketed = true;
    score(table, [queen, whites[8]]);
    expect(table.boardPoints).toBe(9);
    expect(table.phase).toBe('gameOver');
    expect(table.winner).toBe(0);
    expect(table.winnerPoints).toBe(31);
  });

  it('hitting and pocketing a coin in bottom pocket is legal and not a foul', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    table.queenCoveredBy = 0;
    const coin = table.coins.find((c) => c.type === 'white')!;
    coin.x = 0.06;
    coin.y = 0.90;
    const dx = coin.x - 0.35;
    const dy = coin.y - baselineY(0);
    const angle = Math.atan2(dy, dx);
    expect(table.resolveShot(0, 0.35, angle, 0.35)).toBe(true);
    expect(table.status).not.toContain('behind the baseline');
    expect(table.status).not.toContain('Foul');
  });

  it('player colors alternate each board (White breaks, then swaps to Black)', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    expect(table.board).toBe(1);
    expect(colorOf(0, table.board)).toBe('white');
    expect(colorOf(1, table.board)).toBe('black');
    expect(table.breaker).toBe(0);

    table.board = 2;
    expect(colorOf(0, table.board)).toBe('black');
    expect(colorOf(1, table.board)).toBe('white');
    expect(table.breaker).toBe(1);

    table.board = 3;
    expect(colorOf(0, table.board)).toBe('white');
    expect(colorOf(1, table.board)).toBe('black');
    expect(table.breaker).toBe(0);
  });

  it('a coin too fast for a pocket rattles out', () => {
    const coin = makePiece(1, 'white', 0.9, 0.9);
    coin.vx = 3;
    coin.vy = 3;
    const dropped: Piece[] = [];
    for (let i = 0; i < 12; i++) dropped.push(...step([coin]));
    expect(dropped).toEqual([]);
  });

  it('stores and restores the match and the shot velocity', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    table.matchScore = [5, 7];
    table.board = 3;
    expect(table.resolveShot(table.currentPlayer, 0.5, -Math.PI / 2, 0.5)).toBe(true);
    const restored = restoreTable(publicState(table, 4, null), ['Asha', 'Babu']);
    expect(restored.matchScore).toEqual(table.matchScore);
    expect(restored.board).toBe(3);
    expect(restored.lastShot).toEqual(table.lastShot);
  });

  it('reads a board stored before match scoring as a first board', () => {
    const table = CarromTable.fresh(['Asha', 'Babu']);
    const state = publicState(table, 1, null);
    delete state.matchScore;
    delete state.board;
    const restored = restoreTable(state, ['Asha', 'Babu']);
    expect(restored.matchScore).toEqual([0, 0]);
    expect(restored.board).toBe(1);
  });
});
