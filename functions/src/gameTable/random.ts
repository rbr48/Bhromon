import { randomInt } from 'crypto';

/** Cryptographically random, uniform in [0, 1). The table's shuffles and bot choices use it. */
export function secureRandom(): number {
  return randomInt(0, 1_000_000) / 1_000_000;
}
