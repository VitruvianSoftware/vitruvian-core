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
import { createAnalytics } from "./analytics";

function recorder() {
  const calls: [string, Record<string, string | number> | undefined][] = [];
  return {
    calls,
    tracker: {
      track: (e: string, d?: Record<string, string | number>) =>
        calls.push([e, d]),
    },
  };
}

describe("analytics", () => {
  it("sends each event with its name and data", () => {
    const { calls, tracker } = recorder();
    const a = createAnalytics(() => tracker);
    a.matchStarted("online", 3);
    a.gameStarted("online", "gear", 1);
    a.gameFinished("online", "gear", 1, 120);
    a.matchFinished("online", 3, 10);
    expect(calls).toEqual([
      ["match-start", { mode: "online", players: 3 }],
      ["game-start", { mode: "online", game: "gear", round: 1 }],
      [
        "game-finish",
        { mode: "online", game: "gear", round: 1, topScore: 120 },
      ],
      ["match-finish", { mode: "online", players: 3, rounds: 10 }],
    ]);
  });

  it("does nothing when the tracker is not loaded", () => {
    const a = createAnalytics(() => undefined);
    expect(() => a.gameStarted("local", "math", 1)).not.toThrow();
  });

  it("picks up a tracker that loads after the first call", () => {
    const { calls, tracker } = recorder();
    let loaded: typeof tracker | undefined;
    const a = createAnalytics(() => loaded);
    a.gameStarted("local", "math", 1);
    loaded = tracker;
    a.gameStarted("local", "sum", 2);
    expect(calls).toEqual([
      ["game-start", { mode: "local", game: "sum", round: 2 }],
    ]);
  });

  it("never lets a failing tracker break the game", () => {
    const a = createAnalytics(() => ({
      track: () => {
        throw new Error("blocked");
      },
    }));
    expect(() => a.matchFinished("local", 2, 10)).not.toThrow();
  });
});
