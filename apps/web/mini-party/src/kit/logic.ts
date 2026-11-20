/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// Pure helpers shared by the games: a seeded random source and the match
// playlist. No React here, so they can be unit tested.

/**
 * A small, fast seeded random number generator (mulberry32). The same seed
 * always gives the same sequence, so every player in a round, on any device,
 * gets the same puzzles, mazes and dice rolls.
 */
export function seededRandom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** A whole number in [min, max], inclusive. */
export function randInt(rand: () => number, min: number, max: number) {
  return min + Math.floor(rand() * (max - min + 1));
}

/** A random element of a non-empty list. */
export function pick<T>(rand: () => number, items: readonly T[]): T {
  return items[Math.floor(rand() * items.length)];
}

/** A shuffled copy (Fisher-Yates). */
export function shuffle<T>(rand: () => number, items: readonly T[]): T[] {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/** Turns any string (a room code) into a 32-bit seed (FNV-1a). */
export function hashString(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/**
 * The seed for one round. Every device in a room knows the room code and the
 * round number, so they all arrive at the same seed without sending it.
 */
export function roundSeed(roomId: string | null, round: number, gameIndex: number) {
  return hashString(`${roomId ?? "local"}:${round}:${gameIndex}`);
}

/** How many games one match plays. */
export const ROUNDS_PER_MATCH = 10;

/**
 * Picks the next game: a random one not yet played this match. Falls back to
 * any game once every game has been played.
 */
export function nextGameIndex(
  rand: () => number,
  gameCount: number,
  played: readonly number[],
): number {
  const fresh = Array.from({ length: gameCount }, (_, i) => i).filter(
    (i) => !played.includes(i),
  );
  const pool = fresh.length > 0 ? fresh : Array.from({ length: gameCount }, (_, i) => i);
  return pick(rand, pool);
}
