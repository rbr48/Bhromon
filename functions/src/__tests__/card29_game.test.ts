import { Card29Game, Card29RuleError, HumanAction, publicState, restoreGame, seatDoc } from '../card29/game';
import { PlayedCard, Suit, SUITS, fullDeck, legalPlays, suitOf, teamOf, trickWinner } from '../card29/cards';

const HUMANS = [false, false, false, false];
const BOTS = [true, true, true, true];

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

/** Puts a game straight into play with chosen hands, bidder and trump. */
function playing(
  hands: string[][],
  opts: { bidder?: number; trump?: Suit; bid?: number; leader?: number; isBot?: boolean[] } = {},
): Card29Game {
  const g = new Card29Game(opts.isBot ?? HUMANS, prng(1));
  for (let i = 0; i < 4; i++) g.hands[i] = [...hands[i]];
  g.phase = 'playing';
  g.highestBidder = opts.bidder ?? 0;
  g.highestBid = opts.bid ?? 16;
  g.bidTarget = opts.bid ?? 16;
  g.trump = opts.trump ?? 'hearts';
  g.currentTurn = opts.leader ?? 0;
  return g;
}

const codes = (cards: string[]): string[] => [...cards].sort();

/** The legal-card rule, written independently from the documented rules. */
function expectedLegal(g: Card29Game, seat: number): string[] {
  const hand = g.hands[seat];
  if (g.leadSuit === null) {
    if (!g.revealed && seat === g.highestBidder) {
      const nonTrump = hand.filter((c) => suitOf(c) !== g.trump);
      return codes(nonTrump.length > 0 ? nonTrump : hand);
    }
    return codes(hand);
  }
  const follows = hand.filter((c) => suitOf(c) === g.leadSuit);
  if (follows.length > 0) return codes(follows);
  if (g.revealed && g.currentTrick.length > 0) {
    const winner = trickWinner(g.currentTrick, g.trump, true);
    if (teamOf(winner.seat) === teamOf(seat)) return codes(hand);
    const winnerIsTrump =
      suitOf(winner.card) === g.trump && (winner.trumpEligible || suitOf(winner.card) === g.leadSuit);
    const trumps = hand.filter((c) => suitOf(c) === g.trump);
    if (winnerIsTrump) {
      const higher = trumps.filter((c) => power(c) > power(winner.card));
      return codes(higher.length > 0 ? higher : hand);
    }
    if (trumps.length > 0) return codes(trumps);
  }
  return codes(hand);
}

function power(card: string): number {
  return { J: 8, '9': 7, A: 6, '10': 5, K: 4, Q: 3, '8': 2, '7': 1 }[card.slice(0, -1)] ?? 0;
}

describe('Card 29 play rules (ported from the app tests)', () => {
  it('no card can be played while a finished trick is on the table', () => {
    const g = playing(
      [
        ['7S', '8S'],
        ['9S', 'KS'],
        ['QS', 'AS'],
        ['10S', 'JS'],
      ],
      { leader: 1 },
    );
    expect(g.playCard(1, '9S')).toBe(true);
    expect(g.playCard(2, 'QS')).toBe(true);
    expect(g.playCard(3, '10S')).toBe(true);
    expect(g.playCard(0, '7S')).toBe(true);
    expect(g.phase).toBe('trickComplete');
    expect(g.legalCards(0)).toEqual([]);
    expect(g.playCard(0, '8S')).toBe(false);
    g.resolveTrick();
    expect(g.phase).toBe('playing');
    expect(g.currentTurn).toBe(1); // 9S outranks 10S and QS
    expect(g.teamPoints[1]).toBe(3); // 9 (2) + 10 (1)
  });

  it('a void player must trump when an opponent is winning, but not when a partner is', () => {
    const g = playing(
      [
        ['7S', '8S'],
        ['7H', '8D'],
        ['7C', '8C'],
        ['9C', 'KC'],
      ],
      { bidder: 2, trump: 'hearts', leader: 3 },
    );
    g.revealed = true;
    expect(g.playCard(3, '9C')).toBe(true);
    expect(codes(g.legalCards(0))).toEqual(codes(['7S', '8S']));

    // West (3) is East's partner and is winning, so East is not forced to trump.
    g.currentTurn = 1;
    expect(codes(g.legalCards(1))).toEqual(codes(['7H', '8D']));

    // North leads and wins; East is void in clubs and holds a heart, so must trump.
    const opp = playing(
      [
        ['7S', '8S'],
        ['7H', '8D'],
        ['JC', '8C'],
        ['9C', 'KC'],
      ],
      { bidder: 2, trump: 'hearts', leader: 2 },
    );
    opp.revealed = true;
    expect(opp.playCard(2, 'JC')).toBe(true);
    opp.currentTurn = 1;
    expect(opp.legalCards(1)).toEqual(['7H']);
  });

  it('a void player below the winning trump is not forced to under-trump', () => {
    const g = playing(
      [
        ['8D', '9S', 'AS', '10C'],
        ['7H', '8H'],
        ['JH', '9H'],
        ['KD', '8S'],
      ],
      { bidder: 3, trump: 'diamonds', leader: 1 },
    );
    g.revealed = true;
    expect(g.playCard(1, '7H')).toBe(true);
    expect(g.playCard(2, 'JH')).toBe(true);
    expect(g.playCard(3, 'KD')).toBe(true);
    expect(g.currentTurn).toBe(0);
    expect(codes(g.legalCards(0))).toEqual(codes(['8D', '9S', 'AS', '10C']));
  });

  it('a hidden trump discarded before the reveal does not trump the trick', () => {
    const g = playing(
      [
        ['7C', '8C'],
        ['JH', 'KD'],
        ['9C', 'QD'],
        ['AC', 'KC'],
      ],
      { bidder: 0, trump: 'hearts', leader: 0 },
    );
    expect(g.playCard(0, '7C')).toBe(true);
    expect(g.playCard(1, 'JH')).toBe(true);
    expect(g.revealed).toBe(false);
    expect(g.playCard(2, '9C')).toBe(true);
    expect(g.playCard(3, 'AC')).toBe(true);
    expect(g.trickWinnerSeat).toBe(2);
  });

  it('the bidder reveals trump by playing it while void', () => {
    const g = playing(
      [
        ['7H', '8D'],
        ['7C', '8C'],
        ['9C', 'QC'],
        ['AC', 'KC'],
      ],
      { bidder: 0, trump: 'hearts', leader: 1 },
    );
    expect(g.canAskTrump(0)).toBe(false);
    g.playCard(1, '7C');
    g.playCard(2, '9C');
    g.playCard(3, 'AC');
    expect(g.playCard(0, '7H')).toBe(true);
    expect(g.revealed).toBe(true);
    expect(g.trickWinnerSeat).toBe(0);
  });

  it('the bidder may not lead the hidden trump suit', () => {
    const g = playing([['JH', '7S'], ['7C'], ['8C'], ['9C']], { bidder: 0, trump: 'hearts' });
    expect(g.legalCards(0)).toEqual(['7S']);
  });

  it('the pair lowers the bidding team target and raises it for the opponents', () => {
    const mine = playing([['KH', 'QH'], ['7C'], ['8C'], ['9C']], { bidder: 0, bid: 20 });
    mine.revealed = true;
    expect(mine.claimRoyalty(0)).toBe(true);
    expect(mine.bidTarget).toBe(16);
    expect(mine.claimRoyalty(0)).toBe(false);

    const theirs = playing([['7C'], ['KH', 'QH'], ['8C'], ['9C']], { bidder: 0, bid: 26 });
    theirs.revealed = true;
    expect(theirs.claimRoyalty(1)).toBe(true);
    expect(theirs.bidTarget).toBe(28);
  });

  it('the reveal by the bidder while void is announced as a reveal', () => {
    const g = playing([['7H', '8H'], ['7C', '8C'], ['9C', 'KC'], ['10C', 'JC']], { bidder: 0, leader: 1 });
    g.playCard(1, '7C');
    g.playCard(2, '9C');
    g.playCard(3, '10C');
    expect(g.currentTurn).toBe(0);
    expect(g.canRevealTrump(0)).toBe(true);
    expect(g.revealTrump(0)).toBe(true);
    expect(g.revealed).toBe(true);
    expect(g.revealedBy).toBe(0);
    expect(g.canRevealTrump(0)).toBe(false);
  });
});

describe('Card 29 bidding and match', () => {
  it('a pass is final, and all passes make the dealer play at 16', () => {
    const g = new Card29Game(BOTS, prng(3));
    g.startRound(seededDeck(3));
    const first = g.currentTurn;
    expect(first).toBe((g.dealer + 1) % 4);
    for (let i = 0; i < 4; i++) expect(g.pass(g.currentTurn)).toBe(true);
    expect(g.highestBidder).toBe(g.dealer);
    expect(g.highestBid).toBe(16);
    expect(g.phase).toBe('playing');
  });

  it('a human bidder must pick the trump before the second half is dealt', () => {
    const g = new Card29Game(HUMANS, prng(4));
    g.startRound(seededDeck(4));
    g.currentTurn = 0;
    expect(g.placeBid(0, 16)).toBe(true);
    g.pass(1);
    g.pass(2);
    g.pass(3);
    expect(g.phase).toBe('trumpSelection');
    expect(g.hands[0]).toHaveLength(4);
    expect(g.selectTrump(0, 'clubs')).toBe(true);
    expect(g.hands[0]).toHaveLength(8);
    expect(g.phase).toBe('playing');
  });

  it('a bid may not go below the minimum or past 28', () => {
    const g = new Card29Game(HUMANS, prng(5));
    g.startRound(seededDeck(5));
    g.currentTurn = 0;
    expect(g.placeBid(0, 15)).toBe(false);
    expect(g.placeBid(0, 29)).toBe(false);
    expect(g.placeBid(0, 16)).toBe(true);
  });

  it('starting a new match clears the pips', () => {
    const g = new Card29Game(BOTS, prng(6));
    g.startRound(seededDeck(6));
    g.matchPips = [6, 2];
    g.phase = 'matchOver';
    g.startRound(seededDeck(7));
    expect(g.matchPips).toEqual([0, 0]);
    expect(g.phase).toBe('bidding');
  });
});

describe('Card 29 whole matches and the rules', () => {
  it('bots only ever play legal cards, each deal scores 29, and every match ends', () => {
    for (let seed = 0; seed < 25; seed++) {
      const g = new Card29Game(BOTS, prng(seed));
      g.newMatch(seededDeck(seed));
      let deals = 0;
      let steps = 0;
      while (g.phase !== 'matchOver') {
        if (++steps > 20000) throw new Error(`seed ${seed} did not finish`);
        if (g.phase === 'roundOver') {
          expect(g.teamPoints[0] + g.teamPoints[1]).toBe(29);
          deals++;
          g.startRound(seededDeck(seed * 1000 + deals));
          continue;
        }
        // Before any ask, the legal cards are the ones the bot's card must come from.
        const before = g.phase === 'playing' ? g.legalCards(g.currentTurn) : [];
        const wasRevealed = g.revealed;
        const playedBefore = g.playedCards.length;
        g.advance(false);
        if (!wasRevealed && g.playedCards.length > playedBefore) {
          expect(before).toContain(g.playedCards[g.playedCards.length - 1]);
        }
      }
    }
  });

  it('the legal-card rule matches the written rule across random human deals', () => {
    let checked = 0;
    for (let seed = 0; seed < 120; seed++) {
      const rnd = prng(seed + 99);
      const g = new Card29Game(HUMANS, prng(seed));
      g.newMatch(seededDeck(seed));
      let steps = 0;
      while (g.phase !== 'matchOver' && steps++ < 3000) {
        const p = g.currentTurn;
        switch (g.phase) {
          case 'bidding':
            if (rnd() < 0.6) g.placeBid(p, Math.min(28, g.minimumNextBid() + Math.floor(rnd() * 3)));
            if (g.phase === 'bidding' && g.currentTurn === p) g.pass(p);
            break;
          case 'trumpSelection':
            g.selectTrump(p, SUITS[Math.floor(rnd() * 4)]);
            break;
          case 'playing': {
            if (g.canClaimRoyalty(p) && rnd() < 0.5) g.claimRoyalty(p);
            if (g.canAskTrump(p) && rnd() < 0.5) g.askTrump(p);
            if (g.canRevealTrump(p) && rnd() < 0.5) g.revealTrump(p);
            const actual = codes(g.legalCards(p));
            expect(actual).toEqual(expectedLegal(g, p));
            expect(actual.length).toBeGreaterThan(0);
            checked++;
            const pick = g.legalCards(p)[Math.floor(rnd() * g.legalCards(p).length)];
            expect(g.playCard(p, pick)).toBe(true);
            break;
          }
          case 'trickComplete':
            g.resolveTrick();
            break;
          case 'roundOver':
            g.startRound(seededDeck(seed * 7 + steps));
            break;
          default:
            break;
        }
      }
    }
    expect(checked).toBeGreaterThan(1000);
  });
});

describe('Card 29 table privacy', () => {
  it('the public state never holds a hand, the second half, or a hidden trump', () => {
    const g = new Card29Game(HUMANS, prng(11));
    g.startRound(seededDeck(11));
    g.currentTurn = 0;
    g.placeBid(0, 17);
    g.pass(1);
    g.pass(2);
    g.pass(3);
    g.selectTrump(0, 'spades');
    const json = JSON.stringify(publicState(g, 5, Date.now()));
    expect(json).not.toContain('"hand"');
    expect(json).not.toContain('"pending"');
    expect(json).not.toContain('"spades"');
    expect(publicState(g, 5, Date.now()).trumpSuit).toBeNull();
  });

  it('only the bidder holds the trump in their seat document', () => {
    const g = new Card29Game(BOTS, prng(12));
    g.startRound(seededDeck(12));
    g.placeBid(g.currentTurn, 16);
    while (g.phase === 'bidding') g.pass(g.currentTurn);
    const bidder = g.highestBidder;
    for (let seat = 0; seat < 4; seat++) {
      const doc = seatDoc(g, seat, `s${seat}@x.com`);
      expect(doc.trumpSuit).toBe(seat === bidder ? g.trump : null);
    }
  });

  it('the public trump appears once revealed', () => {
    const g = playing([['7H', '8D'], ['7C', '8C'], ['9C', 'QC'], ['AC', 'KC']], { bidder: 0, trump: 'hearts', leader: 1 });
    g.playCard(1, '7C');
    g.playCard(2, '9C');
    g.playCard(3, 'AC');
    g.playCard(0, '7H');
    expect(publicState(g, 9, Date.now()).trumpSuit).toBe('hearts');
  });

  it('a table restored from storage plays the same legal cards', () => {
    const g = new Card29Game(BOTS, prng(13));
    g.newMatch(seededDeck(13));
    let steps = 0;
    while (g.phase === 'bidding' && steps++ < 50) g.advance(false);
    while (g.phase !== 'playing' && steps++ < 100) g.advance(false);
    for (let i = 0; i < 6; i++) g.advance(false);

    const state = JSON.parse(JSON.stringify(publicState(g, 3, Date.now())));
    const seats = [0, 1, 2, 3].map((s) => JSON.parse(JSON.stringify(seatDoc(g, s, `s${s}`))));
    const restored = restoreGame(state, seats, BOTS, prng(99));
    expect(restored.phase).toBe(g.phase);
    expect(restored.currentTurn).toBe(g.currentTurn);
    for (let seat = 0; seat < 4; seat++) {
      expect(codes(restored.legalCards(seat))).toEqual(codes(g.legalCards(seat)));
    }
  });
});

describe('Card 29 human actions', () => {
  const deck = () => seededDeck(21);

  it('refuses an action from the wrong seat or an illegal card', () => {
    const g = playing([['7S', '8S'], ['9S', 'KS'], ['QS', 'AS'], ['10S', 'JS']], { leader: 1 });
    const attempt = (seat: number, action: HumanAction): void => g.applyHuman(seat, action, deck);
    expect(() => attempt(0, { type: 'play', card: '7S' })).toThrow(Card29RuleError);
    expect(() => attempt(1, { type: 'play', card: '7S' })).toThrow(Card29RuleError);
    expect(() => attempt(1, { type: 'bid', bid: 16 })).toThrow(Card29RuleError);
    expect(() => attempt(1, { type: 'nextDeal' })).toThrow(Card29RuleError);
    attempt(1, { type: 'play', card: '9S' });
    expect(g.currentTurn).toBe(2);
  });

  it('the table plays for a human whose time has run out', () => {
    const g = new Card29Game([false, true, true, true], prng(31));
    g.startRound(seededDeck(31));
    g.currentTurn = 0;
    expect(g.advance(false)).toBeNull();
    expect(g.advance(true)).toBe('auto');
    expect(g.currentTurn).toBe(1);
    expect(g.lastEvent?.type).toBe('pass');
  });

  it('a bot takes its turn only when asked, and a finished trick waits to be collected', () => {
    const g = playing([['7S', '8S'], ['9S', 'KS'], ['QS', 'AS'], ['10S', 'JS']], { leader: 1, isBot: BOTS });
    expect(g.advance(false)).toBe('bot');
    expect(g.playedCards).toHaveLength(1);
    expect(g.advance(false)).toBe('bot');
    expect(g.advance(false)).toBe('bot');
    expect(g.advance(false)).toBe('bot');
    expect(g.phase).toBe('trickComplete');
    expect(g.advance(false)).toBe('resolve');
    expect(g.phase).toBe('playing');
  });

  it('the turn deadline is set only while a human is awaited', () => {
    const now = 1_000;
    const human = playing([['7S'], ['8S'], ['9S'], ['10S']], { leader: 0, isBot: HUMANS });
    expect(human.turnDeadline(now)).toBe(now + 60_000);
    const bots = playing([['7S'], ['8S'], ['9S'], ['10S']], { leader: 0, isBot: BOTS });
    expect(bots.turnDeadline(now)).toBeNull();
  });
});

describe('Card 29 trick helper', () => {
  it('a pre-reveal trump discard does not win the trick', () => {
    const trick: PlayedCard[] = [
      { seat: 0, card: '7C', trumpEligible: true },
      { seat: 1, card: 'JH', trumpEligible: false },
      { seat: 2, card: '8C', trumpEligible: true },
      { seat: 3, card: '7H', trumpEligible: true },
    ];
    expect(trickWinner(trick, 'hearts', true).seat).toBe(3);
  });

  it('with nothing to follow yet, every card in hand may lead', () => {
    const cards = legalPlays({
      hand: ['7S'],
      seat: 0,
      leadSuit: null,
      trick: [],
      trump: 'hearts' as Suit,
      revealed: false,
      highestBidder: 1,
    });
    expect(cards).toEqual(['7S']);
  });
});
