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

// Game analytics for the self-hosted Umami (stats.vitruviansoftware.dev).
// The tracker script is only on the GitHub Pages build (vite.config.ts), so
// these calls do nothing locally. Only the device that decides what happens
// next reports it -- the only device in local play, the host online -- so an
// online round counts once, not once per player.

export type PlayMode = "local" | "online";

type EventData = Record<string, string | number>;

interface UmamiTracker {
  track(event: string, data?: EventData): unknown;
}

export interface Analytics {
  matchStarted(mode: PlayMode, players: number): void;
  gameStarted(mode: PlayMode, game: string, round: number): void;
  gameFinished(
    mode: PlayMode,
    game: string,
    round: number,
    topScore: number,
  ): void;
  matchFinished(mode: PlayMode, players: number, rounds: number): void;
}

// Reads the tracker at call time: the script loads with `defer`, so it may
// arrive after the first render. Analytics never breaks the game, so a
// missing or failing tracker is ignored.
export function createAnalytics(
  getTracker: () => UmamiTracker | undefined,
): Analytics {
  const send = (event: string, data: EventData) => {
    try {
      getTracker()?.track(event, data);
    } catch {
      // ignored on purpose
    }
  };
  return {
    matchStarted: (mode, players) => send("match-start", { mode, players }),
    gameStarted: (mode, game, round) =>
      send("game-start", { mode, game, round }),
    gameFinished: (mode, game, round, topScore) =>
      send("game-finish", { mode, game, round, topScore }),
    matchFinished: (mode, players, rounds) =>
      send("match-finish", { mode, players, rounds }),
  };
}

export const analytics = createAnalytics(() =>
  typeof window === "undefined"
    ? undefined
    : (window as Window & { umami?: UmamiTracker }).umami,
);
