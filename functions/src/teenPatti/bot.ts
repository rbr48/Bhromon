/**
 * The bots' play, ported from TeenPattiGame.playBotTurn in the phone's offline
 * game. A bot reads only its own cards, and it acts through the same rules as
 * a person, so it can never make a move a person could not make.
 */

import type { TeenPattiGame } from './game';
import { MAX_BASE } from './rules';
import { handStrength } from './cards';

/** Plays one action for the bot whose turn it is. */
export function playBotTurn(g: TeenPattiGame, seat: number, random: () => number): void {
  const bot = g.seats[seat];

  if (!bot.isSeen && (bot.blindTurns >= 2 || g.pot > 120 || random() < 0.15)) {
    g.see(seat);
  }
  if (!g.canBet(seat)) {
    g.pack(seat);
    return;
  }

  if (!bot.isSeen) {
    if (random() < 0.1 && g.canRaise(seat)) {
      g.raise(seat);
    } else {
      g.bet(seat);
    }
    return;
  }

  const strength = handStrength(bot.hand) + (random() - 0.5) * 0.1;
  const activeCount = g.activeCount();

  if (activeCount === 2 && strength >= 0.55 && g.pot >= 100 && g.canShow(seat)) {
    g.show(seat);
    return;
  }
  const foldBelow = 0.12 + (g.baseBet / MAX_BASE) * 0.25 + (g.pot > 300 ? 0.05 : 0);
  if (strength < foldBelow) {
    g.pack(seat);
    return;
  }
  if (strength > 0.75 && g.canRaise(seat) && random() < 0.5) {
    g.raise(seat);
    return;
  }
  if (activeCount > 2 && strength >= 0.35 && strength <= 0.7 && g.canSideshow(seat) && random() < 0.25) {
    g.requestSideshow(seat);
    return;
  }
  if (activeCount === 2 && g.pot >= 300 && strength >= 0.3 && g.canShow(seat)) {
    g.show(seat);
    return;
  }
  g.bet(seat);
}

/** A bot answering a sideshow asked by a seat: it looks at its cards and accepts a fair hand. */
export function botAcceptsSideshow(g: TeenPattiGame, seat: number): boolean {
  if (!g.seats[seat].isSeen) g.see(seat);
  return handStrength(g.seats[seat].hand) >= 0.45;
}
