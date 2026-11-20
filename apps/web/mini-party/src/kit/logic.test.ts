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

import { describe, expect, it } from "vitest";
import {
  hashString,
  nextGameIndex,
  randInt,
  roundSeed,
  seededRandom,
  shuffle,
} from "./logic";

describe("seededRandom", () => {
  it("gives the same sequence for the same seed", () => {
    const a = seededRandom(42);
    const b = seededRandom(42);
    const seqA = Array.from({ length: 20 }, a);
    const seqB = Array.from({ length: 20 }, b);
    expect(seqA).toEqual(seqB);
  });

  it("gives different sequences for different seeds", () => {
    expect(seededRandom(1)()).not.toEqual(seededRandom(2)());
  });

  it("stays in [0, 1)", () => {
    const r = seededRandom(7);
    for (let i = 0; i < 10_000; i++) {
      const v = r();
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThan(1);
    }
  });
});

describe("randInt", () => {
  it("covers both ends of the range and nothing outside it", () => {
    const r = seededRandom(3);
    const seen = new Set<number>();
    for (let i = 0; i < 2000; i++) seen.add(randInt(r, 1, 6));
    expect([...seen].sort()).toEqual([1, 2, 3, 4, 5, 6]);
  });
});

describe("shuffle", () => {
  it("keeps every element and leaves the input alone", () => {
    const input = [1, 2, 3, 4, 5, 6, 7, 8];
    const out = shuffle(seededRandom(9), input);
    expect([...out].sort()).toEqual(input);
    expect(input).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
  });
});

describe("roundSeed", () => {
  it("agrees across devices for the same room and round", () => {
    expect(roundSeed("ABC12", 3, 7)).toBe(roundSeed("ABC12", 3, 7));
  });

  it("changes from round to round", () => {
    expect(roundSeed("ABC12", 3, 7)).not.toBe(roundSeed("ABC12", 4, 7));
  });

  it("works without a room", () => {
    expect(roundSeed(null, 0, 0)).toBe(hashString("local:0:0"));
  });
});

describe("nextGameIndex", () => {
  it("never repeats a game until all have been played", () => {
    const r = seededRandom(11);
    const played: number[] = [];
    for (let i = 0; i < 42; i++) played.push(nextGameIndex(r, 42, played));
    expect(new Set(played).size).toBe(42);
  });

  it("still returns a game once every game has been played", () => {
    const all = Array.from({ length: 5 }, (_, i) => i);
    const next = nextGameIndex(seededRandom(1), 5, all);
    expect(next).toBeGreaterThanOrEqual(0);
    expect(next).toBeLessThan(5);
  });
});
