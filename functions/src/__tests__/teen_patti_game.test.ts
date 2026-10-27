import { compareHands, evaluate, fullDeck, handStrength } from '../teenPatti/cards';
import { TeenPattiGame, publicState, restoreGame, seatDoc } from '../teenPatti/game';
import { BOOT, MAX_BASE, MIN_BUY_IN, POT_LIMIT, REBUY_AMOUNT, START_BASE, STARTING_CHIPS } from '../teenPatti/rules';

const HUMANS = [false, false, false, false];

/** A small seeded generator, so every deal in these tests is reproducible. */
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

/** A deck shuffled from a seed (Fisher-Yates over the seeded generator). */
function seededDeck(seed: number): string[] {
  const rnd = prng(seed);
  const deck = fullDeck();
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

/** A deck whose first cards are the given hands, in seat order. The rest of the deck follows. */
function riggedDeck(hands: string[][]): string[] {
  const dealt = hands.flat();
  return [...dealt, ...fullDeck().filter((c) => !dealt.includes(c))];
}

/** A table where every seat holds the starting chips, and no hand has been dealt. */
function freshTable(isBot: boolean[] = HUMANS, seed = 1): TeenPattiGame {
  const g = new TeenPattiGame(isBot, prng(seed));
  for (const s of g.seats) s.chips = STARTING_CHIPS;
  return g;
}

/** A table in its first hand, dealt from the given hands (one per playing seat, in seat order). */
function dealtTable(hands: string[][], isBot: boolean[] = HUMANS): TeenPattiGame {
  const g = freshTable(isBot);
  expect(g.startHand(riggedDeck(hands))).toBe(true);
  return g;
}

/** The chips and the pot always add up to the chips the table started with, plus the rebuys. */
function booksBalance(g: TeenPattiGame): boolean {
  const chips = g.seats.reduce((sum, s) => sum + s.chips, 0);
  return chips + g.pot === 4 * STARTING_CHIPS + g.totalInjected;
}

/** No seat's cards appear in the public state, except the hands shown at a showdown. */
function hiddenCardsStayHidden(g: TeenPattiGame): boolean {
  const shown = JSON.stringify(publicState(g, 0, 0));
  const revealed = new Set(Object.keys(g.revealed ?? {}));
  return g.seats.every(
    (s, seat) => revealed.has(String(seat)) || s.hand.every((card) => !shown.includes(`"${card}"`)),
  );
}

/** A table rebuilt from what is stored offers exactly the same moves. */
function restoredMatches(g: TeenPattiGame): boolean {
  const restored = restoreGame(
    publicState(g, 0, 0),
    g.seats.map((_, seat) => seatDoc(g, seat, 'owner')),
    g.isBot,
  );
  return g.seats.every(
    (_, seat) =>
      restored.canSee(seat) === g.canSee(seat) &&
      restored.canBet(seat) === g.canBet(seat) &&
      restored.canRaise(seat) === g.canRaise(seat) &&
      restored.canShow(seat) === g.canShow(seat) &&
      restored.canSideshow(seat) === g.canSideshow(seat) &&
      restored.canRebuy(seat) === g.canRebuy(seat) &&
      restored.isTurnOf(seat) === g.isTurnOf(seat),
  );
}

/** One person's move: a random option that the rules allow for them. */
function humanMove(g: TeenPattiGame, seat: number, rnd: () => number): void {
  const options: Array<() => boolean> = [];
  if (g.canSee(seat)) options.push(() => g.see(seat));
  if (g.canBet(seat)) options.push(() => g.bet(seat));
  if (g.canRaise(seat)) options.push(() => g.raise(seat));
  if (g.canShow(seat)) options.push(() => g.show(seat));
  if (g.canSideshow(seat)) options.push(() => g.requestSideshow(seat));
  options.push(() => g.pack(seat));
  const pick = options[Math.floor(rnd() * options.length)];
  expect(pick()).toBe(true);
}

describe('Teen Patti hand ranking', () => {
  it('counts every three-card hand the way the rules do', () => {
    const deck = fullDeck();
    const counts: Record<string, number> = {};
    for (let i = 0; i < deck.length; i++) {
      for (let j = i + 1; j < deck.length; j++) {
        for (let k = j + 1; k < deck.length; k++) {
          const type = evaluate([deck[i], deck[j], deck[k]]).handType;
          counts[type] = (counts[type] ?? 0) + 1;
        }
      }
    }
    expect(counts).toEqual({
      trail: 52,
      pureSequence: 48,
      sequence: 720,
      color: 1096,
      pair: 3744,
      highCard: 16440,
    });
  });

  it('ranks trail over pure run over run over colour over pair over high card', () => {
    const trail = ['7S', '7H', '7D'];
    const pureRun = ['5H', '6H', '7H'];
    const run = ['5S', '6H', '7D'];
    const colour = ['2C', '9C', 'KC'];
    const pair = ['QS', 'QH', '3D'];
    const high = ['AS', '9H', '4D'];
    const ladder = [trail, pureRun, run, colour, pair, high];
    for (let i = 0; i < ladder.length - 1; i++) {
      expect(compareHands(ladder[i], ladder[i + 1])).toBeGreaterThan(0);
    }
  });

  it('plays A-K-Q as the top run and A-2-3 as the lowest', () => {
    expect(evaluate(['AS', 'KH', 'QD']).primary).toBe(14);
    expect(compareHands(['AS', 'KH', 'QD'], ['KS', 'QH', 'JD'])).toBeGreaterThan(0);
    expect(evaluate(['AS', '2H', '3D']).primary).toBe(3);
    expect(compareHands(['2S', '3H', '4D'], ['AS', '2H', '3D'])).toBeGreaterThan(0);
  });
});

describe('Teen Patti deal', () => {
  it('deals three cards to each seat, takes the boot from each, and starts after the dealer', () => {
    const g = dealtTable([
      ['AS', '9S', '4D'],
      ['2H', '7D', '9C'],
      ['3C', 'JS', '6H'],
      ['JC', 'JD', '8H'],
    ]);
    expect(g.seats.map((s) => s.hand)).toEqual([
      ['AS', '9S', '4D'],
      ['2H', '7D', '9C'],
      ['3C', 'JS', '6H'],
      ['JC', 'JD', '8H'],
    ]);
    expect(g.pot).toBe(4 * BOOT);
    expect(g.seats.every((s) => s.chips === STARTING_CHIPS - BOOT)).toBe(true);
    expect(g.phase).toBe('betting');
    expect(g.currentTurn).toBe(1);
    expect(booksBalance(g)).toBe(true);
  });

  it('sits a seat out when it cannot cover the buy-in, and needs two players to deal', () => {
    const g = freshTable();
    g.seats[2].chips = MIN_BUY_IN - 1;
    expect(g.startHand(riggedDeck([['AS', 'KS', '2D'], ['3H', '4H', '9C'], ['5C', '6C', '7C']]))).toBe(true);
    expect(g.seats[2].playing).toBe(false);
    expect(g.seats[2].hand).toEqual([]);
    expect(g.pot).toBe(3 * BOOT);

    const short = freshTable();
    short.seats[1].chips = 0;
    short.seats[2].chips = 0;
    short.seats[3].chips = 0;
    expect(short.startHand(seededDeck(3))).toBe(false);
  });

  it('bots buy back in before a deal, and the chips are counted', () => {
    const g = freshTable([false, true, true, true]);
    g.seats[1].chips = 5;
    expect(g.startHand(seededDeck(4))).toBe(true);
    expect(g.totalInjected).toBe(REBUY_AMOUNT);
    expect(g.seats[1].chips).toBe(5 + REBUY_AMOUNT - BOOT);
  });
});

describe('Teen Patti betting', () => {
  it('a blind stake costs the base, and a chaal stake costs double once seen', () => {
    const g = dealtTable([['AS', '9S', '4D'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    expect(g.bet(1)).toBe(true);
    expect(g.seats[1].chips).toBe(STARTING_CHIPS - BOOT - START_BASE);
    expect(g.seats[1].lastAction).toEqual({ kind: 'blind', amount: START_BASE });
    expect(g.currentTurn).toBe(2);

    expect(g.see(2)).toBe(true);
    expect(g.bet(2)).toBe(true);
    expect(g.seats[2].chips).toBe(STARTING_CHIPS - BOOT - 2 * START_BASE);
    expect(g.seats[2].lastAction).toEqual({ kind: 'chaal', amount: 2 * START_BASE });
    expect(booksBalance(g)).toBe(true);
  });

  it('seeing your cards is free, is not a turn, and happens once', () => {
    const g = dealtTable([['AS', '9S', '4D'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    expect(g.see(3)).toBe(true);
    expect(g.currentTurn).toBe(1);
    expect(g.see(3)).toBe(false);
    expect(g.seats[3].chips).toBe(STARTING_CHIPS - BOOT);
  });

  it('the fourth blind opens the cards', () => {
    const g = dealtTable([['AS', '9S', '4D'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    g.seats[1].blindTurns = 3;
    expect(g.bet(1)).toBe(true);
    expect(g.seats[1].blindTurns).toBe(4);
    expect(g.seats[1].isSeen).toBe(true);
  });

  it('raising doubles the base, and stops at the maximum', () => {
    const g = dealtTable([['AS', '9S', '4D'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    expect(g.raise(1)).toBe(true);
    expect(g.baseBet).toBe(START_BASE * 2);
    expect(g.seats[1].lastAction).toEqual({ kind: 'raise', amount: START_BASE * 2 });
    g.baseBet = MAX_BASE;
    g.currentTurn = 2;
    expect(g.canRaise(2)).toBe(false);
  });

  it('packing the second-last seat ends the hand for the last one, who takes the pot', () => {
    const g = dealtTable([['AS', '9S', '4D'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    expect(g.pack(1)).toBe(true);
    expect(g.pack(2)).toBe(true);
    expect(g.pack(3)).toBe(true);
    expect(g.phase).toBe('roundOver');
    expect(g.result?.winners).toEqual([0]);
    expect(g.result?.wasShowdown).toBe(false);
    expect(g.seats[0].chips).toBe(STARTING_CHIPS - BOOT + 4 * BOOT);
    expect(g.pot).toBe(0);
    expect(booksBalance(g)).toBe(true);
  });
});

describe('Teen Patti show and showdown', () => {
  it('a show needs two players, and the better hand takes the pot', () => {
    const g = dealtTable([['AS', 'KS', 'QS'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    expect(g.pack(1)).toBe(true);
    expect(g.currentTurn).toBe(2);
    expect(g.canShow(2)).toBe(false);
    expect(g.pack(2)).toBe(true);
    expect(g.currentTurn).toBe(3);
    expect(g.show(3)).toBe(true);
    expect(g.phase).toBe('roundOver');
    expect(g.result?.winners).toEqual([0]);
    expect(booksBalance(g)).toBe(true);
  });

  it('a tie splits the pot, and the books still balance', () => {
    const g = dealtTable([['AH', '5C', 'AD'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['AS', '5D', 'AC']]);
    expect(g.pack(1)).toBe(true);
    expect(g.pack(2)).toBe(true);
    expect(g.currentTurn).toBe(3);
    expect(g.show(3)).toBe(true);
    expect([...(g.result?.winners ?? [])].sort()).toEqual([0, 3]);
    expect(g.result?.wasShowdown).toBe(true);
    expect(booksBalance(g)).toBe(true);
  });

  it('a showdown reveals only the hands in it, and packed hands stay hidden', () => {
    const g = dealtTable([['AS', 'KS', 'QS'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    g.pack(1);
    g.pack(2);
    g.show(3);
    expect(Object.keys(g.revealed ?? {}).sort()).toEqual(['0', '3']);
    expect(hiddenCardsStayHidden(g)).toBe(true);
  });

  it('the pot limit forces a show', () => {
    const g = dealtTable([['AS', 'KS', 'QS'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    g.pot = POT_LIMIT - START_BASE;
    expect(g.bet(1)).toBe(true);
    expect(g.phase).toBe('roundOver');
    expect(g.result?.potLimitReached).toBe(true);
    expect(g.result?.wasShowdown).toBe(true);
  });
});

describe('Teen Patti sideshow', () => {
  // Every seat has seen its cards and paid the chaal, so a sideshow is allowed.
  const SIDESHOW_HANDS = [['2S', '5H', '9D'], ['KH', 'KD', '3C'], ['AS', '7S', '2C'], ['QH', 'QD', 'QS']];

  function seenTable(isBot: boolean[] = HUMANS): TeenPattiGame {
    const g = dealtTable(SIDESHOW_HANDS, isBot);
    g.see(1);
    g.bet(1);
    g.see(2);
    g.bet(2);
    g.see(3);
    return g;
  }

  it('a person is asked, and the reply decides the hand', () => {
    const g = seenTable();
    expect(g.requestSideshow(3)).toBe(true);
    expect(g.phase).toBe('awaitingSideshowReply');
    expect(g.pendingSideshow).toEqual({ from: 3, to: 2 });
    expect(g.replySideshow(2, true)).toBe(true);
    expect(g.seats[2].isFolded).toBe(true);
    expect(g.seats[3].isFolded).toBe(false);
    expect(g.phase).toBe('betting');
    expect(g.currentTurn).toBe(0);
    expect(booksBalance(g)).toBe(true);
  });

  it('a tie in a sideshow goes against the player who asked', () => {
    const g = dealtTable([['2S', '5H', '9D'], ['KH', 'KD', '3C'], ['AS', 'AC', '5D'], ['AH', 'AD', '5C']]);
    g.see(1);
    g.bet(1);
    g.see(2);
    g.bet(2);
    g.see(3);
    expect(g.requestSideshow(3)).toBe(true);
    expect(g.replySideshow(2, true)).toBe(true);
    expect(g.seats[3].isFolded).toBe(true);
    expect(g.seats[2].isFolded).toBe(false);
  });

  it('declining a sideshow passes the turn, and nobody packs', () => {
    const g = seenTable();
    expect(g.requestSideshow(3)).toBe(true);
    expect(g.replySideshow(2, false)).toBe(true);
    expect(g.seats.some((s) => s.isFolded)).toBe(false);
    expect(g.currentTurn).toBe(0);
  });

  it('a bot answers from its own hand: a weak one declines, a fair one settles it', () => {
    const declined = seenTable([false, false, true, false]);
    expect(declined.requestSideshow(3)).toBe(true);
    expect(declined.phase).toBe('betting');
    expect(declined.seats[2].isFolded).toBe(false);
    expect(declined.lastEvent?.type).toBe('sideshowDeclined');

    const settled = dealtTable([['2S', '5H', '9D'], ['KH', 'KD', '3C'], ['QS', 'JS', 'JD'], ['QH', 'QD', 'QC']], [
      false,
      false,
      true,
      false,
    ]);
    settled.see(1);
    settled.bet(1);
    settled.see(2);
    settled.bet(2);
    settled.see(3);
    expect(settled.requestSideshow(3)).toBe(true);
    expect(settled.phase).toBe('betting');
    expect(settled.seats[2].isFolded).toBe(true);
    expect(handStrength(['AS', '7S', '2C'])).toBeLessThan(0.45);
  });
});

describe('Teen Patti seats leaving, and rebuys', () => {
  it('a seat that leaves on its turn passes the turn on', () => {
    const g = dealtTable([['AS', '9S', '4D'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    g.seatLeft(1);
    expect(g.seats[1].isFolded).toBe(true);
    expect(g.seats[1].lastAction).toEqual({ kind: 'left', amount: null });
    expect(g.currentTurn).toBe(2);
    expect(booksBalance(g)).toBe(true);
  });

  it('a sideshow ends when the person being asked leaves', () => {
    const g = dealtTable([['2S', '5H', '9D'], ['KH', 'KD', '3C'], ['AS', '7S', '2C'], ['QH', 'QD', 'QS']]);
    g.see(1);
    g.bet(1);
    g.see(2);
    g.bet(2);
    g.see(3);
    expect(g.requestSideshow(3)).toBe(true);
    g.seatLeft(2);
    expect(g.phase).toBe('betting');
    expect(g.pendingSideshow).toBeNull();
  });

  it('a rebuy is allowed only when short of the buy-in, and between hands or while sitting out', () => {
    const g = dealtTable([['AS', '9S', '4D'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    g.seats[1].chips = MIN_BUY_IN - 1;
    expect(g.rebuy(1)).toBe(false);
    g.phase = 'roundOver';
    expect(g.rebuy(1)).toBe(true);
    expect(g.seats[1].chips).toBe(MIN_BUY_IN - 1 + REBUY_AMOUNT);
    expect(g.totalInjected).toBe(REBUY_AMOUNT);
  });
});

describe('Teen Patti table over whole matches', () => {
  it('the chips balance, no hidden card reaches the public state, and a restored table plays the same', () => {
    for (let seed = 0; seed < 25; seed++) {
      const rnd = prng(seed + 500);
      const g = freshTable([false, true, false, true], seed);
      let deals = 0;
      let steps = 0;
      while (deals < 6 && steps++ < 4000) {
        if (g.phase === 'roundOver') {
          if (!g.startHand(seededDeck(seed * 100 + deals))) break;
          deals++;
        } else if (g.phase === 'awaitingSideshowReply') {
          expect(g.pendingSideshow).not.toBeNull();
          g.replySideshow(g.pendingSideshow?.to ?? 0, rnd() < 0.5);
        } else if (g.isBot[g.currentTurn]) {
          expect(g.advance(false)).toBe('bot');
        } else {
          humanMove(g, g.currentTurn, rnd);
        }
        expect(booksBalance(g)).toBe(true);
        expect(hiddenCardsStayHidden(g)).toBe(true);
        expect(restoredMatches(g)).toBe(true);
      }
      expect(deals).toBeGreaterThan(0);
    }
  });

  it('a bot never waits on a person, and a person who runs out of time packs', () => {
    const g = dealtTable([['AS', '9S', '4D'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']]);
    expect(g.turnDeadline(1_000)).toBe(1_000 + 60_000);
    expect(g.advance(false)).toBeNull();
    expect(g.advance(true)).toBe('auto');
    expect(g.seats[1].isFolded).toBe(true);

    const bots = dealtTable([['AS', '9S', '4D'], ['2H', '7D', '9C'], ['3C', 'JS', '6H'], ['JC', 'JD', '8H']], [
      true,
      true,
      true,
      true,
    ]);
    expect(bots.turnDeadline(1_000)).toBeNull();
    expect(bots.advance(false)).toBe('bot');
  });
});
